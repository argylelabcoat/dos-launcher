# Task: Music Test Program

## Depends On
- speaker-music
- rtttl-loader
- mml-loader

## Acceptance Criteria
Feature: MusicTest — standalone DOS verification of the music engine
  As the project maintainer
  I want a standalone DOS program that decodes and plays RTTTL and MML and checks the error paths
  So that the playback engine and loaders are verified on real (emulated) hardware before wiring into the launcher

  Scenario: RTTTL decodes and plays
    Given a hard-coded public-domain RTTTL melody string
    When MusicTest runs test 1
    Then LoadRTTTL returns True, the decoded note list (index, freq, duration) is printed, and the melody plays through the PC speaker

  Scenario: MML decodes and plays
    Given a hard-coded MML melody string
    When MusicTest runs test 2
    Then LoadMML returns True, the decoded note list is printed, and the melody plays

  Scenario: Single-note beep
    Given a call to PlayNote(880, 200)
    When MusicTest runs test 3
    Then a single A5 beep plays for 200 ms and a message is printed

  Scenario: Silence rest
    Given a call to Rest(500)
    When MusicTest runs test 4
    Then a half-second silence occurs and a message is printed

  Scenario: Malformed RTTTL rejected
    Given the string "garbage"
    When MusicTest runs test 5
    Then LoadRTTTL returns False and a message confirms the rejection

  Scenario: Empty MML rejected
    Given an empty string
    When MusicTest runs test 6
    Then LoadMML returns False and a message confirms the rejection

  Scenario: Audible in DOSBox-X
    Given DOSBox-X with PC speaker emulation enabled (pcspeaker=true)
    When MUSICTEST.EXE runs
    Then the melody is audible and the note printout matches the expected frequencies and durations

## Spec
Per the "Verification" section of openspec/specs/pc-speaker-music/spec.md and
change tasks.md group 4:

- Create snips/MusicTest.pas — a standalone program with
  `uses Crt, SpeakerMusic, RtttlLoader, MmlLoader`.
- Test 1: `LoadRTTTL(hardcoded melody)` -> print notes -> `PlayMelody`.
- Test 2: `LoadMML(hardcoded melody)` -> print notes -> `PlayMelody`.
- Test 3: `PlayNote(880, 200)`.
- Test 4: `Rest(500)`.
- Test 5 (negative): `LoadRTTTL('garbage')` must return False.
- Test 6 (negative): `LoadMML('')` must return False.
- Built by scripts/build.sh into dosbox-verify/musicroot/MUSICTEST.EXE; run via
  `scripts/run.sh --music`. The launcher itself (snips/launcher.pas) is not
  modified by this change.

## Test Files
- snips/MusicTest.pas   (the standalone verification program itself)

## Implementation Files
- snips/MusicTest.pas

## Test Command
./scripts/build.sh && ./scripts/run.sh --music

(Requires DOSBox-X with the PC speaker enabled; `scripts/run.sh --music` mounts
dosbox-verify/musicroot/ as C: and runs MUSICTEST.EXE. See dosbox-verify/README.md.)
