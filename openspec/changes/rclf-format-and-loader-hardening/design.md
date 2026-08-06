# Design: rclf-format-and-loader-hardening

## Context

`snips/launcher.pas` loads `LAUNCHER.DAT` with a flat scan: it reads chunk headers in
a loop, copies `INFO` payloads into `AppList[TotalApps]`, and on each `ICON` chunk
decodes into `AppList[TotalApps]` and increments `TotalApps`. This assumes INFO and
ICON strictly alternate with nothing between them — no `HDER`, no `LIST`/`APPS`
nesting, no padding, no unknown chunks. `snips/RiffDOSParser.pas` already implements
correct RIFF walking (`SkipChunk` with word alignment), so the two programs currently
disagree on what a valid file looks like. The RCLF structure (`HDER`, `LIST`/`APPS`
of `APP ` entries) is defined only in `snips/RiffLauncher.pas` constants, never
enforced.

Constraints: 16-bit real-mode DOS, Turbo Pascal dialect, 64KB max heap
(`{$M 16384, 0, 65536}`), no exceptions — `{$I-}`/`IOResult` error handling only.
The editor (separate change) will be the writer of these files; this design freezes
the read-side contract it must satisfy.

## Goals / Non-Goals

**Goals:**

- One normative definition of RCLF that reader, parser utility, and editor all share.
- `LoadLauncherData` tolerates real-world variation: unknown chunks, odd-sized chunk
  padding, missing icons, extra entries beyond `MAX_APPS`.
- Honor the already-defined-but-ignored `TAppInfo.Flags` bits.
- Zero layout changes to `RiffLauncher.pas` records — the on-disk format is frozen.

**Non-Goals:**

- Rewriting the UI, paging model, or `ExecSwap`.
- Streaming/lazy icon decode (icons stay pre-decoded; 50 × 516 bytes fits the heap).
- Backward compatibility with flat-scan files that violated the documented structure.
- A format version bump — version stays 1; the structured layout was always the intent.

## Decisions

### D1: Sequential state-machine chunk walk in `LoadLauncherData`

Replace the flat scan with an explicit walk: read root header → loop reading chunk
headers until form size exhausted or EOF → dispatch on FourCC. Nested `LIST` chunks
are handled by recursion on the list payload bounded by its declared size
(`LIST` payload = 4-byte list type + child chunks), the same shape as
`RiffDOSParser.pas`.

Rationale: matches RIFF semantics and the existing parser utility exactly.
Alternative considered: keep the flat scan and just add alignment/unknown-chunk
skips — rejected because it still cannot pair INFO/ICON correctly once a `LIST`
boundary sits between them, and it cannot detect an `APP ` entry missing its INFO.

### D2: INFO/ICON pairing rule

An `ICON` chunk attaches to the most recent `INFO` in the same `APP ` entry. Loading
commits an entry when its `APP ` list ends (or when a new `INFO` arrives in the same
entry, which per spec must not happen — treated as malformed, entry discarded).
Entries are counted (`Inc(TotalApps)`) at entry commit, not at `ICON` sighting as
today. This fixes the current off-by-one-desync where an entry without an icon
shifts every subsequent icon onto the wrong app.

### D3: Alignment and unknown chunks

After every chunk payload, if the declared size is odd, seek forward 1 byte. Unknown
FourCC → seek forward `Size + (Size and 1)`. Use `Seek(F, ...)`/`FilePos` arithmetic
rather than dummy reads (fewer I/O calls on an 8088; `RiffDOSParser` uses dummy
reads but correctness matters more than matching its technique).

### D4: Truncation and I/O guards

Every `BlockRead` result is checked via `{$I-}`/`IOResult` and byte counts. A
truncated chunk header terminates the load loop keeping entries already committed;
a truncated `INFO` discards the in-progress entry. No exceptions, per project
conventions.

### D5: Flags plumbed through launch

`TAppEntry` gains `Flags: Word`. In `RunLauncher`'s ENTER branch: bit 1 → `ClrScr`
before the loading message (already partially there — `ClrScr` is unconditional
today; make it flag-driven per spec); bit 0 → after `ExecWithSwap` returns, print a
prompt and `ReadKey` before `InitGraph`. Default flags = 0 keeps current behavior
except that the unconditional clear becomes opt-in — accepted as the spec'd behavior
since flags were always defined in the record.

## Risks / Trade-offs

- [Recursive LIST walking adds stack depth on a 16KB stack] → Only one `LIST`
  nesting level exists (`RIFF/RCLF` root → `LIST/APPS`); `APP ` entries are flat
  chunks, not a second nested `LIST` level (see `rclf-container` spec's APPS/APP
  requirement). Locals stay small; far calls already forced where needed.
- [Seek-based skipping breaks if a declared size lies] → Clamp seeks to the
  containing chunk's end boundary and to file size; a lying size terminates the loop
  rather than reading out of bounds.
- [Flag-driven `ClrScr` changes behavior for existing files with garbage flag bits]
  → Spec mandates writers emit 0 for reserved bits; editor enforces it. Files with
  random flag bytes may pause/clear unexpectedly — acceptable, format is v1 and
  pre-release.
- [Stricter parsing rejects files the old loader half-accepted] → Intentional; the
  old behavior was silent corruption. `RiffDOSParser` is the verification tool.

## Migration Plan

1. Land the spec (this change's spec deltas).
2. Rewrite `LoadLauncherData` per D1-D4; plumb flags per D5.
3. Regenerate/author `LAUNCHER.DAT` with the editor (companion change) or a small
   writer, verify with `RiffDOSParser`, then test on DOSBox and Book-8088.

## Open Questions

- Should an `APP ` entry containing multiple `INFO` chunks keep the first or discard
  the entry? (Current spec text: discard as malformed; revisit if the editor ever
  needs in-place patching semantics.)
