# dosbox-verify

Manual/emulator-based verification for the launcher, per the "Testing"
section of `AGENTS.md` — there's no automated test suite, so this is
where built DOS binaries actually get run.

## Layout

- `launcher_root/` — mounted as `C:` in DOSBox-X to run the interactive
  launcher itself (`LAUNCHER.EXE` + `LAUNCHER.DAT`).
- `dosroot/` — mounted as `C:` for exercising `RiffDOSParser.pas`
  (built here as `RIFFP.EXE`) against the RIFF/RCLF fixture files
  (`GOOD.DAT`, `BADVER.DAT`, `TOOMANY.DAT`, `TRUNC.DAT`, `WRONGFT.DAT`)
  described in
  `openspec/specs/rclf-format-and-loader-hardening/tasks/03-verification.md`.
  The `OUT*.TXT` files are captured stdout from prior `RIFFP.EXE <fixture>`
  runs against those fixtures, for reference.
- `test.conf` — a DOSBox-X config snippet (CPU core/type/FPU settings)
  merged in via `-conf test.conf` for both flows above.
- `build*.log` — historical `make crossinstall` build logs from earlier
  attempts at building the i8086-msdos FPC cross compiler.

## Building

```sh
./scripts/build-cross-compiler.sh   # one-time, installs into fpc-i8086-install/ below
./scripts/build.sh                  # builds launcher_root/LAUNCHER.EXE + dosroot/RIFFP.EXE
```

See `AGENTS.md`'s Build section for the full explanation of what these
scripts work around (fpcupdeluxe's GUI cross-compiler builder doesn't
work for this target on Apple Silicon macOS — NASM vs. binutils, a
modern-Xcode linker fix, and an FPC Makefile flag-scoping gotcha), and
for the manual compile command if you want to run it yourself instead of
via `build.sh`. The cross compiler itself lands at:

```
dosbox-verify/fpc-i8086-install/lib/fpc/<version>/ppcross8086
```

(gitignored — regenerate any time via `build-cross-compiler.sh`, ~a few
minutes).

One thing worth knowing if you're editing `snips/*.pas`: this project
builds with `-Mtp` (matching `launcher.pas`'s own `{$MODE TP}`
directive), and real Turbo Pascal requires an explicit `^` when indexing
a pointer-to-array (`p^[i]`) — the `p[i]` shorthand is an FPC/Delphi-mode
extension TP doesn't have. `RiffBgiIcon.pas` originally used the
shorthand and failed to compile the first time this project was ever run
through a real cross compiler (see the `pByteArray^[...]` fix in that
file) — the bug had gone uncaught until a working cross compiler
actually existed.

## Launching the launcher in DOSBox-X

```sh
cd dosbox-verify
dosbox-x -conf test.conf \
  -c "MOUNT C launcher_root" \
  -c "C:" \
  -c "LAUNCHER.EXE"
```

This boots DOS, mounts `launcher_root/` as `C:`, and runs
`LAUNCHER.EXE` directly, which reads `LAUNCHER.DAT` in the same
directory and renders the paginated icon menu in VGA 640x480 16-color
mode. Confirmed working (DOSBox-X log shows the aspect-ratio switch to
640x480 that `InitGraph` triggers, no crash) by building fresh with the
newly-built cross compiler above and launching it.

Use arrow keys to navigate, Enter to launch an entry, Esc to quit back
to DOS.

## Running the RIFF parser fixtures

```sh
cd dosbox-verify
dosbox-x -conf test.conf \
  -c "MOUNT C dosroot" \
  -c "C:" \
  -c "RIFFP.EXE GOOD.DAT"
```

Swap `GOOD.DAT` for any of the other fixtures to see how the naive
`RiffDOSParser` dumper handles each malformed-input case (compare
against the `OUT*.TXT` captures and the Python-ported behavioral model in
`fixtures/build_and_check.py`, which mirrors the *hardened* loader in
`launcher.pas` rather than this naive reference parser).
