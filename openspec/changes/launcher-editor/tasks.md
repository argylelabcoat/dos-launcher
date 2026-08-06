# Tasks: launcher-editor

## 1. Shared contract

- [ ] 1.1 Add `{$IFDEF FPC}{$MODE TP}{$ENDIF}` guard to `snips/RiffLauncher.pas` if desktop FPC requires it; confirm record layouts unchanged (244-byte `TAppInfo`)
- [ ] 1.2 Verify `snips/RiffLauncher.pas` compiles under both desktop FPC and the DOS target (`-Mtp` / TP7)

## 2. Format units (editor/, no LCL dependencies)

- [ ] 2.1 `LauncherDoc.pas`: document model — ordered entry list (max 50), dirty flag, add/edit/remove/reorder, save-time validation (non-empty exec path, field limits)
- [ ] 2.2 `RiffReader.pas`: RCLF loader implementing the hardened chunk walk (word alignment, unknown-chunk skip, LIST/APPS/APP nesting, truncation guards, descriptive errors)
- [ ] 2.3 `RiffWriter.pas`: RCLF serializer into `TMemoryStream` — HDER + LIST/APPS of APP entries, INFO/ICON chunks, word alignment, correct RIFF/LIST size fields
- [ ] 2.4 Atomic save: write temp file, reload with `RiffReader`, compare entry count and fields, rename over target; report failure without touching the existing file
- [ ] 2.5 `IconConvert.pas`: load image (PNG/BMP via `TPicture`; spec-valid 32x32 4-plane PCX passthrough), scale to 32x32, quantize to the 16 standard VGA colors, emit planar RLE PCX; include a PCX-decode helper for preview parity with the DOS decoder

## 3. GUI (editor/, Lazarus)

- [ ] 3.1 Scaffold `LauncherEditor.lpi/.lpr` and main form: entry list (title + icon thumbnail), edit panel (Title/Desc/ExecPath/Args with `MaxLength` 40/70/64/64, two flag checkboxes), menu/toolbar (New/Open/Save/Add/Remove/Up/Down/Import icon/Clear icon)
- [ ] 3.2 Wire entry list to document model, including reorder and the 50-entry limit message
- [ ] 3.3 Icon preview: render the quantized 32x32 result scaled up (same pixels the launcher will draw)
- [ ] 3.4 Save-flow integration: block save on validation errors with the offending entry highlighted; default file name `LAUNCHER.DAT` (8.3-safe)

## 4. Verification

- [ ] 4.1 Round-trip: build a file with icons, flags, reordered entries → save → reopen in editor → identical
- [ ] 4.2 Interop: run `RiffDOSParser` on editor output — chunk dump matches entry count and structure
- [ ] 4.3 DOS interop: load editor output in the hardened launcher under DOSBox — entries, icons, and flags behave per the launcher spec
- [ ] 4.4 Negative tests: open malformed files (bad root, bad version, truncated) — descriptive error, document untouched; failed save leaves the on-disk file intact
