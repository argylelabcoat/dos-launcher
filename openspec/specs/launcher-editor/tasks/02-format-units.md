# Task: Format Units

## Depends On
- shared-contract

## Acceptance Criteria
Feature: Non-GUI RCLF document, reader, writer, and icon-conversion units
  As the launcher editor
  I want format logic isolated from LCL widgets in LauncherDoc/RiffReader/RiffWriter/IconConvert
  So that RCLF read/write/validation logic is independently testable and never diverges from the DOS reader's contract

  Scenario: Entry limit enforced
    Given a LauncherDoc with 50 entries already added
    When the caller attempts to add a 51st entry
    Then LauncherDoc refuses and reports the launcher's MAX_APPS limit

  Scenario: Reorder entries
    Given a LauncherDoc with several entries
    When an entry is moved up or down
    Then the entry's position changes accordingly, preserving its data and icon reference

  Scenario: Empty exec path blocks save-time validation
    Given a LauncherDoc entry with an empty ExecPath
    When save-time validation runs
    Then validation fails and identifies the offending entry

  Scenario: Valid root header is accepted by RiffReader
    Given a file whose first 12 bytes are RIFF, <size-8 LE>, RCLF
    When RiffReader opens the file
    Then it proceeds to parse chunks within the declared size

  Scenario: RiffReader rejects malformed files
    Given a file with a wrong form type, unsupported HDER version, or truncated chunks
    When RiffReader opens the file
    Then it raises a descriptive error and the caller's existing document is left unmodified

  Scenario: RiffWriter produces a spec-compliant container
    Given a LauncherDoc with N entries, some with icons and some without
    When RiffWriter serializes it
    Then the output has RIFF/RCLF root, one HDER (Version=1, AppCount=N, Flags=0), one LIST/APPS containing one flat APP chunk per entry (not a nested LIST) with INFO and optional ICON chunks, and correct word alignment throughout

  Scenario: Atomic save preserves the existing file on failure
    Given a save that fails partway (e.g. disk full simulated in the temp-file write)
    When the atomic save routine runs
    Then the pre-existing target file on disk remains intact and the failure is reported

  Scenario: Atomic save round-trip self-check
    Given a completed temp-file write
    When the atomic save routine reloads the temp file with RiffReader
    Then entry count and fields match the in-memory LauncherDoc before the temp file is renamed over the target

  Scenario: PNG import converts to spec PCX
    Given a 256-color PNG of arbitrary size imported for an entry
    When IconConvert processes it
    Then the result is a 32x32 16-color image quantized to the standard VGA palette, emitted as 4-plane 1bpp RLE PCX

  Scenario: Icon preview matches launcher output
    Given an icon that has been imported or loaded
    When IconConvert's preview and PCX-decode helper are compared against the DOS PCX16Decoder's output for the same bytes
    Then they produce the same 32x32 16-color pixels

  Scenario: Clear icon
    Given an entry with an icon
    When the icon is cleared
    Then IconConvert/LauncherDoc record no icon for that entry and RiffWriter emits no ICON chunk for it

## Spec
Per `openspec/changes/launcher-editor/tasks.md` group 2 and design decisions
D1, D3, D4, D5, D6 (`openspec/changes/launcher-editor/design.md`):

- **`editor/LauncherDoc.pas`**: document model — ordered entry list (max 50),
  dirty flag, add/edit/remove/reorder, save-time validation (non-empty exec path,
  field limits per `TAppInfo`: Title 40, Desc 70, ExecPath 64, Args 64). No LCL
  dependency (D1) — testable from a console harness.
- **`editor/RiffReader.pas`**: RCLF loader implementing the hardened chunk walk —
  word alignment, unknown-chunk skip, `LIST`/`APPS`/`APP ` nesting, truncation
  guards, descriptive errors (exceptions allowed editor-side, unlike the DOS code's
  `{$I-}` convention — D6). This is an independent implementation of the same
  `rclf-container` spec the DOS loader implements, not shared code with
  `snips/launcher.pas` — deliberate, so disagreement between them flags a spec
  ambiguity.
- **`editor/RiffWriter.pas`**: RCLF serializer building the file in a
  `TMemoryStream` — compute each chunk's size, write header + payload + pad,
  accumulate list sizes, backpatch `LIST`/`RIFF` size fields (D3).
- **Atomic save**: write to a temp file, reload it with `RiffReader`, compare
  entry count and fields against the in-memory document, then rename over the
  target; report failure without touching the existing file if any step fails
  (D5's round-trip self-check).
- **`editor/IconConvert.pas`**: load image (PNG/BMP via `TPicture`; spec-valid
  32x32 4-plane PCX passthrough for already-conforming files), scale to 32x32,
  quantize to the 16 standard VGA colors (nearest-color RGB distance), emit
  planar RLE PCX. Mirrors `snips/RiffBgiIcon.pas`/`snips/PCX16Decoder.pas`
  bitplane logic exactly, inverted, minus the `Graph`/BGI dependency (D4).
  Include a PCX-decode helper so the editor's preview matches what the DOS
  decoder will produce byte-for-byte.
- Uses `snips/RiffLauncher.pas` (the `01-shared-contract` task's output) for all
  record and FourCC definitions.

## Test Files
- editor/tests/TestLauncherDoc.pas
- editor/tests/TestRiffReader.pas
- editor/tests/TestRiffWriter.pas
- editor/tests/TestIconConvert.pas

(Add each new test unit to the `uses` clause of `editor/tests/TestRunner.lpr` — an
fpcunit console runner already scaffolded there with a passing placeholder test
proving the harness compiles and runs on this machine's native desktop FPC. Each
test unit registers its `TTestCase` classes via `RegisterTest` in its
`initialization` section, following `editor/tests/TestPlaceholder.pas`'s pattern.)

## Implementation Files
- editor/LauncherDoc.pas
- editor/RiffReader.pas
- editor/RiffWriter.pas
- editor/IconConvert.pas

## Test Command
cd editor/tests && fpc -Mobjfpc -Sh -Fu/usr/local/lib/fpc/3.2.2/units/aarch64-darwin/fcl-fpcunit -Fu.. TestRunner.lpr && ./TestRunner -a --format=plain
