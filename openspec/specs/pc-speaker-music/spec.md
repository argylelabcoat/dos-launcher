# Spec: pc-speaker-music

## Overview

Three new TP-dialect Pascal units provide monophonic PC-speaker music
playback from a shared intermediate note format, with loaders for RTTTL
and MML source text.

All units compile under Free Pascal `i8086-msdos` in `{$MODE TP}` and under
Turbo Pascal 7. No exceptions, no heap allocations, no managed strings.
Short strings only (`string[N]`). All error reporting is via Boolean return
values and `{$I-}`/`IOResult` where file I/O is involved (none here —
loaders parse in-memory strings).

## Unit: SpeakerMusic

### Interface

```pascal
unit SpeakerMusic;

interface

const
  MAX_NOTES = 256;  { 256 notes × 4 bytes = 1KB — fits 16KB stack }

type
  TNote = record
    Freq     : Word;   { Hz; 0 = rest (silence) }
    Duration : Word;   { milliseconds }
  end;

  TMelody = record
    Notes : array[0..MAX_NOTES - 1] of TNote;
    Count : Word;      { number of valid notes (0..MAX_NOTES) }
  end;

{ Play a single tone. Freq=0 produces silence (rest). }
procedure PlayNote(Freq, Duration: Word);

{ Play a silence gap. Equivalent to PlayNote(0, Duration). }
procedure Rest(Duration: Word);

{ Play a full melody. Blocking — uses Delay(ms) per note. }
procedure PlayMelody(var Melody: TMelody);

{ Clear a melody to zero notes (Count := 0, Notes zeroed). }
procedure ClearMelody(var Melody: TMelody);

{ Append a note to a melody. Returns False if the melody is full. }
function AddNote(var Melody: TMelody; Freq, Duration: Word): Boolean;

{ Note-name to frequency lookup. NoteName is 1-2 chars: letter A-G
  optionally followed by '#' or 'b' (sharp/flat). Octave is 1-8.
  Returns 0 if the note name is invalid. }
function NoteFreq(const NoteName: string; Octave: Integer): Word;
```

### Implementation contract

- `PlayNote` wraps `Crt.Sound` / `Crt.NoSound` / `Crt.Delay`. When `Freq =
  0`, it calls `NoSound; Delay(Duration);` (silence). When `Freq > 0`, it
  calls `Sound(Freq); Delay(Duration); NoSound;`. The trailing `NoSound`
  guarantees the speaker is off after each note, preventing stuck tones.
- `PlayMelody` iterates `Melody.Notes[0..Count-1]`, calling `PlayNote` for
  each. Between notes, a short gap (1ms) of silence is inserted to separate
  consecutive same-pitch notes (otherwise they merge into one long tone
  and the listener cannot hear note boundaries).
- `NoteFreq` uses the equal-temperament formula: `freq = 440 * 2^((n -
  A4_MIDI) / 12)` where `n` is the MIDI note number. The computation uses
  integer math only (no floating point) via a precomputed frequency table
  for C1..B8 (the table is 96 entries × 2 bytes = 192 bytes, stored in a
  `const` array). Sharps and flats map to adjacent table entries.
- `AddNote` returns `False` without modifying the melody if `Count >=
  MAX_NOTES`. Otherwise it writes `Notes[Count]` and increments `Count`.
- `ClearMelody` sets `Count := 0` and `FillChar`s the `Notes` array to
  zero. This is defensive — a loader that overwrites `Count` and only the
  first `Count` entries does not need to clear, but the helper exists for
  reuse safety.

### Frequency table

The note-to-frequency table covers MIDI notes 24 (C1, ~32.70 Hz) through
119 (B8, ~7902.13 Hz). Values are rounded to the nearest integer Hz. The
table is indexed by `(Octave - 1) * 12 + semitoneOffset` where
`semitoneOffset` is 0 for C, 1 for C#, ..., 11 for B, and Octave is 1..8.
This range matches the octave ranges declared by both loaders (RTTTL 4-8,
MML 1-8), so every note in those ranges resolves to a valid entry.
`NoteFreq` validates that the computed index is within `[0..95]`;
out-of-range octaves (below 1 or above 8) return 0.

Source: standard equal-temperament frequencies, A4 = 440 Hz. The table is
defined as a `const array[0..95] of Word` in the implementation section.

## Unit: RtttlLoader

### Interface

```pascal
unit RtttlLoader;

interface

uses SpeakerMusic;

{ Parse an RTTTL string into Melody. Returns True on success, False if the
  string is structurally invalid (missing sections, bad note, or zero
  notes). On False, Melody.Count may be partially filled — caller should
  treat the result as unusable. }
function LoadRTTTL(const S: string; var Melody: TMelody): Boolean;
```

### RTTTL format (reference)

An RTTTL string has three colon-separated sections:

```
name:defaults:note1,note2,...,noteN
```

- **name:** free text (ignored by the loader). Must be present but content
  is not validated.
- **defaults:** `d=duration, o=octave, b=beats_per_minute` — each optional,
  comma-separated within the section. `d` is a default duration value (1,
  2, 4, 8, 16, 32), `o` is a default octave (4-8), `b` is BPM (25-900).
  Defaults apply to notes that don't specify their own.
- **notes:** comma-separated; each note is `[duration][pitch][octave][.]` where:
  - `duration` (optional): 1, 2, 4, 8, 16, 32 — overrides the default.
  - `pitch`: `A`-`G`, `P` (pause/rest), optionally followed by `#` (sharp).
    Note: RTTTL uses `#` for sharps; `b` means flat but is rarely used in
    practice — the loader accepts `b` as flat for completeness.
  - `octave` (optional): 4-8 — overrides the default octave.
  - `.` (optional): dotted note — duration × 1.5.

### Duration resolution

RTTTL durations are note-length values (whole=1, half=2, quarter=4,
eighth=8, sixteenth=16, thirty-second=32). The millisecond duration is:

```
ms = (60000 / BPM) * (4 / durationValue) * dottedMultiplier
```

where `BPM` is the beats-per-minute (default 63 if not specified),
`durationValue` is the note-length number, and `dottedMultiplier` is 1.5
if dotted, 1.0 otherwise. A quarter note at 63 BPM = 60000/63 × 4/4 × 1.0
= ~952ms. The loader uses integer arithmetic, but the numerator `60000 * 4`
overflows 16-bit `Integer`/`Word`, so the computation uses `LongInt`:

```
var ms: LongInt;
ms := (LongInt(60000) * 4) div (BPM * durationValue);
if dotted then ms := (ms * 3) div 2;
```

The final value always fits in `Word` (max dotted whole note ≈ 18000 ms).

### Parsing contract

- The loader splits `S` on the first two colons to extract name, defaults,
  and notes sections. If fewer than 2 colons exist, returns `False`.
- Defaults parsing: each default is `key=value`. Unknown keys are ignored.
  Out-of-range values clamp to valid bounds (duration 1-32, octave 4-8,
  BPM 25-900).
- Each note is parsed left-to-right: optional digits (duration), letter
  (pitch), optional `#` or `b`, optional digits (octave), optional `.`.
  Unrecognized characters cause the note to be skipped (not a fatal error)
  — this matches the lenient real-world RTTTL behavior.
- `P` (pause) produces a rest: `Freq = 0`, `Duration` computed normally.
- If `AddNote` returns `False` (melody full), the loader stops and returns
  `True` with the notes parsed so far — a melody truncated at 256 notes is
  valid, not an error.
- On any structural failure (no name section, no notes section, completely
  unparseable defaults), returns `False`.

## Unit: MmlLoader

### Interface

```pascal
unit MmlLoader;

interface

uses SpeakerMusic;

{ Parse an MML string into Melody. Returns True on success, False if the
  string is structurally invalid. Partial fill on False is unusable. }
function LoadMML(const S: string; var Melody: TMelody): Boolean;
```

### MML format (supported subset)

MML (Music Macro Language) is a text format used by NES/MSX trackers and
many Japanese retro tools. The supported command set is the common
"baseline" used across implementations:

| Command | Meaning |
|---------|---------|
| `A`-`G` | Note at current octave. Optional `#`/`+` (sharp) or `-` (flat) suffix. Optional duration digits after. Optional `.` (dotted). |
| `R`     | Rest. Optional duration digits and `.`. |
| `O`n    | Set octave to n (1-8). Default is 4. |
| `L`n    | Set default note length to n (1,2,4,8,16,32,64). Default is 4. |
| `T`n    | Set tempo in BPM (20-500). Default is 120. |
| `<`     | Octave down (decrement octave, min 1). |
| `>`     | Octave up (increment octave, max 8). |
| `&`     | Tie: merges the previous note's duration with the next note's duration. The next note must be the same pitch; if different, the tie is ignored and both notes play normally. |
| `.`     | Dotted note (applies to the preceding note or rest): duration × 1.5. |
| `n` (digits) | Note length override (after a note name or R): 1,2,4,8,16,32,64. |

Unsupported commands (`@` instrument, `v` volume, `$` macro, `[...]` loop,
`{}` grace notes) are skipped: the loader reads and discards their
arguments without error. This keeps the loader compatible with MML files
that use features the PC speaker cannot use.

### Duration resolution

Same formula as RTTTL, computed in `LongInt` to avoid 16-bit overflow:

```
var ms: LongInt;
ms := (LongInt(60000) * 4) div (Tempo * lengthValue);
if dotted then ms := (ms * 3) div 2;
```

Default length is `L` (default 4). A note with explicit duration digits
uses those; a note without uses the current `L` value. Dotted multiplies
by 1.5.

### Octave handling

MML octave numbers map to the same frequency table as RTTTL via the shared
`NoteFreq` function. `O4` = octave 4 (C4..B4). `<` and `>` shift the current
octave. The octave clamps at 1 and 8.

### Tie handling

`&` between two notes of the same pitch merges them: the first note's
duration is extended by the second's duration, and the second note is not
emitted as a separate `TNote`. If the pitches differ, both notes play
independently (the tie is ignored) and the pending-tie flag is cleared.
Ties can chain (`A4 & A4 & A4` = one note of 3× duration). The loader
implements this by buffering the last emitted note and extending its
`Duration` when a tie is encountered before the next note.

### Parsing contract

- The loader scans `S` character by character. State: current octave
  (default 4), current length (default 4), current tempo (default 120),
  a "pending tie" flag, and a pointer to the last emitted note for tie
  extension.
- Unrecognized characters are skipped (lenient — MML files often have
  whitespace, comments, or dialect-specific markers).
- If `AddNote` returns `False` (melody full), the loader stops and returns
  `True` with notes so far.
- Returns `False` only on truly empty input or a completely unparseable
  string (no valid notes or commands at all).

## Shared constraints

- All three units are `{$MODE TP}` compatible and compile under FPC
  `i8086-msdos` and Turbo Pascal 7.
- No heap allocations (`New`, `GetMem`) anywhere — `TMelody` is a
  stack/record type. The frequency table is a `const` array in the
  implementation section (no heap).
- No floating-point math — all frequency and duration calculations use
  integer arithmetic (multiply-then-divide to preserve precision), with
  `LongInt` intermediates for the duration formula (the `60000 * 4`
  numerator overflows a 16-bit `Integer`/`Word`).
- No `uses` beyond `Crt` (for `SpeakerMusic`) and `SpeakerMusic` (for the
  loaders). No `Dos`, no `Graph`, no `Strings`.
- Maximum melody length is 256 notes. A melody that exceeds this is
  truncated, not errored — the loader returns `True` with 256 notes.

## Verification

A standalone test program `snips/MusicTest.pas` exercises both loaders:

1. Hard-coded RTTTL string (a public-domain melody, e.g. "The Entertainer"
   or a simple scale) → `LoadRTTTL` → print each note (index, freq, duration
   in ms) → `PlayMelody`.
2. Hard-coded MML string (same melody or a short scale) → `LoadMML` →
   print notes → `PlayMelody`.
3. `PlayNote(880, 200)` — single A5 beep.
4. `Rest(500)` — half-second silence.
5. Malformed RTTTL (missing colons, bad note) → `LoadRTTTL` returns `False`.
6. Malformed MML (empty string) → `LoadMML` returns `False`.

Run in DOSBox-X with PC speaker emulation enabled. Verify the melody is
audible and the note list printout matches expected frequencies and
durations.

## File layout

```
snips/
  SpeakerMusic.pas   — playback + intermediate format + frequency table
  RtttlLoader.pas    — RTTTL → TMelody loader
  MmlLoader.pas      — MML → TMelody loader
  MusicTest.pas      — standalone verification program
```