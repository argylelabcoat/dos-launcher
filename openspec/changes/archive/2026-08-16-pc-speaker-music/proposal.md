# Proposal: pc-speaker-music

## Why

The launcher currently has no audio. The PC speaker — driven by the 8253 PIT
via the `Crt` unit's `Sound(Hz)` / `NoSound` / `Delay(ms)` API — is the only
sound hardware guaranteed present on the Book-8088 (and every
IBM-compatible). No sound card, no drivers, no DMA, no IRQ. A small playback
engine can produce UI feedback sounds (navigation blips, launch fanfare,
exit jingle) and optionally short melodies for startup/launch events.

Two text-based monophonic music formats have large public-domain libraries
and fit the 8088's 64KB heap and TP short-string constraints:

- **RTTTL** (Ringtone Text Transfer Language) — the Nokia ringtone format.
  Compact (100-300 bytes per melody), trivial grammar, thousands of free
  ringtones. Maps directly to `Sound(freq); Delay(duration); NoSound;`.
- **MML** (Music Macro Language) — the retro game/MSX format. Slightly
  richer (tempo changes, rests, ties, octave commands, optional note-length
  defaults). Used by NES/MSX trackers; larger library of game themes.

Parsing both directly in the playback hot loop is wasteful and ties the
player to a single source format. A shared **intermediate note format**
(a flat array of frequency/duration pairs) decouples the player from the
source format, so new loaders can be added without touching the playback
engine.

## What Changes

- Add a new unit `snips/SpeakerMusic.pas` providing:
  - **`TNote`** record: `Freq: Word; Duration: Word` — one note or rest in the
    intermediate format. `Freq = 0` means rest (silence). `Duration` is in
    milliseconds.
  - **`TMelody`** record: `Notes: array[0..MAX_NOTES-1] of TNote; Count: Word`
    — the intermediate representation. `MAX_NOTES = 256` (fits in ~1KB).
  - **`PlayMelody(var Melody: TMelody)`** — blocking playback: iterates
    notes, calls `Sound(freq)` / `NoSound` / `Delay(duration)`.
  - **`PlayNote(Freq, Duration: Word)`** — single-note helper for UI blips.
  - **`Rest(Duration: Word)`** — silence helper (just `Delay`, no `Sound`).
- Add a new unit `snips/RtttlLoader.pas` providing:
  - **`LoadRTTTL(const S: string; var Melody: TMelody): Boolean`** — parses
    an RTTTL string into the intermediate `TMelody`. Returns `False` on
    malformed input (no exceptions, per project conventions).
  - Note-name → frequency table (C1..B8, equal temperament).
  - Duration and octave resolution per the RTTTL spec defaults and per-note
    overrides.
- Add a new unit `snips/MmlLoader.pas` providing:
  - **`LoadMML(const S: string; var Melody: TMelody): Boolean`** — parses an
    MML string into `TMelody`. Returns `False` on malformed input.
  - Supports the core MML command set: `A-G` (note names), `R` (rest),
    `O` (octave), `L` (default note length), `T` (tempo), `<`/`>` (octave
    shift), `&` (tie), `.` (dotted note).
  - Same frequency table as the RTTTL loader (shared via `SpeakerMusic.pas`
    to avoid duplication).
- No changes to `launcher.pas` in this change — the playback unit and
  loaders are self-contained and tested independently. Wiring into the
  launcher event loop is a separate change.

## Capabilities

### New Capabilities

- `pc-speaker-music`: A TP-compatible unit for monophonic PC-speaker
  playback from a shared intermediate note format, with loader units that
  convert RTTTL and MML source text into that format.

### Modified Capabilities

(None — the launcher is not modified by this change.)

## Impact

- **New files:** `snips/SpeakerMusic.pas`, `snips/RtttlLoader.pas`,
  `snips/MmlLoader.pas`. All TP-dialect Pascal, `{$MODE TP}` compatible,
  16-bit real-mode DOS safe. No heap allocations beyond the `TMelody`
  stack/record (1KB per melody — fits comfortably in the 16KB stack).
- **No changes** to `snips/launcher.pas`, `snips/RiffLauncher.pas`,
  `snips/RiffBgiIcon.pas`, `snips/ExecSwap.pas`, or any existing unit.
- **No changes** to the RCLF container format or any on-disk layout.
- **Downstream:** a future change will wire `PlayMelody` / `PlayNote` calls
  into the launcher's event loop (startup jingle, arrow blips, launch
  fanfare, exit sound). That change depends on the units defined here.
- **Verification:** manual — a standalone test program
  `snips/MusicTest.pas` that loads an RTTTL string, prints the decoded
  `TMelody` note list, plays it via the PC speaker, and repeats for an MML
  string. Run in DOSBox-X (PC speaker emulation confirmed working).

## Non-Goals

- Polyphony / arpeggiation — the intermediate format is strictly
  monophonic. A future change could add a timer-driven arpeggio player, but
  that requires PIT interrupt hooking and is out of scope here.
- Non-blocking playback — `PlayMelody` blocks (uses `Delay`). A
  timer-driven async player is a separate change.
- A new on-disk container or chunk type for embedding music in
  `LAUNCHER.DAT` — melodies are hard-coded string constants for now.
  Embedding music in RCLF is a separate change.
- Sound Blaster / AdLib / MIDI output — PC speaker only.