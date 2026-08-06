# Design: launcher-editor

## Context

The DOS launcher reads `LAUNCHER.DAT`, an RCLF (RIFF) container whose contract is
frozen by change `rclf-format-and-loader-hardening`: packed records with TP short
strings, a 244-byte `TAppInfo`, 32x32 4-plane RLE PCX icons, word alignment. Today
no writer for this format exists. The editor is a Lazarus/FPC desktop GUI
(user-confirmed) that authors these files on a modern host and must agree with the
DOS reader byte-for-byte.

Key constraint: `snips/RiffLauncher.pas` is the single source of truth for record
layouts and must compile under both the DOS toolchain (TP7 / FPC i8086-msdos, TP
mode) and desktop FPC/Lazarus. It currently has no `{$MODE}` directive and relies
on the caller's `-Mtp`; short strings inside packed records require TP/Delphi-mode
or `{$H-}` semantics.

## Goals / Non-Goals

**Goals:**

- GUI CRUD for launcher data files with spec-compliant RCLF output.
- Icon pipeline: arbitrary image → 32x32, 16-color VGA palette → planar RLE PCX.
- Maximal reuse of launcher units; zero divergence in the on-disk format.
- Atomic saves; descriptive errors on malformed input.

**Non-Goals:**

- An on-device DOS editor (explicitly rejected — host-side only).
- A PCX paint program; icon editing is import/scale/quantize/clear only.
- Editing BGI/swap configuration or anything outside `LAUNCHER.DAT`.
- Palette customization — the standard 16-color VGA palette is fixed.

## Decisions

### D1: Project layout

New top-level `editor/` directory: `LauncherEditor.lpi/.lpr`, one main form unit,
and non-GUI units `RiffWriter.pas` (serializer), `RiffReader.pas` (loader used for
open/verify), `IconConvert.pas` (image → PCX pipeline), `LauncherDoc.pas` (document
model: entry list, dirty flag, validation). GUI code never touches file format
details; the document model never touches LCL widgets — keeps the format units
testable from a console harness if wanted.

### D2: Reuse `snips/RiffLauncher.pas` as the shared contract

Add the editor's unit path to `snips/` rather than copying the unit. If desktop FPC
rejects it (no mode directive at unit level), add at its top:

```pascal
{$IFDEF FPC}
  {$MODE TP}
  {$PACKRECORDS 1}
{$ENDIF}
```

The `{$PACKRECORDS 1}` guard already exists; `{$MODE TP}` added the same way is
inert for TP7 and matches how `launcher.pas` is already compiled under FPC. Record
layouts are not touched. Alternative considered: duplicate the types in an
editor-only unit — rejected, two sources of truth for a binary format will drift.

### D3: RCLF serialization in a dedicated writer unit

`RiffWriter` builds the file in memory (or streamed with explicit size backpatching):
compute each chunk's size, write header + payload + pad, accumulate list sizes, then
backpatch `LIST`/`RIFF` size fields. Backpatching via seek on the real file is fine
(sizes are LongInt at fixed offsets) and avoids holding large buffers; a
`TMemoryStream` + single write is equally acceptable for files this small
(≤ ~50 × (244 + ~1KB)) — prefer `TMemoryStream`, then one atomic write-to-temp +
rename per the spec.

### D4: Icon pipeline ports the DOS logic, minus BGI

`IconConvert` mirrors `RiffBgiIcon.pas`/`PCX16Decoder.pas` bitplane logic exactly,
inverted: pixels → 4 planes → RLE. Steps: load via LCL (`TPicture`, which covers
PNG/BMP; PCX needs a small reader or `fpimage` PCX support — confirm at
implementation time, fallback is BMP/PNG only plus raw passthrough for already-valid
PCX), stretch to 32x32, map each pixel to nearest of the 16 standard VGA colors
(RGB euclidean distance is sufficient at this size), emit planes 0..3 with 4 bytes
per scanline, PCX RLE encode (run marker `$C0|len`). Preview renders the quantized
32x32 result scaled up — i.e. exactly what the decoder will produce, satisfying the
"preview matches launcher" requirement by construction.

### D5: Validation at two layers

Input-time: `MaxLength` on edit controls, checkbox pair for flags. Save-time: the
document model re-validates (non-empty exec path, entry count ≤ 50) and refuses with
a per-entry error list. Round-trip self-check on save: after writing, reload the
temp file with `RiffReader` and compare entry count/fields before renaming over the
target — cheap insurance for a format with manual size bookkeeping.

### D6: Reader is the spec's mirror, not launcher code

`RiffReader` implements the hardened chunk walk (alignment, unknown-chunk skip,
LIST nesting, truncation guards) in modern FPC (exceptions allowed editor-side per
project conventions, which restrict `{$I-}` style to DOS code). It does not share
code with `launcher.pas` — the two readers are independent implementations of the
same spec, which is deliberate: disagreement between them flags a spec ambiguity.

## Risks / Trade-offs

- [LCL `TPicture` PCX support is spotty across widgetsets] → Support PNG/BMP via
  `TPicture`; accept PCX only through our own reader when it is already a
  spec-valid 32x32 4-plane file (passthrough, no re-encode). Document the fallback.
- [Nearest-color quantization can look rough for photos] → Acceptable for 32x32
  launcher icons; ordered dithering is a possible later enhancement, not in scope.
- [Mode-directive change to the shared unit could upset TP7] → `{$IFDEF FPC}`
  guard makes it invisible to TP7; verified by compiling both sides in tasks.
- [Size backpatching bugs corrupt files silently] → Mitigated by D5's post-save
  reload-and-compare before atomic rename.

## Migration Plan

1. Land change `rclf-format-and-loader-hardening` (spec + hardened loader) first —
   it defines what the editor writes.
2. Scaffold the Lazarus project, port format units, wire the GUI.
3. Verify with `RiffDOSParser` and the DOS launcher in DOSBox; ship a sample
   `LAUNCHER.DAT` built by the editor.

## Open Questions

- PCX import: rely on `fpimage` PCX reader or restrict PCX to spec-valid
  passthrough? Decide during implementation based on the installed FPC version.
- Should the editor default the working file name to `LAUNCHER.DAT` (uppercase,
  8.3) for DOS friendliness? Leaning yes — enforce 8.3-safe names in save dialog.
