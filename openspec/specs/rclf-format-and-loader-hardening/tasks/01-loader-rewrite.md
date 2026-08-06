# Task: Loader Rewrite

## Acceptance Criteria
Feature: RCLF sequential chunk-walk loader
  As the DOS launcher
  I want to parse LAUNCHER.DAT as a structured RCLF container instead of a flat scan
  So that real-world files with padding, unknown chunks, or missing icons load correctly instead of desyncing

  Scenario: Valid root header is accepted
    Given a LAUNCHER.DAT whose first 12 bytes are RIFF, <size-8 LE>, RCLF
    When the loader opens the file
    Then the loader proceeds to parse chunks within the declared size

  Scenario: Wrong form type is rejected
    Given a RIFF file whose form type is not RCLF
    When the loader opens the file
    Then the loader rejects the file and loads no applications

  Scenario: Non-RIFF file is rejected
    Given a file that does not begin with RIFF
    When the loader opens the file
    Then the loader rejects the file and loads no applications

  Scenario: Version 1 header is accepted
    Given a HDER chunk declaring Version = 1 and AppCount = N
    When the loader reads the HDER chunk
    Then the loader accepts the file and expects N application entries

  Scenario: Unsupported version is rejected
    Given a HDER chunk declaring a Version other than 1
    When the loader reads the HDER chunk
    Then the loader rejects the file and loads no applications

  Scenario: Entry with info and icon
    Given an APP entry containing an INFO chunk followed by an ICON chunk
    When the loader walks that APP list
    Then it creates one application entry using that metadata and icon

  Scenario: Entry without icon
    Given an APP entry containing an INFO chunk and no ICON chunk
    When the loader walks that APP list
    Then it creates one application entry with no icon

  Scenario: Entry without info is ignored
    Given an APP entry containing no INFO chunk
    When the loader walks that APP list
    Then the loader skips the entry and creates no application for it

  Scenario: Truncated INFO record is rejected
    Given an INFO chunk declaring a size smaller than 244 bytes, or the file ending mid-record
    When the loader attempts to read that INFO chunk
    Then the loader discards that APP entry and stops loading further entries

  Scenario: Odd-sized chunk is padded
    Given a chunk that declares an odd payload size
    When the loader finishes reading its payload
    Then it skips exactly one pad byte before reading the next chunk header

  Scenario: Even-sized chunk has no padding
    Given a chunk that declares an even payload size
    When the loader finishes reading its payload
    Then the next chunk begins immediately with no pad byte skipped

  Scenario: Unknown chunk between known chunks
    Given an unrecognized chunk of declared size S appears between the HDER chunk and the APPS list
    When the loader encounters it
    Then it seeks forward S bytes plus any alignment pad and parses the following chunks normally

  Scenario: Truncated trailing chunk
    Given the file ends partway through a chunk header after the last complete APP entry
    When the loader reaches that point
    Then it keeps the entries already loaded and finishes loading without error

## Spec
Rewrite `LoadLauncherData` in `snips/launcher.pas` as a sequential state-machine chunk
walk per design decisions D1-D4 (`openspec/changes/rclf-format-and-loader-hardening/design.md`):

- **D1**: Read the 12-byte RIFF root header, validate `RIFF` ID and `RCLF` form type,
  then loop reading chunk headers until the declared form size is exhausted or EOF.
  Nested `LIST` chunks (payload = 4-byte list type + child chunks) are walked by
  recursion bounded by their declared size — same shape as `RiffDOSParser.pas`.
  Require `HDER` (`Version = 1`) before any `LIST`.
- **D2**: An `ICON` chunk attaches to the most recent `INFO` in the same `APP ` entry.
  An entry commits (`Inc(TotalApps)`) when its `APP ` list ends, not when `ICON` is
  sighted — fixes the current off-by-one desync where an entry without an icon shifts
  every subsequent icon onto the wrong app. A second `INFO` in the same entry is
  malformed; discard the entry.
- **D3**: After every chunk payload, if the declared size is odd, seek forward 1 byte.
  Unknown FourCC seeks forward `Size + (Size and 1)`. Use `Seek`/`FilePos` arithmetic
  rather than dummy reads. Clamp all seeks to the containing chunk's end boundary and
  to file size; a lying declared size terminates the loop rather than reading out of
  bounds.
- **D4**: Every `BlockRead` result is checked via `{$I-}`/`IOResult` and byte counts,
  no exceptions. A truncated chunk header terminates the load loop, keeping entries
  already committed; a truncated `INFO` discards the in-progress entry.
- Add `Flags: Word` to `TAppEntry` and copy it from `TAppInfo` during load (feeds
  the `02-launch-flags` task).
- Enforce `MAX_APPS = 50`: stop committing entries at 50 and do no further parsing
  work once the cap is hit.
- Record layouts in `snips/RiffLauncher.pas` are frozen — do not change them.

Constraints: 16-bit real-mode DOS, Turbo Pascal dialect, `{$M 16384, 0, 65536}`, no
exceptions.

## Test Files
(none — DOS-target unit, no automated unit test harness; verified by compile check
and the `03-verification` task's DOSBox/fixture-file testing)

## Implementation Files
- snips/launcher.pas

## Test Command
An FPC i8086-msdos cross-compiler now exists at
`dosbox-verify/fpc-i8086-install/` (built from `~/fpcupdeluxe/fpcsrc`). Real
compile command — see `03-verification`'s Test Command for the full invocation
and required `AppList` heap-allocation note (a static `AppList` overflows the
64KB DGROUP segment once linked against the Graph unit). This produces a real,
runnable DOS `.exe`, confirmed under DOSBox-X to initialize real 640x480 VGA
mode and run without crashing. Interactive/visual scenarios (paging, nav,
swap round-trip, flags) still need manual DOSBox-X verification — see
`03-verification`.
