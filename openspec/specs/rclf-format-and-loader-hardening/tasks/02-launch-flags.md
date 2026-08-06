# Task: Launch Flags

## Depends On
- loader-rewrite

## Acceptance Criteria
Feature: Per-entry launch flags
  As the DOS launcher
  I want to honor each entry's Flags bits around program launch
  So that authors can opt individual entries into pause-on-exit and clear-screen behavior

  Scenario: Pause on exit
    Given an entry with flag bit 0 (pause on exit) set, loaded with its Flags field retained by the 01-loader-rewrite task
    When the entry's program finishes running
    Then the launcher waits in text mode for a keypress before returning to the graphical menu

  Scenario: Clear screen before launch
    Given an entry with flag bit 1 (clear screen) set
    When the entry is launched
    Then the text screen is cleared before the loading message is printed

  Scenario: Default flags preserve minimal behavior
    Given an entry whose Flags field is 0
    When the entry is launched and exits
    Then the screen is not cleared before the loading message and the launcher does not pause for a keypress after exit

## Spec
Per design decision D5 (`openspec/changes/rclf-format-and-loader-hardening/design.md`),
in `RunLauncher`'s ENTER branch of `snips/launcher.pas`:

- Bit 1 (clear screen, `Flags and 2 <> 0`): make the pre-launch `ClrScr` conditional
  on this bit instead of unconditional as it is today.
- Bit 0 (pause on exit, `Flags and 1 <> 0`): after `ExecWithSwap` returns, print a
  prompt and `ReadKey` in text mode before calling `InitGraph` to resume the menu.
- Default flags = 0 keeps current behavior except that the unconditional clear
  becomes opt-in — accepted per spec since `Flags` was always defined in
  `TAppInfo`/`TAppEntry` but previously ignored.
- Depends on `TAppEntry.Flags` being populated by the `01-loader-rewrite` task.

## Test Files
(none — DOS-target unit, no automated unit test harness; verified by compile check
and the `03-verification` task's DOSBox testing)

## Implementation Files
- snips/launcher.pas

## Test Command
See `03-verification`'s Test Command — an FPC i8086-msdos cross-compiler now
exists at `dosbox-verify/fpc-i8086-install/` and produces a real, runnable DOS
`.exe`. The pause-on-exit and clear-screen behavioral scenarios above still
need manual DOSBox-X verification (interactive, not headlessly scriptable) —
see `03-verification`.
