# Task: Verification

## Depends On
- gui

## Acceptance Criteria
Feature: Editor round-trip and DOS interoperability verification
  As the project maintainer
  I want editor output proven identical on reload and interoperable with RiffDOSParser and the DOS launcher
  So that the editor can be trusted as the writer half of the rclf-container contract

  Scenario: New file round-trips
    Given the user creates entries with icons, flags, and a specific order, then saves to a new file
    When the file is reopened in the editor
    Then all entries, fields, flags, and icons are identical to what was saved

  Scenario: Open malformed file
    Given a file that is not a valid RCLF container (bad root, bad version, or truncated chunks)
    When the user opens it in the editor
    Then the editor shows a descriptive error and does not modify its current document

  Scenario: Save preserves existing file on failure
    Given a save that fails midway (e.g. disk full)
    When the failure occurs
    Then the pre-existing file on disk remains intact and the editor reports the failure

  Scenario: Parser agrees with editor
    Given a file saved by the editor
    When RiffDOSParser is run against it
    Then it reports the same entry count and chunk structure (HDER, APPS list, per-entry APP/INFO/ICON with correct sizes) the editor displayed

  Scenario: DOS interop in DOSBox
    Given a LAUNCHER.DAT produced by the editor, containing entries, icons, and both launch flags
    When it is loaded by the hardened DOS launcher under DOSBox
    Then all entries, icons, and flags behave per the launcher spec (rendering, pause-on-exit, clear-screen)

## Spec
Per `openspec/changes/launcher-editor/tasks.md` group 4 and the migration plan in
`design.md`:

1. **Round-trip**: build a file with icons, flags, and a deliberately reordered
   entry list; save; reopen in the editor; confirm the reopened document is
   identical to what was built (covered automatably by the `RiffWriter`/
   `RiffReader` fpcunit tests in `02-format-units`, plus a full-application
   exercise here through the GUI).
2. **Interop**: run `snips/RiffDOSParser.pas` on editor output; its chunk dump
   must match the entry count and structure the editor displayed.
3. **DOS interop — manual verification required**: load editor output in the
   hardened DOS launcher (from `rclf-format-and-loader-hardening`) under DOSBox;
   confirm entries, icons, and flags behave per the `launcher` spec. This cannot
   be automated from this Darwin-arm64 host — do not mark this task COMPLETED
   until the DOSBox check has actually been run.
4. **Negative tests**: open malformed files (bad root, bad version, truncated) —
   confirm a descriptive error and that the document is left untouched; confirm a
   failed save leaves the on-disk file intact (exercises `RiffReader`'s error
   paths and the atomic-save failure path from `02-format-units`).

## Test Files
- editor/tests/TestRiffReader.pas (negative-file scenarios, extends `02-format-units`)
- editor/tests/TestRiffWriter.pas (round-trip scenarios, extends `02-format-units`)

## Implementation Files
(none new — this task verifies `01-shared-contract`, `02-format-units`, and
`03-gui` together; any fixes required land in those units)
- snips/RiffDOSParser.pas (reference verifier, used but not modified)

## Test Command
cd editor/tests && fpc -Mobjfpc -Sh -Fu/usr/local/lib/fpc/3.2.2/units/aarch64-darwin/fcl-fpcunit -Fu.. TestRunner.lpr && ./TestRunner -a --format=plain

(Covers the automatable round-trip and negative-file scenarios. The RiffDOSParser
interop check and the DOSBox interop scenario above require running
`snips/RiffDOSParser.pas` against editor output and manual DOSBox verification
respectively — neither is captured by this Test Command. Do not mark this task
COMPLETED on a green fpcunit run alone.)
