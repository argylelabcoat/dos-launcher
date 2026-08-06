# Spec: launcher

Delta for the `launcher` capability (new).

## ADDED Requirements

### Requirement: Graphics startup

The launcher SHALL initialize BGI graphics in VGA 640x480 16-color mode
(`VGA`/`VGAHi`) at startup. If graphics initialization fails, the launcher MUST halt
with a nonzero exit code before attempting any data loading or rendering.

#### Scenario: Graphics init succeeds

- **WHEN** a BGI driver is reachable and `InitGraph` returns `grOk`
- **THEN** the launcher proceeds to load `LAUNCHER.DAT`

#### Scenario: Graphics init fails

- **WHEN** `InitGraph` returns a result other than `grOk`
- **THEN** the launcher halts with exit code 1 without rendering a menu

### Requirement: RCLF data loading

The launcher SHALL load application entries from `LAUNCHER.DAT` in the current
directory, parsing it as an RCLF container per the `rclf-container` spec: validating
the RIFF root and `HDER` version, walking chunks sequentially, honoring word
alignment, skipping unknown chunks, and pairing each `ICON` with the `INFO` of the
same `APP ` entry. At most 50 entries (`MAX_APPS`) SHALL be loaded; additional
entries MUST be ignored. Each entry's `Flags` field SHALL be retained for use at
launch time.

#### Scenario: Well-formed file loads fully

- **WHEN** `LAUNCHER.DAT` is spec-compliant with 12 entries each having INFO and ICON
- **THEN** all 12 entries load with correct titles, descriptions, paths, args, flags,
  and pre-decoded icons

#### Scenario: Missing data file

- **WHEN** `LAUNCHER.DAT` does not exist or cannot be opened
- **THEN** the launcher exits graphics, prints "No games found in LAUNCHER.DAT!", and
  waits for a keypress

#### Scenario: More entries than MAX_APPS

- **WHEN** the file contains more than 50 `APP ` entries
- **THEN** the first 50 entries load and the rest are skipped without error

#### Scenario: Unknown chunk does not desync loading

- **WHEN** the file contains an unrecognized chunk of declared size S between known
  chunks
- **THEN** the launcher skips S bytes plus any alignment pad and loads all following
  entries correctly

#### Scenario: Odd-sized chunk alignment

- **WHEN** any chunk declares an odd payload size
- **THEN** the launcher skips exactly one pad byte before reading the next chunk
  header

### Requirement: Icon pre-decoding

During loading, each `ICON` chunk SHALL be decoded exactly once from its embedded PCX
into a 516-byte BGI `PutImage` RAM buffer (4-byte width/height header followed by 32
scanlines of Plane0..Plane3 bytes). At draw time the launcher MUST blit icons with a
single `PutImage` call and MUST NOT re-decode PCX data per frame. Icon buffers SHALL
be released with the matching 516-byte `FreeMem` when freed.

#### Scenario: Icon blitted in one call

- **WHEN** a menu row with a valid icon is drawn
- **THEN** the icon appears via a single `PutImage` using the pre-decoded buffer

#### Scenario: Entry without icon

- **WHEN** an entry has no icon (missing or non-conforming PCX)
- **THEN** the row renders title and description with no image and no decode error

### Requirement: Menu rendering and paging

The launcher SHALL render a paginated menu showing 7 entries per page
(`ITEMS_PER_PAGE`), a header bar with title and `Page N/M` indicator, a footer with
key instructions, and a highlighted selection box around the current entry. Pages
SHALL be numbered such that page count is `(TotalApps + 6) div 7`, with at least one
page.

#### Scenario: 12 entries produce 2 pages

- **WHEN** 12 entries are loaded
- **THEN** page 1 shows entries 1-7, page 2 shows entries 8-12, and the header shows
  `Page 1/2` or `Page 2/2` accordingly

#### Scenario: Selection highlight

- **WHEN** an entry is the current selection
- **THEN** it is drawn with a yellow-bordered filled box and white title text;
  other entries render unhighlighted

### Requirement: Keyboard navigation

The launcher SHALL respond to these keys: UP/DOWN move the selection by one entry
(clamped at the ends, updating the current page to contain the selection); LEFT/RIGHT
switch pages (clamped), moving the selection to the first entry of the new page;
ENTER launches the selected entry; ESC quits the launcher. After each keypress the
launcher SHALL flush queued key repeats (`while KeyPressed do ReadKey`) so held keys
do not queue inputs on slow 8088 CPUs.

#### Scenario: Arrow-key movement clamps at ends

- **WHEN** the selection is on the first entry and UP is pressed
- **THEN** the selection stays on the first entry

#### Scenario: Page switch moves selection

- **WHEN** RIGHT is pressed on page 1 of 2
- **THEN** page 2 is displayed and the selection moves to the first entry of page 2

#### Scenario: ESC exits

- **WHEN** ESC is pressed
- **THEN** the launcher leaves the event loop, closes graphics, and terminates

### Requirement: Swap-to-disk game launch

On ENTER with a valid selection, the launcher SHALL: close graphics, print a loading
message, then invoke `ExecWithSwap` with the entry's `ExecPath` and `Args` and swap
file `C:\SWAP.TMP`. `ExecWithSwap` SHALL write the full program memory image (PSP
through `HeapPtr`) to the swap file, run the child via `Dos.Exec` with
`SwapVectors`, then restore the memory image from disk and delete the swap file.
After the child exits, the launcher MUST re-initialize graphics and resume the menu.
Launch SHALL NOT be attempted when no entries are loaded or the entry's `ExecPath`
is empty.

#### Scenario: Successful round-trip

- **WHEN** ENTER is pressed on an entry whose program exists
- **THEN** the launcher swaps out, the program runs, and on its exit the launcher
  restores itself, re-enters graphics mode, and redraws the menu

#### Scenario: Exec failure returns to menu

- **WHEN** `Dos.Exec` fails (e.g. program not found)
- **THEN** the launcher restores from the swap file, deletes it, re-initializes
  graphics, and resumes the menu without crashing

#### Scenario: Empty exec path is ignored

- **WHEN** ENTER is pressed on an entry with an empty `ExecPath`
- **THEN** nothing is launched and the menu remains displayed

### Requirement: Per-entry launch flags

The launcher SHALL honor the `Flags` field of each entry at launch time: when bit 0
(pause on exit) is set, the launcher MUST wait for a keypress after the child exits
before re-initializing graphics; when bit 1 (clear screen) is set, the launcher MUST
clear the text screen before printing the loading message.

#### Scenario: Pause on exit

- **WHEN** an entry with flag bit 0 set finishes running
- **THEN** the launcher waits in text mode for a keypress before returning to the
  graphical menu

#### Scenario: Clear screen before launch

- **WHEN** an entry with flag bit 1 set is launched
- **THEN** the text screen is cleared before the loading message is printed
