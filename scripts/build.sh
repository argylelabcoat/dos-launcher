#!/usr/bin/env bash
#
# build.sh
#
# Builds the DOS launcher (snips/launcher.pas) and the RiffDOSParser
# reference utility with the i8086-msdos FPC cross compiler, and drops
# the results into dosbox-verify/{launcher_root,dosroot}/ ready for
# DOSBox-X verification (see dosbox-verify/README.md).
#
# Prerequisite: run ./scripts/build-cross-compiler.sh first (one-time,
# ~a few minutes) unless dosbox-verify/fpc-i8086-install/ already exists.
#
# Usage:
#   ./scripts/build.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HOST_FPC="${HOST_FPC:-/Applications/fpcupdeluxe/fpc/bin/aarch64-darwin/fpc}"
FPC_VERSION="$("$HOST_FPC" -iV 2>/dev/null || echo 3.2.2)"

PPC="dosbox-verify/fpc-i8086-install/lib/fpc/$FPC_VERSION/ppcross8086"
UNITS="dosbox-verify/fpc-i8086-install/lib/fpc/$FPC_VERSION/units/msdos"

if [ ! -x "$PPC" ]; then
  echo "ERROR: cross compiler not found at $PPC" >&2
  echo "       Run ./scripts/build-cross-compiler.sh first." >&2
  exit 1
fi

if ! command -v nasm >/dev/null 2>&1; then
  echo "ERROR: nasm not found on PATH (needed by the cross compiler to assemble)" >&2
  exit 1
fi
NASM_DIR="$(dirname "$(command -v nasm)")"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

COMMON_FLAGS=(
  -Tmsdos -Pi8086 -Mtp -WmLarge -CX -XX -Xs
  -FD"$NASM_DIR"
  -Fu"$UNITS/rtl" -Fu"$UNITS/rtl-console" -Fu"$UNITS/rtl-extra" -Fu"$UNITS/rtl-objpas"
  -Fusnips
)

echo "==> Building launcher.exe (snips/launcher.pas)"
"$PPC" "${COMMON_FLAGS[@]}" -Fu"$UNITS/graph" -FE"$BUILD_DIR" snips/launcher.pas
mkdir -p dosbox-verify/launcher_root
cp "$BUILD_DIR/launcher.exe" dosbox-verify/launcher_root/LAUNCHER.EXE
echo "    -> dosbox-verify/launcher_root/LAUNCHER.EXE"

echo "==> Building RiffDOSParser.exe (snips/RiffDOSParser.pas, reference verifier)"
"$PPC" "${COMMON_FLAGS[@]}" -FE"$BUILD_DIR" snips/RiffDOSParser.pas
mkdir -p dosbox-verify/dosroot
cp "$BUILD_DIR/RiffDOSParser.exe" dosbox-verify/dosroot/RIFFP.EXE
echo "    -> dosbox-verify/dosroot/RIFFP.EXE"

echo "==> Building MusicTest.exe (snips/MusicTest.pas, PC-speaker music verifier)"
"$PPC" "${COMMON_FLAGS[@]}" -FE"$BUILD_DIR" snips/MusicTest.pas
mkdir -p dosbox-verify/musicroot
# 8.3-safe name: "MUSICTEST.EXE" is 9 chars and would surface as MUSICT~1.EXE in DOS.
cp "$BUILD_DIR/MusicTest.exe" dosbox-verify/musicroot/MUSIC.EXE
echo "    -> dosbox-verify/musicroot/MUSIC.EXE"

cat <<'EOF'

Build complete. Verify in DOSBox-X:

  ./scripts/run.sh            # launcher
  ./scripts/run.sh --music    # PC-speaker music verifier (MUSIC.EXE)

See dosbox-verify/README.md for the RiffDOSParser fixture-testing flow.
EOF
