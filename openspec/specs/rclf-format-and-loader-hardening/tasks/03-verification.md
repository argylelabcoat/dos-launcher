# Task: Verification

## Depends On
- launch-flags

## Acceptance Criteria
Feature: Hardened loader and launch-flag verification
  As the project maintainer
  I want the rewritten loader and flag-driven launch behavior proven against fixtures and DOSBox
  So that the RCLF hardening change is trustworthy before the editor depends on it

  Scenario: Well-formed file loads fully
    Given a spec-compliant LAUNCHER.DAT with 12 entries, some with icons and some without, one unknown chunk, and one odd-sized chunk
    When the hardened launcher loads the file
    Then all 12 entries load with correct titles, descriptions, paths, args, flags, and pre-decoded icons, and RiffDOSParser dumps the same file cleanly

  Scenario: More entries than MAX_APPS
    Given a file containing more than 50 APP entries
    When the launcher loads the file
    Then the first 50 entries load and the rest are skipped without error

  Scenario: 12 entries produce 2 pages
    Given 12 entries are loaded
    When the menu is rendered
    Then page 1 shows entries 1-7, page 2 shows entries 8-12, and the header shows "Page 1/2" or "Page 2/2" accordingly

  Scenario: Entry without icon renders cleanly
    Given an entry has no icon (missing or non-conforming PCX)
    When its row is drawn
    Then the row renders title and description with no image and no decode error

  Scenario: Successful launch round-trip with swap
    Given ENTER is pressed on an entry whose program exists
    When the launcher swaps out via ExecWithSwap
    Then the program runs, and on its exit the launcher restores itself, re-initializes graphics, and redraws the menu

  Scenario: Pause-on-exit and clear-screen flags observed in DOSBox
    Given entries with flag bit 0 and flag bit 1 set respectively
    When each is launched and exits under DOSBox
    Then the pause-on-exit entry waits for a keypress in text mode and the clear-screen entry clears text before the loading message

  Scenario: Wrong form type is rejected
    Given a RIFF file whose form type is not RCLF
    When the launcher attempts to load it
    Then it fails gracefully, loading no applications

  Scenario: Unsupported version is rejected
    Given a HDER chunk declaring a Version other than 1
    When the launcher attempts to load it
    Then it fails gracefully, loading no applications

  Scenario: Truncated file fails gracefully
    Given a LAUNCHER.DAT truncated mid-chunk
    When the launcher attempts to load it
    Then it keeps only the entries fully committed before the truncation point and does not crash

## Spec
Per `openspec/changes/rclf-format-and-loader-hardening/tasks.md` group 3 and the
migration plan in `design.md`:

1. Build a spec-compliant `LAUNCHER.DAT` fixture: 12+ entries, a mix of
   with/without icons, one unknown chunk, one odd-sized chunk. Confirm
   `snips/RiffDOSParser.pas` dumps it cleanly (correct chunk structure, sizes,
   entry count).
2. Compile `snips/launcher.pas` with FPC `-Mtp` (i8086-msdos target) and/or TP7 in
   DOSBox with no new warnings introduced by the `01-loader-rewrite` and
   `02-launch-flags` changes.
3. **Manual DOSBox verification required** — the automated compile check below
   cannot exercise runtime behavior. In DOSBox, verify: paging over 2+ pages,
   navigation clamping at list ends, an entry without an icon renders without
   error, a full launch round-trip with swap-to-disk, and both the pause-on-exit
   and clear-screen flags behave per spec. Do not mark this task COMPLETED until
   these manual checks have actually been run — a green compile alone is
   insufficient evidence per the project's format/GUI verification convention.
4. Negative tests: wrong form type, bad version, truncated file, and >50 entries
   must each fail gracefully (reject/skip, never crash or read out of bounds) —
   build one malformed fixture per case and confirm behavior against the
   `rclf-container` and `launcher` spec scenarios above.

## Test Files
(none — DOS-target unit and fixture-driven manual verification; no automated
harness exists for this project's DOS binaries)

## Implementation Files
- snips/launcher.pas
- snips/RiffDOSParser.pas (reference verifier, used but not modified)

## Test Command
An FPC i8086-msdos cross-compiler was built from source
(`~/fpcupdeluxe/fpcsrc`, `make crossinstall CPU_TARGET=i8086 OS_TARGET=msdos`)
and installed at `dosbox-verify/fpc-i8086-install/`. Real compile command
(includes FPC's bundled `graph` package, which provides a from-scratch
TP7-compatible VGA driver — no `.BGI` driver files or Turbo Pascal needed):

    PPC=dosbox-verify/fpc-i8086-install/lib/fpc/3.2.3/ppcross8086
    UNITS=dosbox-verify/fpc-i8086-install/lib/fpc/3.2.3/units/msdos
    $PPC -Tmsdos -Pi8086 -XPmsdos- -Ur -WmLARGE \
      -Fu$UNITS/rtl -Fu$UNITS/rtl-console -Fu$UNITS/rtl-extra -Fu$UNITS/rtl-objpas -Fu$UNITS/graph \
      -Fusnips -FE<outdir> snips/launcher.pas

This compiles and links a real DOS `.exe` (confirmed MZ header). Run under
DOSBox-X (`/Applications/DOSBox-X.app/Contents/MacOS/dosbox-x`, headless via
`-c`/`-silent`/`-time-limit`): with a real `LAUNCHER.DAT`, it runs without
crashing and DOSBox-X's own video log confirms `InitGraph(VGA, VGAHi)` actually
switches real emulated VGA hardware to 640x480 (`Aspect ratio: 640 x 480`).
Requires `AppList` to be heap-allocated (`PAppEntryArray`/`New`/`Dispose`
instead of a static global array) — a static `AppList` overflows the 64KB
DGROUP near-data segment once linked against the Graph unit's embedded font
data; see the `New(AppList)`/`Dispose(AppList)` calls in the program body.

Still not automatable: the *interactive* scenarios (paging, selection
highlight, ESC-driven navigation, swap round-trip, pause/clear-screen flags
observed live) need either keystroke injection or visual screenshot
inspection, neither of which was reliably scriptable via DOSBox-X's headless
`-c` command interface in this environment — same limitation noted below for
`Crt`-based interactive I/O (BIOS keyboard/video calls bypass DOS stdio
redirection entirely, so headless capture doesn't work once the menu loop is
running). A human running `dosbox-verify/launcher_root/LAUNCHER.EXE`
interactively in DOSBox-X is the remaining gap — do not mark this task
COMPLETED until that's done.
