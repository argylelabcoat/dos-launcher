# AGENTS.md

## Project overview

This is a retro-computing project: a **DOS game launcher for the Book-8088** (an 8088-class handheld/retro PC), written in Turbo Pascal–style Pascal. It runs in real-mode DOS using the BGI (Borland Graphics Interface) graphics library in VGA 640x480 16-color mode (`VGA` / `VGAHi`).

The launcher:

- Reads game/app metadata and icons from a single RIFF container file (`LAUNCHER.DAT`, custom form type `RCLF`).
- Renders a paginated, keyboard-driven menu (arrows to navigate, ENTER to launch, ESC to quit).
- Pre-decodes 32x32 16-color PCX icons into raw `PutImage` RAM buffers for instant blitting.
- When launching a game, swaps its own entire memory image (PSP + code + data + heap) out to a disk swap file (`C:\SWAP.TMP`), runs the game with `Dos.Exec`, then reloads itself — freeing ~550KB of conventional RAM for the child program.

The `snips/` directory contains the complete source. There is no build system, package manifest, or test suite in the repo — these are source "snippets" intended to be compiled with an external DOS Pascal toolchain.

## Technology stack and runtime architecture

- **Language:** Pascal, Turbo Pascal dialect (`{$MODE TP}` in `launcher.pas`). Compatible targets are Turbo Pascal 7 / Borland Pascal and Free Pascal in TP mode.
- **Platform:** 16-bit real-mode DOS (8088-class CPU). Code relies on TP real-mode specifics: `Dos` unit (`Exec`, `SwapVectors`, `PrefixSeg`, `DosError`), `Mem[]` / `Seg()` / `HeapPtr` memory access, direct VGA DAC port I/O (`Port[$3C8/$3C9]`), and BGI (`Graph` unit).
- **Runtime files expected on the DOS machine:**
  - `LAUNCHER.DAT` — RIFF data file in the working directory.
  - A BGI driver (e.g. `EGAVGA.BGI`) reachable from the working directory or BGI path — `InitGraph(Gd, Gm, '')` is called with an empty driver path.
  - `C:\SWAP.TMP` is used as the swap-file path when launching games.

### The RIFF launcher format (`RCLF`)

Defined by `RiffLauncher` unit:

- Root: standard RIFF header, form type `RCLF` ("RIFF Container Launcher Format").
- Chunk IDs (FourCC): `HDER` (launcher header: version, app count, flags), `LIST`, `APPS`, `APP ` (note trailing space), `INFO` (per-app `TAppInfo` record: title/desc/exec path/args as fixed-size short strings), `ICON` (a 32x32 4-plane 16-color RLE PCX image).
- All on-disk records are `packed` (`{$PACKRECORDS 1}` under FPC). `TAppInfo` uses Turbo Pascal short strings (`string[N]`, 1 length byte + N bytes), so the file format is TP-specific, not plain C strings.
- Chunks with odd sizes are word-aligned (2-byte padding rule) — see `SkipChunk` in `RiffDOSParser.pas`.

### Icon pipeline

`ICON` chunks embed a standard 16-color planar PCX (32x32, 4 bitplanes, RLE-encoded). `RiffBgiIcon.LoadRiffIconToBGI` decodes the RLE stream and re-packs it into the memory layout FPC's `Graph` unit's `PutImage` actually expects, so icons can be blitted with a single `PutImage` call at draw time with no per-frame decoding.

**Important:** FPC's `Graph` unit (`packages/graph/src/inc/graph.inc`, `DefaultGetImage`/`DefaultPutImage` — used as-is for the `msdos`/`i8086` target, no override) does **not** use real Borland BGI's packed-bitplane `GetImage`/`PutImage` binary format. It uses its own: a 12-byte header (three `LongInt`s — Width, Height, Reserved) followed by one `Word` (raw color index) per pixel in raster order — not the 4-byte "Width-1/Height-1 word pair" + 1-bit-per-plane packed bitplanes real BGI uses. `RiffBgiIcon.pas` targets FPC's format specifically. This means the "Free Pascal in TP mode" and "Turbo Pascal 7 / Borland Pascal" compatible-target claim above does **not** extend to icon rendering — a real TP7/Borland BGI build would need a different `LoadRiffIconToBGI` implementation (real BGI's packed-plane format) to display icons correctly, even though the rest of the codebase is source-compatible with both.

## Source layout (all under `snips/`)

- `launcher.pas` — **main program** (`DOSLAUNCHER`). UI rendering, keyboard event loop, RIFF loading, game launch via `ExecWithSwap`. Sets `{$M 16384, 0, 65536}` (16KB stack, 64KB max heap) to keep the RAM footprint low.
- `RiffLauncher.pas` — **unit**: shared RIFF type definitions, FourCC constants, `SameFourCC` helper. The interface contract between all RIFF-reading code.
- `RiffBgiIcon.pas` — **unit**: PCX-in-RIFF → BGI buffer decoder (`LoadRiffIconToBGI`, `FreeBgiIcon`).
- `ExecSwap.pas` — **unit**: swap-to-disk execution (`ExecWithSwap`). Writes `Mem[PrefixSeg:0..HeapPtr]` to disk, calls `Dos.Exec`, restores memory afterwards. Return codes: 0 success, 1 swap-file create failed, 2 swap write failed, 3 exec error (check `DosError`).
- `RiffDOSParser.pas` — standalone **utility program**: parses `LAUNCHER.DAT` and prints chunk contents to the console; useful for debugging/verifying data files. Handles unknown-chunk skipping with RIFF word alignment.
- `PCX16Decoder.pas` — standalone **utility program**: reference 16-color PCX decoder that renders a file to screen via `PutPixel` and programs the VGA DAC palette directly through ports. Not used by the launcher itself.

`launcher.pas` depends on the three units (`RiffLauncher`, `RiffBgiIcon`, `ExecSwap`); the two utility programs depend only on `RiffLauncher`.

## Build

Build with an FPC `i8086-msdos` cross compiler (Turbo Pascal 7 in DOS/DOSBox also works, but isn't scripted here). Two scripts drive the whole thing:

```sh
./scripts/build-cross-compiler.sh   # one-time: builds ppcross8086 into dosbox-verify/fpc-i8086-install/ (gitignored, ~few minutes)
./scripts/build.sh                  # builds launcher.exe + RiffDOSParser.exe, drops them into dosbox-verify/{launcher_root,dosroot}/
```

`build-cross-compiler.sh` assumes fpcupdeluxe (https://github.com/LongDirtyAnimAlf/fpcupdeluxe) already installed a native FPC at `/Applications/fpcupdeluxe` (override via `FPCUP_ROOT`/`FPCSRC`/`HOST_FPC` env vars). On Apple Silicon macOS, fpcupdeluxe's own GUI cross-compiler builder does **not** work for this target — it fails with a misleading `ERROR: Failed to get crossbinutils` — so these scripts drive FPC's `make crossinstall` directly instead. The real requirements it's working around, in case you need to debug a variant of this yourself:

- **NASM, not GNU binutils.** FPC's i8086-msdos backend emits NASM-syntax assembly and links with its own internal linker; it has no use for `as`/`ld`. It also shells out to a binary literally named `msdos-nasm` when building the RTL — `build-cross-compiler.sh` installs `nasm` via Homebrew and symlinks the alias.
- **Modern Xcode's linker breaks the native bootstrap stage.** Every cross-compiler build first re-verifies FPC's own native host compiler; on recent Xcode this fails linking with `ld: library 'c' not found` (the newer default linker, ld-prime, being stricter than this FPC version expects). Fixed with `-XR<CommandLineTools SDK> -k-ld_classic`.
- **`-dFPC_SOFT_FPUX80` must be scoped to only the i8086-targeting build stage.** The i8086 compiler needs this 80-bit-float software-emulation define, but setting it globally breaks the native aarch64 bootstrap stage instead (`Can't find unit sfpux80`). FPC's `compiler/Makefile` has a dedicated hook for this most guides don't mention: `OPTLEVEL2`, which only applies to `CYCLELEVEL=2` (the stage that actually targets your chosen CPU/OS).

Manual command, once the cross compiler exists (what `build.sh` runs):

```sh
PPC=dosbox-verify/fpc-i8086-install/lib/fpc/<version>/ppcross8086
UNITS=dosbox-verify/fpc-i8086-install/lib/fpc/<version>/units/msdos
$PPC -Tmsdos -Pi8086 -Mtp -WmLarge -CX -XX -Xs \
  -FD<dir containing nasm> \
  -Fu$UNITS/rtl -Fu$UNITS/rtl-console -Fu$UNITS/rtl-extra -Fu$UNITS/rtl-objpas -Fu$UNITS/graph \
  -Fusnips -FE<outdir> snips/launcher.pas
```

`-Mtp` matters beyond matching `launcher.pas`'s own `{$MODE TP}` directive: real Turbo Pascal (and FPC's `-Mtp` emulation of it) requires an explicit `^` when indexing a pointer-to-array (`p^[i]`) — the `p[i]` shorthand is an FPC/Delphi-mode extension TP doesn't have. `-Fu$UNITS/graph` (FPC's bundled `graph` package, a from-scratch TP7-compatible VGA driver — no `.BGI` files or Turbo Pascal needed) is only required for `launcher.pas`/`RiffBgiIcon.pas`; drop it for console-only programs like `RiffDOSParser.pas`.

See `dosbox-verify/README.md` for building the RTL/compiler itself and for running the result in DOSBox-X.

## Code style guidelines

- Turbo Pascal dialect: `program`/`unit` structure, short strings (`string[N]`), `{$I-}`/`{$I+}` around I/O with `IOResult` checks — never exceptions.
- `CamelCase` for procedures/functions/types (`T`-prefixed types), `UPPER_SNAKE` for constants, FourCCs compared with `SameFourCC` rather than direct `=`.
- Memory-constrained mindset: fixed-size buffers and arrays (`MAX_APPS = 50`), minimal heap use, icons pre-decoded once at load time, key-repeat flushed with `while KeyPressed do ReadKey;` for slow 8088 CPUs.
- Comments are in English, in `{ ... }` braces, and typically explain *why* (hardware/DOS rationale) rather than *what*.
- Direct hardware/low-level access (`Port[]`, `Mem[]`, `PrefixSeg`, `HeapPtr`) is normal and idiomatic here — do not abstract it away.
- Buffers sized for exact formats (e.g. the 2060-byte FPC `PutImage` icon buffer, see `RiffBgiIcon.pas`) use literal/derived sizes documented in comments; keep them in sync when touching icon code.

## Testing

There is no automated test suite. Verification is manual:

- `RiffDOSParser` — run against a `LAUNCHER.DAT` to verify container/chunk parsing.
- `PCX16Decoder` — run against a 16-color PCX to verify the decoding logic visually.
- The launcher itself is tested on target hardware or in an emulator (DOSBox / 86Box / Book-8088), checking menu rendering, paging, and swap-exec round-trips.

## Security / correctness considerations

- This is trusted-local retro software: it executes arbitrary paths read from `LAUNCHER.DAT` via `Dos.Exec`. That is by design — do not add sandboxing, but treat the data file as fully trusted input.
- `ExecSwap` performs raw block reads/writes of the entire program memory image; any change to memory layout assumptions (heap limits, `{$M}` directive, far-call requirements — note `{$F+}`) must be reviewed carefully or the swap/restore will corrupt state.
- File parsing does minimal bounds checking beyond header validation; malformed RIFF/PCX data can read out of bounds. Keep new parsing code defensive within real-mode constraints.
- Do not "modernize" the code (managed strings, classes, exceptions) — it must stay compilable for 16-bit real-mode DOS.
