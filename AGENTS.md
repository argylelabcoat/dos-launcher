# AGENTS.md

## Project overview

This is a retro-computing project: a **DOS game launcher for the Book-8088** (an 8088-class handheld/retro PC), written in Turbo Pascal–style Pascal. It runs in real-mode DOS using the BGI (Borland Graphics Interface) graphics library in VGA 640x480 16-color mode (`VGA` / `VGAHi`).

The launcher:

- Reads game/app metadata and icons from a single RIFF container file (`LAUNCHER.DAT`, custom form type `RCLF`).
- Renders a paginated, keyboard-driven menu (arrows to navigate, ENTER to launch, ESC to quit).
- Pre-decodes 32x32 16-color PCX icons into raw 516-byte BGI `PutImage` RAM buffers for instant blitting.
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

`ICON` chunks embed a standard 16-color planar PCX (32x32, 4 bitplanes, RLE-encoded). `RiffBgiIcon.LoadRiffIconToBGI` decodes the RLE stream directly into the BGI `PutImage` memory layout (4-byte width/height header followed by per-scanline Plane0..Plane3 bytes), so icons can be blitted with a single `PutImage` call at draw time with no per-frame decoding.

## Source layout (all under `snips/`)

- `launcher.pas` — **main program** (`DOSLAUNCHER`). UI rendering, keyboard event loop, RIFF loading, game launch via `ExecWithSwap`. Sets `{$M 16384, 0, 65536}` (16KB stack, 64KB max heap) to keep the RAM footprint low.
- `RiffLauncher.pas` — **unit**: shared RIFF type definitions, FourCC constants, `SameFourCC` helper. The interface contract between all RIFF-reading code.
- `RiffBgiIcon.pas` — **unit**: PCX-in-RIFF → BGI buffer decoder (`LoadRiffIconToBGI`, `FreeBgiIcon`).
- `ExecSwap.pas` — **unit**: swap-to-disk execution (`ExecWithSwap`). Writes `Mem[PrefixSeg:0..HeapPtr]` to disk, calls `Dos.Exec`, restores memory afterwards. Return codes: 0 success, 1 swap-file create failed, 2 swap write failed, 3 exec error (check `DosError`).
- `RiffDOSParser.pas` — standalone **utility program**: parses `LAUNCHER.DAT` and prints chunk contents to the console; useful for debugging/verifying data files. Handles unknown-chunk skipping with RIFF word alignment.
- `PCX16Decoder.pas` — standalone **utility program**: reference 16-color PCX decoder that renders a file to screen via `PutPixel` and programs the VGA DAC palette directly through ports. Not used by the launcher itself.

`launcher.pas` depends on the three units (`RiffLauncher`, `RiffBgiIcon`, `ExecSwap`); the two utility programs depend only on `RiffLauncher`.

## Build

There is no build script or manifest in the repository. To build, use a DOS Pascal compiler (Turbo Pascal 7 in DOS, or Free Pascal cross-compiling to `i8086-msdos`), compiling `snips/launcher.pas` as the main program with `snips/` on the unit search path. Examples (not provided by the repo):

```sh
# Free Pascal (TP-compatible mode is already set via {$MODE TP} in the source)
fpc -Mtp snips/launcher.pas

# Turbo Pascal 7 (inside DOS / DOSBox)
tpc snips\launcher.pas
```

Units not carrying their own `{$MODE TP}` directive may need `-Mtp` passed explicitly under FPC.

## Code style guidelines

- Turbo Pascal dialect: `program`/`unit` structure, short strings (`string[N]`), `{$I-}`/`{$I+}` around I/O with `IOResult` checks — never exceptions.
- `CamelCase` for procedures/functions/types (`T`-prefixed types), `UPPER_SNAKE` for constants, FourCCs compared with `SameFourCC` rather than direct `=`.
- Memory-constrained mindset: fixed-size buffers and arrays (`MAX_APPS = 50`), minimal heap use, icons pre-decoded once at load time, key-repeat flushed with `while KeyPressed do ReadKey;` for slow 8088 CPUs.
- Comments are in English, in `{ ... }` braces, and typically explain *why* (hardware/DOS rationale) rather than *what*.
- Direct hardware/low-level access (`Port[]`, `Mem[]`, `PrefixSeg`, `HeapPtr`) is normal and idiomatic here — do not abstract it away.
- Buffers sized for exact formats (e.g. 516-byte BGI icon) use literal sizes documented in comments; keep them in sync when touching icon code.

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
