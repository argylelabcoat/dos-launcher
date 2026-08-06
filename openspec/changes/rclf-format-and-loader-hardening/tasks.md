# Tasks: rclf-format-and-loader-hardening

## 1. Loader rewrite (snips/launcher.pas)

- [ ] 1.1 Add `Flags: Word` to `TAppEntry` and copy it from `TAppInfo` during load
- [ ] 1.2 Rewrite `LoadLauncherData` as a sequential chunk walk: validate RIFF root and `RCLF` form type, require `HDER` with `Version = 1` before any `LIST`
- [ ] 1.3 Implement bounded `LIST` handling (`APPS` containing `APP ` entries) with entry commit at end of each `APP ` list
- [ ] 1.4 Pair each `ICON` with the most recent `INFO` in the same `APP ` entry; support entries without icons
- [ ] 1.5 Add word-alignment skip (1 pad byte after odd-sized payloads) and seek-based unknown-chunk skipping clamped to container/file bounds
- [ ] 1.6 Add `{$I-}`/`IOResult` and byte-count guards on every `BlockRead`; truncated header keeps committed entries, truncated `INFO` discards the in-progress entry
- [ ] 1.7 Enforce `MAX_APPS = 50` cap: stop committing entries at 50, continue no further parsing work

## 2. Launch flags (snips/launcher.pas)

- [ ] 2.1 Make the pre-launch `ClrScr` conditional on `Flags` bit 1 (clear screen)
- [ ] 2.2 Add post-exit pause: when `Flags` bit 0 is set, wait for `ReadKey` in text mode before `InitGraph`

## 3. Verification

- [ ] 3.1 Build a spec-compliant `LAUNCHER.DAT` fixture (12+ entries, with/without icons, one unknown chunk, one odd-sized chunk) and confirm `RiffDOSParser` dumps it cleanly
- [ ] 3.2 Compile launcher with FPC `-Mtp` (and/or TP7 in DOSBox) with no new warnings
- [ ] 3.3 In DOSBox: verify paging over 2 pages, navigation clamping, entry without icon, launch round-trip with swap, pause-on-exit and clear-screen flags
- [ ] 3.4 Negative tests: wrong form type, bad version, truncated file, >50 entries — each must fail gracefully per spec
