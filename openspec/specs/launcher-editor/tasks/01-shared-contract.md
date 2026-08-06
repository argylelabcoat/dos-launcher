# Task: Shared Contract

## Acceptance Criteria
Feature: RiffLauncher.pas as the single shared RCLF contract
  As both the DOS launcher and the desktop editor
  I want snips/RiffLauncher.pas to compile unmodified-in-layout under both toolchains
  So that record layouts are defined exactly once and cannot drift between reader and writer

  Scenario: Byte-level agreement
    Given the editor writes an INFO record for known field values using snips/RiffLauncher.pas types
    When the bytes are compared to the packed TAppInfo layout the DOS launcher reads
    Then they match: 244-byte payload, TP short strings, little-endian flags

  Scenario: DOS toolchain compiles unaffected
    Given any {$IFDEF FPC}-guarded addition made to snips/RiffLauncher.pas for desktop compilation
    When the unit is compiled with TP7 or FPC -Mtp targeting i8086-msdos
    Then compilation succeeds with no layout change to TAppInfo or any RIFF record

  Scenario: Desktop FPC compiles the shared unit
    Given snips/RiffLauncher.pas as used by the editor
    When it is compiled under desktop FPC/Lazarus
    Then it compiles successfully with short strings behaving correctly inside packed records

## Spec
Per design decision D2 (`openspec/changes/launcher-editor/design.md`) and the
`rclf-format-and-loader-hardening` change (this change's dependency — its
`rclf-container` spec is the frozen contract this unit implements):

- Add the editor's unit search path to `snips/` rather than copying
  `RiffLauncher.pas` — one source of truth for the binary format.
- If desktop FPC rejects the unit as-is (no mode directive at unit level), add at
  its top:
  ```pascal
  {$IFDEF FPC}
    {$MODE TP}
    {$PACKRECORDS 1}
  {$ENDIF}
  ```
  `{$PACKRECORDS 1}` already exists in the unit; `{$MODE TP}` added the same way
  is inert for TP7 and matches how `snips/launcher.pas` is already compiled under
  FPC.
- Do not touch record layouts. Confirm `TAppInfo` stays exactly 244 bytes
  (41 + 71 + 65 + 65 + 2, per the `rclf-container` INFO requirement) under both
  toolchains.
- Verify `snips/RiffLauncher.pas` compiles under both desktop FPC and the DOS
  target (`-Mtp` / TP7).

## Test Files
(none — a shared type-definition unit with no runtime logic to unit-test; verified
by dual-toolchain compile)

## Implementation Files
- snips/RiffLauncher.pas

## Test Command
fpc -Mobjfpc -Sh snips/RiffLauncher.pas && fpc -Mtp -Pi8086 -Tmsdos -Fusnips snips/RiffLauncher.pas

(The second half needs the i8086-msdos FPC target, not installed on this
Darwin-arm64 machine — cross-check on a machine with that target or via TP7 in
DOSBox. The first half, the desktop FPC compile, runs natively here.)
