#!/usr/bin/env bash
#
# build-cross-compiler.sh
#
# Builds the Free Pascal i8086-msdos cross compiler (ppcross8086) this
# project's build depends on, installing it to dosbox-verify/fpc-i8086-install/
# (gitignored, ~51MB, fully regenerable -- see .gitignore).
#
# Prerequisite: a native FPC install with its source tree, as provided by
# fpcupdeluxe (https://github.com/LongDirtyAnimAlf/fpcupdeluxe). This
# script does NOT install fpcupdeluxe or a native FPC for you -- run
# fpcupdeluxe's own "install native FPC" step first.
#
# Why this script exists instead of just using fpcupdeluxe's GUI cross-
# compiler builder: on Apple Silicon macOS, fpcupdeluxe's GUI fails for
# this target with a misleading "Failed to get crossbinutils" error. The
# real requirements (NASM, not GNU binutils; a couple of Xcode/toolchain
# workarounds) are documented in AGENTS.md's Build section and in
# dosbox-verify/README.md. This script encodes the working `make
# crossinstall` invocation directly, bypassing the GUI's fragile
# auto-detection for this target.
#
# Usage:
#   ./scripts/build-cross-compiler.sh
#
# Override any of these env vars if your fpcupdeluxe install differs from
# a stock fpcupdeluxe-aarch64-darwin-cocoa.app layout:
#   FPCUP_ROOT, FPCSRC, HOST_FPC, CLT_SDK

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FPCUP_ROOT="${FPCUP_ROOT:-/Applications/fpcupdeluxe}"
FPCSRC="${FPCSRC:-$FPCUP_ROOT/fpcsrc}"
HOST_FPC="${HOST_FPC:-$FPCUP_ROOT/fpc/bin/aarch64-darwin/fpc}"
CLT_SDK="${CLT_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
INSTALL_PREFIX="$REPO_ROOT/dosbox-verify/fpc-i8086-install"

echo "==> Checking prerequisites"

if [ ! -d "$FPCSRC" ]; then
  echo "ERROR: FPC source tree not found at $FPCSRC (set FPCSRC)" >&2
  exit 1
fi
if [ ! -x "$HOST_FPC" ]; then
  echo "ERROR: host FPC not found/executable at $HOST_FPC (set HOST_FPC)" >&2
  echo "       Install a native FPC via fpcupdeluxe first." >&2
  exit 1
fi
if [ ! -d "$CLT_SDK" ]; then
  echo "ERROR: Command Line Tools SDK not found at $CLT_SDK" >&2
  echo "       Run 'xcode-select --install' or set CLT_SDK." >&2
  exit 1
fi

echo "==> Ensuring NASM is installed"
# FPC's i8086-msdos backend assembles via NASM, not GNU binutils -- and
# the RTL build scripts shell out to a binary literally named
# "msdos-nasm". NASM is architecture-agnostic so a normal Homebrew
# install works as-is; we just need the alias.
if ! command -v nasm >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || { echo "ERROR: need nasm or Homebrew" >&2; exit 1; }
  brew install nasm
fi
NASM_DIR="$(dirname "$(command -v nasm)")"
command -v msdos-nasm >/dev/null 2>&1 || ln -sf "$(command -v nasm)" "$NASM_DIR/msdos-nasm"

echo "==> Building ppcross8086 into $INSTALL_PREFIX (a few minutes)"
cd "$FPCSRC"

# See AGENTS.md's Build section for what each of these flags is working
# around (modern-Xcode linker, FPC_SOFT_FPUX80 needing to be scoped to
# only the i8086-targeting build stage via OPTLEVEL2, etc).
make crossinstall \
  OS_TARGET=msdos \
  CPU_TARGET=i8086 \
  FPC="$HOST_FPC" \
  CROSSOPT="-WmLarge -CX -XX -Xs -dFPC_SOFT_FPUX80" \
  OPT="-XR${CLT_SDK} -k-ld_classic" \
  OPTLEVEL2="-dFPC_SOFT_FPUX80 -Fu../rtl/inc" \
  INSTALL_PREFIX="$INSTALL_PREFIX"

FPC_VERSION="$("$HOST_FPC" -iV)"
PPCROSS="$INSTALL_PREFIX/lib/fpc/$FPC_VERSION/ppcross8086"

if [ ! -x "$PPCROSS" ]; then
  echo "ERROR: build finished but ppcross8086 missing at $PPCROSS" >&2
  exit 1
fi

echo "==> Success: $PPCROSS"
"$PPCROSS" -iV
echo "==> Now run ./scripts/build.sh to build the launcher itself."
