# Task: GUI

## Depends On
- format-units

## Acceptance Criteria
Feature: Lazarus editor GUI for LAUNCHER.DAT
  As a user authoring launcher data files
  I want a desktop form to manage entries, edit fields, and preview icons
  So that I can build a spec-compliant LAUNCHER.DAT without hand-editing bytes

  Scenario: Overlong title is blocked
    Given the Title edit field bound to an entry
    When the user types a 41st character
    Then the character is rejected and the field keeps its 40 characters

  Scenario: Entry list shows title and icon
    Given entries with and without icons in the document model
    When the main form's entry list renders
    Then each row shows the entry's title and, if present, its icon thumbnail

  Scenario: Reorder via toolbar
    Given an entry selected in the list
    When the user clicks Up or Down
    Then LauncherDoc's reorder operation runs and the list view reflects the new order

  Scenario: Entry limit message shown in the GUI
    Given the list already has 50 entries
    When the user clicks Add
    Then the GUI surfaces LauncherDoc's MAX_APPS refusal as a user-facing message and adds no entry

  Scenario: Icon preview matches conversion output
    Given an icon has been imported via the toolbar
    When the preview panel renders
    Then it shows the same quantized 32x32 pixels IconConvert produced, scaled up for visibility

  Scenario: Save blocked on validation errors
    Given at least one entry has an empty exec path
    When the user attempts to save
    Then the save is blocked, the offending entry is highlighted in the list, and an explanation is shown

  Scenario: Default save file name is DOS-friendly
    Given a new, unsaved document
    When the save dialog opens
    Then the default file name is LAUNCHER.DAT (8.3-safe)

## Spec
Per `openspec/changes/launcher-editor/tasks.md` group 3 and design decision D1
(`openspec/changes/launcher-editor/design.md`):

- Scaffold `editor/LauncherEditor.lpi`/`.lpr` and a main form unit with: an entry
  list (title + icon thumbnail), an edit panel (Title/Desc/ExecPath/Args text
  fields with `MaxLength` 40/70/64/64, two flag checkboxes for pause-on-exit and
  clear-screen), and a menu/toolbar (New/Open/Save/Add/Remove/Up/Down/Import
  icon/Clear icon).
- Wire the entry list to `LauncherDoc` (from the `02-format-units` task),
  including reorder operations and the 50-entry limit message surfaced from
  `LauncherDoc`'s refusal.
- Icon preview panel renders `IconConvert`'s quantized 32x32 result scaled up —
  exactly the pixels the launcher will draw, per the editor spec's
  "Icon preview matches launcher output" requirement, satisfied by construction
  since the preview uses the same conversion output that gets written.
- Save-flow integration: block save when `LauncherDoc`'s save-time validation
  fails, highlight the offending entry, and show the explanation. Default the
  save dialog's file name to `LAUNCHER.DAT` (8.3-safe) per the design's open
  question, resolved yes for DOS friendliness.
- GUI code must not touch RCLF byte-format details directly — it goes through
  `LauncherDoc`/`RiffWriter`/`RiffReader`/`IconConvert` only (D1's separation of
  concerns), keeping those units testable independent of the LCL.

## Test Files
(none — LCL-dependent GUI code has no fpcunit harness in this project; verified by
lazbuild compile check and the `04-verification` task's manual/DOSBox testing)

## Implementation Files
- editor/LauncherEditor.lpi
- editor/LauncherEditor.lpr
- editor/MainForm.pas (or equivalent main-form unit name chosen at scaffold time)

## Test Command
/Volumes/ExternalRAID/Users/matthew/fpcupdeluxe/lazarus/lazbuild editor/LauncherEditor.lpi

(This machine has Lazarus/lazbuild installed at that path but the `editor/`
project does not exist yet — this command becomes runnable once this task
scaffolds `LauncherEditor.lpi`. The GUI's visual/interaction scenarios above
still require manual verification by running the built application; a clean
lazbuild compile alone does not confirm field limits, highlighting, or dialog
defaults behave correctly.)
