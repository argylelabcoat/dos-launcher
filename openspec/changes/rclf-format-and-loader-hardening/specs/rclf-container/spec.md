# Spec: rclf-container

Delta for the `rclf-container` capability (new).

## ADDED Requirements

### Requirement: RIFF root structure

An RCLF data file SHALL be a standard RIFF container whose 12-byte root header consists
of the FourCC `RIFF`, a little-endian 32-bit file size equal to the total file size
minus 8, and the form type FourCC `RCLF`. Readers MUST reject files whose root ID is
not `RIFF` or whose form type is not `RCLF`.

#### Scenario: Valid root header is accepted

- **WHEN** a reader opens a file whose first 12 bytes are `RIFF`, `<size-8 LE>`,
  `RCLF`
- **THEN** the reader proceeds to parse chunks within the declared size

#### Scenario: Wrong form type is rejected

- **WHEN** a reader opens a RIFF file whose form type is not `RCLF`
- **THEN** the reader rejects the file and loads no applications

#### Scenario: Non-RIFF file is rejected

- **WHEN** a reader opens a file that does not begin with `RIFF`
- **THEN** the reader rejects the file and loads no applications

### Requirement: Word alignment of chunks

Every chunk SHALL begin at an even (2-byte aligned) file offset relative to the start
of the RIFF form data. A chunk whose declared payload size is odd SHALL be followed by
exactly one padding byte, which readers MUST skip and writers MUST emit. The padding
byte is not counted in the chunk's declared size.

#### Scenario: Odd-sized chunk is padded

- **WHEN** a chunk declares an odd payload size
- **THEN** the following chunk begins one byte after the end of the payload, and the
  reader skips exactly that one pad byte

#### Scenario: Even-sized chunk has no padding

- **WHEN** a chunk declares an even payload size
- **THEN** the following chunk begins immediately after the payload with no pad byte

### Requirement: HDER launcher header chunk

The file SHALL contain exactly one `HDER` chunk, appearing before any `LIST` chunk.
Its payload SHALL be a packed 6-byte record: `Version` (Word), `AppCount` (Word),
`Flags` (Word), all little-endian. `Version` SHALL be 1 for this revision of the
format. `AppCount` SHALL equal the number of `APP ` entries in the file. `Flags` is
reserved and SHALL be written as 0; readers MUST ignore it.

#### Scenario: Version 1 header is accepted

- **WHEN** the `HDER` chunk declares `Version = 1` and `AppCount = N`
- **THEN** the reader accepts the file and expects N application entries

#### Scenario: Unsupported version is rejected

- **WHEN** the `HDER` chunk declares a `Version` other than 1
- **THEN** the reader rejects the file and loads no applications

### Requirement: APPS list and APP entries

All application entries SHALL be contained in a single `LIST` chunk whose list type is
`APPS`. Inside the `APPS` list, each application SHALL be one plain chunk with FourCC
`APP ` (with a trailing space) — not a nested `LIST` — whose payload is exactly one
`INFO` chunk followed by at most one `ICON` chunk. The `INFO` chunk SHALL precede the
`ICON` chunk within its `APP ` entry's payload. An `APP ` entry without an `INFO`
chunk SHALL be ignored by readers.

`APP ` is a flat, non-`LIST` chunk by design: an `APP ` entry always contains exactly
`INFO` + optional `ICON` with no other chunk types possible inside it, so a `LIST`
wrapper (whose only purpose is signaling "generic tools should recurse into
heterogeneous named sub-chunks") adds 4 bytes and one parse level per entry with no
benefit — no generic RIFF tooling consumes this format, and readers must already
special-case the `APP ` FourCC to know its payload holds sub-chunks at all, wrapper or
not. Tools that walk chunks generically (e.g. `RiffDOSParser`) MUST special-case `APP
` explicitly to descend into it; a `LIST`-only generic walker will otherwise treat it
as opaque data, which is expected and does not indicate a malformed file.

#### Scenario: Entry with info and icon

- **WHEN** an `APP ` entry contains an `INFO` chunk followed by an `ICON` chunk
- **THEN** the reader creates one application entry using that metadata and icon

#### Scenario: Entry without icon

- **WHEN** an `APP ` entry contains an `INFO` chunk and no `ICON` chunk
- **THEN** the reader creates one application entry with no icon

#### Scenario: Entry without info is ignored

- **WHEN** an `APP ` entry contains no `INFO` chunk
- **THEN** the reader skips the entry and creates no application for it

### Requirement: INFO application metadata record

The `INFO` chunk payload SHALL be a packed record `TAppInfo` with fields in this
order: `Title` (`string[40]`), `Desc` (`string[70]`), `ExecPath` (`string[64]`),
`Args` (`string[64]`), `Flags` (Word, little-endian). Strings are Turbo Pascal short
strings: one length byte followed by up to N content bytes, padded with arbitrary
bytes up to the fixed field size; the declared record size is always
41 + 71 + 65 + 65 + 2 = 244 bytes. `Flags` bit 0 SHALL mean "pause on exit" and bit 1
SHALL mean "clear screen before launch"; all other bits are reserved and SHALL be
written as 0.

#### Scenario: Full-size record is read

- **WHEN** an `INFO` chunk declares a size of 244 bytes
- **THEN** the reader reads the five fields at their packed offsets and applies the
  string length bytes, ignoring padding content

#### Scenario: Truncated record is rejected

- **WHEN** an `INFO` chunk declares a size smaller than 244 bytes or the file ends
  mid-record
- **THEN** the reader discards that `APP ` entry and stops loading further entries

### Requirement: ICON embedded PCX image

The `ICON` chunk payload SHALL be a standard 16-color planar PCX image with these
constraints: manufacturer byte `$0A`, RLE encoding (encoding byte 1), 1 bit per pixel
per plane, exactly 4 bitplanes, and dimensions exactly 32x32 pixels
(`XMax - XMin + 1 = 32`, `YMax - YMin + 1 = 32`). BytesPerLine SHALL be at least 4.
The PCX palette is advisory; readers MAY ignore it.

#### Scenario: Valid 32x32 4-plane PCX is decoded

- **WHEN** an `ICON` chunk contains a PCX meeting all constraints
- **THEN** the reader decodes the RLE data into a 32x32 16-color image and associates
  it with the current application entry

#### Scenario: Non-conforming PCX yields no icon

- **WHEN** an `ICON` chunk's PCX has wrong dimensions, wrong plane count, or a bad
  manufacturer byte
- **THEN** the reader treats the entry as having no icon and continues loading

### Requirement: Unknown chunks are skipped

Readers MUST skip any chunk whose FourCC they do not recognize by seeking forward by
the chunk's declared payload size plus the applicable alignment pad, without
interpreting the payload. Unknown chunks MUST NOT affect the parsing of subsequent
known chunks.

#### Scenario: Unknown chunk between known chunks

- **WHEN** an unrecognized chunk appears between the `HDER` chunk and the `APPS` list
- **THEN** the reader skips it by size and parses the following chunks normally

### Requirement: Little-endian scalar encoding

All multi-byte scalar fields in chunk headers and payloads (chunk sizes, `Version`,
`AppCount`, `Flags`, PCX header Words) SHALL be stored little-endian, matching the
native byte order of the 8088 target and the RIFF standard.

#### Scenario: Cross-platform read

- **WHEN** a file is written on any host and read on the DOS target
- **THEN** every scalar field decodes to the same value because writers and readers
  both use explicit little-endian layout

### Requirement: Sequential chunk stream termination

Readers SHALL stop reading chunks when the declared RIFF form size is exhausted or the
end of file is reached, whichever comes first. A chunk header that cannot be read in
full (truncated file) SHALL terminate parsing without error, keeping all entries
loaded so far.

#### Scenario: Truncated trailing chunk

- **WHEN** the file ends partway through a chunk header after the last complete
  `APP ` entry
- **THEN** the reader keeps the entries already loaded and finishes loading normally
