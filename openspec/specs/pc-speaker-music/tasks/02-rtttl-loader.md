# Task: RTTTL Loader

## Depends On
- speaker-music

## Acceptance Criteria
Feature: RtttlLoader unit — RTTTL text to TMelody
  As the launcher
  I want to parse an RTTTL string into the shared TMelody format
  So that Nokia ringtone melodies can be played through the PC speaker without a format-specific player

  Scenario: Well-formed RTTTL parses
    Given a string like "OdeToJoy:d=4,o=5,b=140:e5,e5,f5,g5,g5,f5,e5,d5"
    When LoadRTTTL is called
    Then it returns True and fills Melody with one note per comma-separated note token in the notes section

  Scenario: Sections are colon-delimited
    Given an RTTTL string "Name:Defaults:Notes"
    When LoadRTTTL splits it
    Then it splits on the first two colons, so name, defaults, and notes land in the correct sections even though defaults and notes are internally comma-separated

  Scenario: Fewer than two colons is rejected
    Given a string with fewer than two colons
    When LoadRTTTL is called
    Then it returns False

  Scenario: Defaults resolve and clamp
    Given a defaults section with d, o, and b values
    When LoadRTTTL parses them
    Then d (1-32), o (4-8), and b (25-900) apply as defaults, out-of-range values clamp to bounds, and unknown keys are ignored

  Scenario: Per-note overrides win
    Given a note with its own duration and octave digits
    When LoadRTTTL parses it
    Then the per-note values override the defaults for that note only

  Scenario: Rest note P produces silence
    Given a note token "P" (pause)
    When LoadRTTTL parses it
    Then it adds a note with Freq = 0 and the computed duration

  Scenario: Dotted note multiplies by 1.5
    Given a note token ending in '.'
    When LoadRTTTL resolves its duration
    Then the duration is multiplied by 1.5 using integer math

  Scenario: Duration math is 32-bit safe
    Given the millisecond formula (60000 * 4) div (BPM * durationValue)
    When LoadRTTTL computes a quarter note at 63 BPM
    Then the result is about 952 ms, computed via LongInt so 60000 * 4 does not overflow 16-bit Integer/Word

  Scenario: Malformed notes are skipped, not fatal
    Given a notes section with an unrecognized token mixed among valid notes
    When LoadRTTTL parses it
    Then the bad token is skipped and the valid notes still parse, returning True

  Scenario: Full melody truncates at MAX_NOTES
    Given input producing more than 256 notes
    When LoadRTTTL parses it
    Then it stops at 256 notes and returns True (truncation is valid, not an error)

  Scenario: Empty notes section is rejected
    Given a structurally valid string whose notes section yields zero notes
    When LoadRTTTL is called
    Then it returns False

## Spec
Per the "Unit: RtttlLoader" section of openspec/specs/pc-speaker-music/spec.md
and design decisions D4, D7, D8 of openspec/changes/pc-speaker-music/design.md:

- `LoadRTTTL(const S: string; var Melody: TMelody): Boolean`. Returns True on
  success or truncation-at-256-notes; False on structural failure (missing
  sections or zero notes).
- RTTTL has three colon-separated sections: `name:defaults:notes`. The loader
  splits on the first two colons — the defaults and notes sections are
  themselves comma-separated, so colons (not commas) are the section delimiters.
- Note token grammar: `[duration][pitch][accidental][octave][.]` with pitch A-G
  or P (pause), accidental `#` (sharp) or `b` (flat), octave 4-8, and optional
  dotted `.`.
- Duration resolution uses LongInt: `ms := (LongInt(60000) * 4) div (BPM *
  durationValue); if dotted then ms := (ms * 3) div 2`. The final value fits in
  Word. (60000 * 4 = 240000 overflows 16-bit Integer/Word — hence LongInt.)
- Lenient parsing: skip unrecognized tokens without error; `AddNote` returning
  False (melody full) stops the loop and returns True.
- Add the top-of-unit comment block summarizing the RTTTL reference and the
  lenient parsing policy (change tasks.md 5.2).

## Test Files
(none — DOS-target unit with no automated unit-test harness; verified by
cross-compile and the 04-music-test task's MUSICTEST.EXE build/run)

## Implementation Files
- snips/RtttlLoader.pas

## Test Command
./scripts/build.sh

(Builds dosbox-verify/musicroot/MUSICTEST.EXE via the i8086-msdos cross-compiler
with -Mtp; this unit compiles as a dependency of that program.)
