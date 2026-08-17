#!/usr/bin/env bash
#
# run.sh
#
# Builds (unless --no-build) and launches the DOS launcher in DOSBox-X.
# See dosbox-verify/README.md for the manual equivalent.
#
# Usage:
#   ./scripts/run.sh              # build + run launcher
#   ./scripts/run.sh --no-build   # run already-built launcher
#   ./scripts/run.sh --riffp [FIXTURE]   # run RIFFP.EXE against a fixture
#   ./scripts/run.sh --music      # run MUSIC.EXE (PC-speaker music verifier)
#
# FIXTURE is one of the *.DAT files in dosbox-verify/dosroot/ (default
# GOOD.DAT).
#
# --music requires DOSBox-X's PC speaker enabled (pcspeaker=true).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DO_BUILD=1
MODE=launcher
FIXTURE="GOOD.DAT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --riffp) MODE=riffp; shift; [[ $# -gt 0 ]] && { FIXTURE="$1"; shift; } ;;
    --music) MODE=music; shift ;;
    -h|--help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1 (try --help)" >&2; exit 2 ;;
  esac
done

DOSBOX_X="${DOSBOX_X:-dosbox-x}"
if ! command -v "$DOSBOX_X" >/dev/null 2>&1; then
  echo "ERROR: $DOSBOX_X not found on PATH (set DOSBOX_X to override)" >&2
  exit 1
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
  "$REPO_ROOT/scripts/build.sh"
fi

cd "$REPO_ROOT/dosbox-verify"

if [[ "$MODE" == "riffp" ]]; then
  exec "$DOSBOX_X" -conf test.conf \
    -c "MOUNT C dosroot" \
    -c "C:" \
    -c "RIFFP.EXE $FIXTURE"
elif [[ "$MODE" == "music" ]]; then
  exec "$DOSBOX_X" -conf test.conf \
    -c "MOUNT C musicroot" \
    -c "C:" \
    -c "MUSIC.EXE"
else
  exec "$DOSBOX_X" -conf test.conf \
    -c "MOUNT C launcher_root" \
    -c "C:" \
    -c "LAUNCHER.EXE"
fi
