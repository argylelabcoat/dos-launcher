# Task: Speaker Music Unit

## Acceptance Criteria
Feature: SpeakerMusic unit — intermediate format, frequency table, and playback
  As the DOS launcher and its music loaders
  I want a shared TMelody intermediate format, a precomputed note-frequency table, and a Crt-backed playback engine
  So that playback is decoupled from source formats and every loader resolves note names through one source of truth

  Scenario: Frequency table covers the declared octave range
    Given the table is a const array of Word in the implementation section
    When NoteFreq is called for any note from C1 through B8
    Then it returns the equal-temperament frequency (A4 = 440 Hz) indexed by (Octave - 1) * 12 + semitoneOffset, and the table has exactly 96 entries

  Scenario: Out-of-range octave returns silence sentinel
    Given an octave below 1 or above 8
    When NoteFreq is called
    Then it returns 0 without indexing out of bounds

  Scenario: Sharp and flat map to adjacent entries
    Given a note name of one letter optionally followed by '#' or 'b'
    When NoteFreq is called
    Then the sharp/flat resolves to the adjacent semitone entry of the same octave

  Scenario: PlayNote produces a tone and silences after
    Given a frequency greater than zero and a duration
    When PlayNote is called
    Then it calls Sound(Freq), Delay(Duration), then NoSound so the speaker is never left stuck on

  Scenario: PlayNote with zero frequency is a rest
    Given a frequency of zero
    When PlayNote is called
    Then it produces silence (NoSound + Delay) with no tone

  Scenario: PlayMelody inserts an inter-note gap
    Given a melody with two consecutive same-pitch notes
    When PlayMelody plays it
    Then a short (1ms) silence gap separates the notes so they do not merge into one long tone

  Scenario: AddNote refuses a full melody
    Given a melody whose Count already equals MAX_NOTES
    When AddNote is called
    Then it returns False and leaves the melody unmodified

  Scenario: ClearMelody zeroes the melody
    Given any melody
    When ClearMelody is called
    Then Count becomes 0 and the Notes array is zeroed

  Scenario: Melody size is bounded and heap-free
    Given MAX_NOTES = 256
    When a TMelody is declared
    Then it occupies about 1KB (256 * 4 + 2 bytes) with no heap allocation

## Spec
Per the "Unit: SpeakerMusic" section of openspec/specs/pc-speaker-music/spec.md
and design decisions D1, D2, D3 of openspec/changes/pc-speaker-music/design.md:

- Define `TNote = record Freq: Word; Duration: Word end` with Freq = 0 meaning
  rest, and `TMelody = record Notes: array[0..MAX_NOTES - 1] of TNote; Count:
  Word end` with `MAX_NOTES = 256`.
- Expose PlayNote, Rest, PlayMelody, ClearMelody, AddNote, and NoteFreq in the
  interface. `uses Crt` appears in the implementation only (Sound/NoSound/Delay).
- Frequency table: MIDI 24 (C1) through 119 (B8) — 96 entries — indexed by
  `(Octave - 1) * 12 + semitoneOffset` (C=0 .. B=11). This range matches both
  loaders' octave ranges (RTTTL 4-8, MML 1-8) so no declared octave falls off
  the table. Values are precomputed equal-temperament frequencies rounded to
  integer Hz; no floating-point math at runtime.
- PlayNote: Freq = 0 -> `NoSound; Delay(Duration)`. Freq > 0 ->
  `Sound(Freq); Delay(Duration); NoSound`. PlayMelody calls PlayNote per note
  with a 1ms `Delay(1)` gap between notes.
- AddNote returns False without modifying the melody when `Count >= MAX_NOTES`.
- ClearMelody uses `FillChar(Melody, SizeOf(Melody), 0)` (zeroes Count and Notes
  together).
- Add the top-of-unit comment block explaining the 8253 PIT / speaker-gate
  mechanism (via Crt) and why the inter-note gap exists (change tasks.md 5.1).

## Test Files
(none — DOS-target unit with no automated unit-test harness; verified by
cross-compile and the 04-music-test task's MUSICTEST.EXE build/run)

## Implementation Files
- snips/SpeakerMusic.pas

## Test Command
./scripts/build.sh

(Builds dosbox-verify/musicroot/MUSICTEST.EXE via the i8086-msdos cross-compiler
with -Mtp; this unit compiles as a dependency of that program. See
dosbox-verify/README.md for the cross-compiler location.)
