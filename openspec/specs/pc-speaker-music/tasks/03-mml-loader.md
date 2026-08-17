# Task: MML Loader

## Depends On
- speaker-music

## Acceptance Criteria
Feature: MmlLoader unit — MML text to TMelody
  As the launcher
  I want to parse an MML string into the shared TMelody format
  So that game-theme melodies can be played through the PC speaker

  Scenario: Notes and rests parse
    Given an MML string with note letters A-G and R rests
    When LoadMML is called
    Then it emits one TNote per note/rest with the correct frequency and duration

  Scenario: Octave, length, and tempo commands apply
    Given an MML string using O (octave), L (length), and T (tempo) commands
    When LoadMML scans it
    Then those set the current octave (1-8), default note length, and tempo (20-500) that subsequent notes use

  Scenario: Octave shift clamps
    Given '<' and '>' octave-shift commands
    When the octave would move below 1 or above 8
    Then it clamps at 1 and 8

  Scenario: Tie merges same-pitch notes
    Given an MML string "A4 & A4"
    When LoadMML parses it
    Then it extends the first note's duration by the second's and emits only one note

  Scenario: Tie to a different pitch is ignored and the flag cleared
    Given an MML string "A4 & B4"
    When LoadMML parses it
    Then both notes are emitted normally and the pending-tie flag is cleared so a later same-pitch note is not wrongly merged

  Scenario: Dotted note multiplies by 1.5
    Given a note token with a trailing '.'
    When LoadMML resolves its duration
    Then the duration is multiplied by 1.5 using integer math

  Scenario: Unsupported commands are skipped
    Given MML containing '@', 'v', '$', '[...]', or '{}' constructs
    When LoadMML scans it
    Then those commands and their arguments are discarded without error

  Scenario: Duration math is 32-bit safe
    Given the formula (60000 * 4) div (Tempo * lengthValue)
    When LoadMML computes a quarter note at 120 BPM
    Then the result is about 500 ms, computed via LongInt so 60000 * 4 does not overflow 16-bit Integer/Word

  Scenario: Full melody truncates at MAX_NOTES
    Given input producing more than 256 notes
    When LoadMML parses it
    Then it stops at 256 notes and returns True

  Scenario: Empty input is rejected
    Given an empty or whitespace-only string
    When LoadMML is called
    Then it returns False

## Spec
Per the "Unit: MmlLoader" section of openspec/specs/pc-speaker-music/spec.md
and design decisions D5, D6, D7, D8 of openspec/changes/pc-speaker-music/design.md:

- `LoadMML(const S: string; var Melody: TMelody): Boolean`. Character-by-character
  state machine holding current octave (default 4), length (default 4), tempo
  (default 120 BPM), a pending-tie flag, and the last emitted note index.
- Commands: A-G (notes, optional `#`/`+` or `-` accidental, duration digits,
  dotted), R (rest), `O`n, `L`n, `T`n, `<` / `>` octave shift, `&` tie, `.`
  dotted.
- Tie handling: on `&` set the pending flag; when the next note arrives, if its
  frequency matches the last emitted note, extend that note's duration and do not
  emit; if it differs, emit normally AND clear the pending flag.
- Duration: `ms := (LongInt(60000) * 4) div (Tempo * lengthValue); if dotted
  then ms := (ms * 3) div 2`.
- Unsupported commands (@, v, $, [...], {}) read and discard their arguments.
  Unrecognized characters/whitespace are skipped. Returns False only on empty or
  fully unparseable input.
- Add the top-of-unit comment block summarizing the supported MML command set and
  the unsupported-command skip policy (change tasks.md 5.3).

## Test Files
(none — DOS-target unit with no automated unit-test harness; verified by
cross-compile and the 04-music-test task's MUSICTEST.EXE build/run)

## Implementation Files
- snips/MmlLoader.pas

## Test Command
./scripts/build.sh

(Builds dosbox-verify/musicroot/MUSICTEST.EXE via the i8086-msdos cross-compiler
with -Mtp; this unit compiles as a dependency of that program.)
