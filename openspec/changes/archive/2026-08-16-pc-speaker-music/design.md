# Design: pc-speaker-music

## Context

The launcher (`snips/launcher.pas`) already `uses Crt`, which provides
`Sound(Hz: Word)`, `NoSound`, and `Delay(MS: Word)` — the standard
Turbo Pascal PC-speaker API. These drive the 8253 PIT and the speaker gate
on port $61 directly. No sound card is involved. DOSBox-X emulates the PC
speaker, confirmed working in earlier sessions.

Constraints from the project (`AGENTS.md` + `openspec/config.yaml`):
- 16-bit real-mode DOS, Turbo Pascal dialect, `{$MODE TP}`.
- 64KB max heap (`{$M 16384, 0, 65536}`) — but the music units use no heap.
- No exceptions — Boolean returns, `{$I-}`/`IOResult` for I/O.
- No managed strings — short strings (`string[N]`) only.
- Comments explain WHY (hardware/format rationale), not WHAT.

## Goals / Non-Goals

**Goals:**
- A shared intermediate format (`TMelody`) that decouples playback from
  source format.
- A blocking `PlayMelody` that works on any IBM-compatible with a PC
  speaker.
- Loaders for RTTTL and MML that parse in-memory strings into `TMelody`
  without heap allocation.
- Integer-only math (no floating point) for frequency and duration
  calculations.
- Self-contained, testable without the launcher.

**Non-Goals:**
- Polyphony or arpeggiation (future change — needs PIT interrupt hooking).
- Non-blocking / background playback (future change — needs timer ISR).
- Embedding music in `LAUNCHER.DAT` / RCLF (future change).
- Wiring into the launcher event loop (future change — depends on this
  one).
- Sound Blaster / AdLib / MIDI hardware output.

## Decisions

### D1: Intermediate format — flat array of (freq, duration) pairs

The intermediate `TMelody` is a flat array of `TNote = record Freq: Word;
Duration: Word end`. This is the simplest representation that the
`Sound(freq); Delay(duration); NoSound;` playback loop can consume
directly — no per-note parsing during playback, no format-specific state
machine in the hot path.

`MAX_NOTES = 256` gives 256 × 4 = 1024 bytes per melody, which fits
comfortably on the 16KB stack as a local `var` or as a global. No heap
allocation is needed. A 256-note melody at ~500ms per note is ~2 minutes
of music — more than enough for a launcher jingle.

Caution: a `TMelody` declared as a *static global* (rather than a local)
consumes ~1KB of the near data segment (DGROUP), which already overflowed
once in `launcher.pas` — its `AppList` is heap-allocated precisely to
avoid that. The future launcher-wiring change should keep melodies as
locals or heap allocations, not static globals.

`Freq = 0` denotes a rest (silence). This avoids a separate "note type"
enum and keeps `TNote` to 4 bytes.

### D2: Shared frequency table in SpeakerMusic.pas

Both RTTTL and MML need note-name → frequency conversion. Duplicating the
table in each loader would waste ~150 bytes per copy and risk
inconsistency. The table lives in `SpeakerMusic.pas` as a `const array`
in the implementation section, exposed via the `NoteFreq` function. The
loaders `uses SpeakerMusic` and call `NoteFreq`.

The table covers MIDI 24 (C1) through MIDI 119 (B8): 96 entries × 2 bytes
= 192 bytes, indexed by `(Octave - 1) * 12 + semitoneOffset`. Values are
precomputed equal-temperament frequencies rounded to integer Hz.
Integer-only — no `Float`/`Extended` needed at runtime.

### D3: Blocking playback with inter-note gap

`PlayMelody` calls `PlayNote` for each note, which calls `Sound(freq);
Delay(duration); NoSound;`. Between consecutive notes, a 1ms `Delay(1)`
gap is inserted. Without this, two consecutive same-pitch notes merge into
one long tone — the listener cannot hear the note boundary. The 1ms gap
is short enough to be imperceptible as silence but long enough to create
an audible attack transient.

This 1ms gap is the only "trick" in the playback engine — everything else
is a direct `Sound`/`Delay`/`NoSound` sequence. No envelope, no volume
control (the PC speaker has none).

### D4: RTTTL parsing — lenient, section-based

RTTTL has three colon-separated sections: name, defaults, notes. The
loader splits on the first two colons (not every comma — the defaults and
notes sections are themselves comma-separated, but the first two colons
are the section delimiters).

Defaults are `key=value` pairs: `d` (duration), `o` (octave), `b` (BPM).
Each is optional. Unknown keys are ignored. Values out of range clamp.

Individual notes are parsed left-to-right with optional duration digits,
pitch letter, optional sharp/flat, optional octave digits, optional dot.
Unrecognized characters within a note cause that note to be skipped
(lenient — real-world RTTTL files have dialect variations).

### D5: MML parsing — character-by-character state machine

MML has no section delimiters — it's a flat command stream. The loader
scans character by character, maintaining state: current octave, current
length, current tempo, a pending-tie flag, and a pointer to the last
emitted note.

Unsupported commands (`@`, `v`, `$`, `[...]`, `{}`) are skipped: the loader
reads and discards their arguments without error. This is the key
leniency decision — MML files from different tools use different dialects,
and rejecting unknown commands would make the loader useless for real-world
files.

### D6: Tie handling in MML

`&` ties two notes of the same pitch. The loader buffers a pointer to the
last emitted `TNote` in the melody. When `&` is encountered:
- If the next note has the same frequency as the last, extend the last
  note's `Duration` by the next note's duration and do not emit the next
  note.
- If the next note has a different frequency, emit it normally (the tie is
  ignored — this matches real MML player behavior).
- Ties chain: `A4 & A4 & A4` extends the first A4 by the durations of the
  second and third.

### D7: Integer duration math

Both formats express durations as note-length values (1=whole, 2=half,
4=quarter, ...). The millisecond conversion is:

```
ms := (60000 * 4) div (BPM * lengthValue)
if dotted then ms := (ms * 3) div 2
```

All integer, no float — but the numerator `60000 * 4` is 240000, which
overflows a 16-bit `Integer`/`Word`. Turbo Pascal types the literal
`60000` as `Word`, so the multiply wraps mod 65536 and produces garbage
durations (e.g. a quarter note at 63 BPM computes to 256ms instead of
952ms). The intermediate `ms` and the numerator must therefore be
computed as `LongInt`:

```
var ms: LongInt;
ms := (LongInt(60000) * 4) div (BPM * lengthValue);
if dotted then ms := (ms * 3) div 2;
```

The final value always fits in `Word` (max dotted whole note ≈ 18000 ms),
so it is assigned to the 16-bit `Duration` field after the 32-bit math.

### D8: Error reporting — Boolean, no exceptions

Per project conventions, loaders return `Boolean`. `True` = success (or
truncated-at-256-notes success). `False` = structurally invalid input
(no sections, no notes, unparseable). Partial fills on `False` are
unusable and the caller should not play them.

## Risks

- **PC speaker volume in DOSBox-X:** The PC speaker emulation volume may
  be low or disabled by default. The test program should be run with
  `pcspeaker = true` and `speaker = on` in the DOSBox-X config. This is a
  documentation/run-instruction concern, not a code concern.
- **Delay accuracy on real 8088:** `Crt.Delay` is calibrated at unit
  initialization by a busy-loop measurement. On an 8088 it's approximately
  accurate but not cycle-exact; values below one timer tick (~55ms) —
  including the 1ms inter-note gap — are especially approximate. Melodies
  will play at roughly the right tempo but may drift by a few percent.
  Acceptable for jingles.
- **`Sound`/`NoSound` in FPC's i8086-msdos `Crt`:** Turbo Pascal 7 provides
  these in `Crt`; confirm the FPC i8086-msdos target's `Crt` unit exports
  them (and `Delay`) before relying on the `uses Crt` implementation. If
  absent, the PIT programming would move to direct `Port[]` access.
- **RTTTL dialect variation:** Real-world RTTTL files sometimes use
  lowercase, sometimes use `b` for flat, sometimes have extra spaces. The
  lenient parser handles these by skipping unrecognized characters rather
  than failing.