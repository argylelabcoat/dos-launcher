# Spec: editor

Delta for the `editor` capability (new).

## ADDED Requirements

### Requirement: Data file lifecycle

The editor SHALL create new launcher data files and open existing ones, parsing them
per the `rclf-container` spec. Saving SHALL produce a spec-compliant RCLF file:
`RIFF`/`RCLF` root with correct size, one `HDER` chunk (`Version = 1`, `AppCount`
matching the entry list, `Flags = 0`), and one `LIST`/`APPS` containing one flat
`APP ` chunk per entry (not a nested `LIST` — see the `rclf-container` spec's
APPS/APP requirement) with its `INFO` chunk and optional `ICON` chunk, with
2-byte word alignment throughout. Save SHALL be atomic (write to temporary file,
then rename) so a failed save never destroys the existing file.

#### Scenario: New file round-trips

- **WHEN** the user creates entries, saves to a new file, and reopens it
- **THEN** all entries, fields, flags, and icons are identical to what was saved

#### Scenario: Open malformed file

- **WHEN** the user opens a file that is not a valid RCLF container (bad root, bad
  version, truncated chunks)
- **THEN** the editor shows a descriptive error and does not modify its current
  document

#### Scenario: Save preserves existing file on failure

- **WHEN** a save fails midway (e.g. disk full)
- **THEN** the pre-existing file on disk remains intact and the editor reports the
  failure

### Requirement: Entry list management

The editor SHALL maintain an ordered list of up to 50 applications with operations
to add, edit, remove, and reorder (move up/down) entries. The list view SHALL show
each entry's title and icon. The editor MUST refuse to add a 51st entry, explaining
the launcher's `MAX_APPS` limit.

#### Scenario: Reorder entries

- **WHEN** the user moves an entry up or down
- **THEN** the entry's position in the list and in the saved file changes
  accordingly, preserving its data and icon

#### Scenario: Entry limit enforced

- **WHEN** the list already contains 50 entries and the user attempts to add another
- **THEN** the editor refuses and explains the 50-entry launcher limit

### Requirement: Entry field editing and validation

Each entry SHALL expose editable fields matching `TAppInfo`: Title (max 40 chars),
Description (max 70 chars), Exec path (max 64 chars, required), Args (max 64 chars),
and flags for pause-on-exit (bit 0) and clear-screen (bit 1). The editor SHALL
enforce length limits at input time (not merely at save) and SHALL prevent saving a
file containing an entry with an empty exec path.

#### Scenario: Overlong title is blocked

- **WHEN** the user types a 41st character into the Title field
- **THEN** the character is rejected and the field keeps its 40 characters

#### Scenario: Empty exec path blocks save

- **WHEN** the user saves while any entry has an empty exec path
- **THEN** the save is blocked and the offending entry is highlighted with an
  explanation

### Requirement: Icon import and conversion

The editor SHALL import common image formats (at minimum PNG, BMP, and PCX) as an
entry icon. Imported images SHALL be scaled to 32x32 and quantized to the standard
16-color VGA palette, then converted to the 4-plane 1-bit-per-pixel RLE PCX form
required by the `rclf-container` spec. The editor SHALL show a preview of the
converted 32x32 16-color icon (what the launcher will render) and SHALL allow
clearing an entry's icon.

#### Scenario: PNG import converts to spec PCX

- **WHEN** the user imports a 256-color PNG of arbitrary size for an entry
- **THEN** the entry icon becomes a 32x32 16-color image, the preview reflects it,
  and the saved `ICON` chunk decodes correctly in the launcher

#### Scenario: Icon preview matches launcher output

- **WHEN** an icon has been imported or loaded
- **THEN** the preview shows the same 32x32 16-color pixels the launcher's PCX
  decoder produces from the saved file

#### Scenario: Clear icon

- **WHEN** the user clears an entry's icon and saves
- **THEN** the saved `APP ` entry contains no `ICON` chunk

### Requirement: Shared format contract with DOS code

The editor SHALL use `snips/RiffLauncher.pas` (unmodified in layout) for all RCLF
record and FourCC definitions, so on-disk structures are defined exactly once. Any
compilation guard needed for desktop FPC (e.g. a mode directive) MUST be
`{$IFDEF FPC}`-conditional and MUST NOT change record layouts or break compilation
with the DOS toolchain.

#### Scenario: Byte-level agreement

- **WHEN** the editor writes an `INFO` record for known field values
- **THEN** the bytes on disk match the packed `TAppInfo` layout the DOS launcher
  reads (244-byte payload, TP short strings, little-endian flags)

### Requirement: Interoperability verification path

A saved editor file SHALL parse identically in `RiffDOSParser` (chunk dump shows
`HDER`, `APPS` list, and per-entry `APP `/`INFO`/`ICON` with correct sizes) and load
in the hardened DOS launcher with all entries, icons, and flags intact.

#### Scenario: Parser agrees with editor

- **WHEN** `RiffDOSParser` is run against an editor-saved file
- **THEN** it reports the same entry count and chunk structure the editor displayed
