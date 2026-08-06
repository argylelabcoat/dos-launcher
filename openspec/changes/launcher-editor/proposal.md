# Proposal: launcher-editor

## Why

There is no tooling to author `LAUNCHER.DAT`. Hand-building an RCLF container —
packed TP short-string records, RLE PCX icons, RIFF word alignment — is error-prone,
and the launcher's loader is the only consumer, so mistakes surface only on the DOS
target. A GUI editor is needed to create and edit launcher data files reliably.

## What Changes

- New Lazarus/FPC desktop application (the **launcher editor**) that:
  - Creates, opens, edits, and saves `LAUNCHER.DAT` files conforming to the
    `rclf-container` spec (depends on change `rclf-format-and-loader-hardening`).
  - Manages an ordered list of applications: add, edit, remove, and reorder entries
    with Title / Description / Exec path / Args / launch flags (pause on exit,
    clear screen).
  - Imports icon images, scales/crops them to 32x32, quantizes to the 16-color VGA
    palette, and embeds them as 4-plane RLE PCX in `ICON` chunks; shows a live
    preview.
  - Enforces field limits (40/70/64/64 characters, required exec path) at edit time.
  - Reports malformed files with a clear error instead of crashing.
- Shared Pascal code with the DOS project:
  - Reuses `snips/RiffLauncher.pas` unchanged for the RCLF type contract.
  - Adds editor-side units for RCLF writing and icon conversion, porting the
    bitplane/RLE logic from `snips/RiffBgiIcon.pas` / `snips/PCX16Decoder.pas`
    without their `Graph`/BGI dependency.

## Capabilities

### New Capabilities

- `editor`: The Lazarus/FPC launcher editor — data file CRUD, entry editing and
  validation, icon import/conversion/preview, and RCLF serialization with
  round-trip fidelity against the DOS launcher and `RiffDOSParser`.

### Modified Capabilities

(None — the editor targets the `rclf-container` spec as-is from change
`rclf-format-and-loader-hardening`; if implementation reveals format ambiguities,
they are resolved in that change's spec first.)

## Impact

- New directory `editor/` with the Lazarus project (`.lpi`, main form, editor
  units). The `snips/` DOS sources are untouched except for a possible
  `{$IFDEF FPC}` mode-directive guard in `RiffLauncher.pas` if Lazarus compilation
  requires it.
- New shared-code constraint: `RiffLauncher.pas` must compile under both the DOS
  toolchain (TP7 / FPC i8086-msdos) and desktop FPC — no exceptions, generics, or
  managed-string assumptions in that unit.
- Depends on the `rclf-container` spec from change
  `rclf-format-and-loader-hardening`; the editor writes exactly what the hardened
  launcher reads.
- Verification loop: editor output → `RiffDOSParser` dump → launcher in DOSBox.
