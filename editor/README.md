# editor/

A host-side (Lazarus/FPC, not DOS) tool for authoring `LAUNCHER.DAT` files, in two front-ends over the same format units:

- **`LauncherEditor`** — the GUI (`LauncherEditor.lpi`/`.lpr` + `MainForm.pas`). Build/run via Lazarus IDE or `lazbuild`.
- **`LauncherCli`** — a console program that builds a `LAUNCHER.DAT` from a YAML manifest and PNG icon files, for scripted/CI use without opening the GUI.

Both share the same non-GUI format units — `LauncherDoc.pas` (document model), `RiffWriter.pas`/`RiffReader.pas` (RCLF serialization), `IconConvert.pas` (32x32/16-color/planar-RLE-PCX icon pipeline), `SaveIO.pas` (atomic save with a round-trip self-check) — so the GUI and CLI can never disagree about the on-disk format. See `openspec/changes/launcher-editor/design.md` for the original design rationale.

## LauncherCli

```sh
cd editor
fpc -Mobjfpc -Sh -Fu<path-to-fcl-image-units> -Fu../snips LauncherCli.lpr
./LauncherCli manifest.yaml -o LAUNCHER.DAT
```

(`fcl-image` is FPC's non-LCL image-decoding package, e.g. `/usr/local/lib/fpc/<version>/units/<target>/fcl-image` on a typical install — needed for `PngLoader.pas`'s PNG decoding.)

### Manifest format

`YamlManifest.pas` accepts a deliberately small YAML *subset* — not a general-purpose YAML parser — with one fixed shape:

```yaml
apps:
  - title: "Game 1"
    desc: "Description for game 1"
    exec: "C:\GAMES\G1\GAME.EXE"
    args: "-fast"
    pause_on_exit: true
    clear_screen: false
    icon: "icons/game1.png"
  - title: "Game 2"
    exec: "C:\GAMES\G2\GAME.EXE"
    # desc, args, pause_on_exit, clear_screen, icon are all optional
```

Rules: a top-level `apps:` line starts the list; each entry starts with a line indented exactly 2 spaces (`  - key: value`), and its remaining keys are indented exactly 4 spaces. Values are either double-quoted (quotes stripped, no escape processing) or bare (trimmed). `#` starts a comment; blank lines are ignored. Unknown keys and non-`true`/`false` boolean values are rejected with a line-numbered error — a typo'd key silently doing nothing would be worse than a parse error.

`pause_on_exit`/`clear_screen` map to `Flags` bits 0/1 (see `AGENTS.md`). `icon`, if present, is a path to a PNG file, resolved relative to the manifest file's own directory (not the current working directory).

Content-level validation (non-empty `exec`, field length limits, `MAX_APPS`) is **not** done by the parser — that's `LauncherDoc.Validate`'s job, run after parsing, same as the GUI. The CLI reports every validation error (with 1-based entry numbers) before writing anything.

### Icon pipeline

`PngLoader.pas` loads a PNG via FPC's `fpImage`/`FPReadPNG` (no LCL dependency, so this works in a plain console program), nearest-neighbor-resizes it to 32x32, and quantizes each pixel to the nearest of the fixed 16 VGA colors via `IconConvert.QuantizeColor` — the same colors the DOS launcher actually renders with, since it never reprograms the palette (`snips/launcher.pas` has no `Port[$3C8/$3C9]`/`SetRGBPalette` calls). Partially transparent pixels are composited against black before quantizing (PCX/VGA has no alpha channel).

### Example

`editor/examples/manifest.yaml` + `editor/examples/icons/*.png` is a real, verified example — 8 apps, 7 with icons sourced from [Anthony's Icon Library](../../aicons) (XPM converted to PNG via ImageMagick as a one-off preprocessing step; `LauncherCli` only reads PNG). Build it:

```sh
cd editor
./LauncherCli examples/manifest.yaml -o /tmp/LAUNCHER.DAT
```

Verified: loads correctly against the Python reference model in `fixtures/build_and_check.py`, and boots cleanly in DOSBox-X against the real `LAUNCHER.EXE`.

## Tests

```sh
cd editor/tests
fpc -Mobjfpc -Sh \
  -Fu<path-to-fcl-fpcunit-units> \
  -Fu<path-to-fcl-image-units> \
  -Fu.. -Fu../../snips TestRunner.lpr
./TestRunner -a --format=plain
```
