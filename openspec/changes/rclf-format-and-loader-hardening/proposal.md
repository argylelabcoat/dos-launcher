# Proposal: rclf-format-and-loader-hardening

## Why

The launcher's RIFF loader in `snips/launcher.pas` (`LoadLauncherData`) does not parse
the documented RCLF container structure: it scans flatly for `INFO` chunks, assumes the
next `ICON` chunk belongs to the last `INFO` seen, ignores `HDER` and the
`LIST`/`APPS`/`APP ` nesting entirely, and performs no word-alignment or unknown-chunk
skipping. Any real-world `LAUNCHER.DAT` that contains padding, unknown chunks, or a
different chunk order will desynchronize the stream and load garbage. There is also no
written contract for the RCLF format itself, so the upcoming editor has nothing
normative to target.

## What Changes

- Formalize the **RCLF container format** as a written specification: RIFF root
  (`RCLF`), `HDER` chunk, `LIST`/`APPS` wrapping `APP ` entries, `INFO` and `ICON`
  chunks, packed record layouts with TP short strings, little-endian fields, and the
  2-byte word-alignment rule.
- Harden `LoadLauncherData` in `snips/launcher.pas`:
  - Sequential chunk walk with dispatch on FourCC via `SameFourCC`.
  - Word-alignment (2-byte pad) after odd-sized chunks, matching `SkipChunk` in
    `snips/RiffDOSParser.pas`.
  - Skip unknown chunks by their declared size instead of desyncing.
  - Honor the `LIST`/`APPS` → `APP ` → `INFO`/`ICON` nesting; pair each `ICON` with
    the `INFO` of the same `APP ` entry.
  - Validate `HDER` (version, `AppCount`) and guard against EOF/truncated reads.
  - Carry `TAppInfo.Flags` into `TAppEntry` and honor bit 0 (pause on exit) and
    bit 1 (clear screen) around game launch.
- Keep the change behavior-compatible for well-formed files: a spec-compliant
  `LAUNCHER.DAT` loads identically before and after hardening.

## Capabilities

### New Capabilities

- `rclf-container`: The on-disk RIFF Container Launcher Format — chunk layout, record
  layouts, alignment, and versioning rules that both the DOS launcher and the editor
  must follow byte-for-byte.
- `launcher`: The DOS launcher application behavior — startup, RCLF loading, menu
  rendering/paging, keyboard navigation, and swap-to-disk game launch/restore.

### Modified Capabilities

(None — no specs exist under `openspec/specs/` yet.)

## Impact

- `snips/launcher.pas` — `LoadLauncherData` rewritten as a structured chunk walk;
  `TAppEntry` gains a `Flags` field; launch path honors pause/clear-screen flags.
- `snips/RiffLauncher.pas` — no layout changes (the format contract is frozen); may
  gain constants only if the spec requires them.
- `snips/RiffDOSParser.pas` — used as the reference verifier; launcher output must
  agree with it.
- Downstream: the `launcher-editor` change depends on the `rclf-container` spec
  defined here — the editor writes what this spec describes.
- No breaking change to well-formed data files; malformed files that previously
  "half-loaded" will now be rejected explicitly.
