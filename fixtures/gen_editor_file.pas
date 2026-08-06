program gen_editor_file;

{ Standalone integration check for launcher-editor/verification (task 04).

  Not part of the fpcunit suite and not wired into the ztask test-file
  registry deliberately -- this is a one-off host tool that exercises the
  *real* compiled RiffWriter unit (the same one MainForm.pas calls into) to
  write a real LAUNCHER.DAT-shaped file to disk, then shells out to the
  actually-compiled snips/RiffDOSParser.pas binary (not a Python port) and
  compares what it reports against the editor's own in-memory document.

  This closes the "Parser agrees with editor" scenario from
  openspec/specs/launcher-editor/tasks/04-verification.md for real, rather
  than by code inspection: the same bytes RiffWriter would hand to
  SaveIO/TFileStream are the bytes RiffDOSParser reads back off disk.

  Usage: run from anywhere; writes ./LAUNCHER.DAT in the current directory
  (RiffDOSParser.pas hardcodes that relative filename) and prints a report.
  Caller is responsible for cleaning up LAUNCHER.DAT afterwards. }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, Classes, RiffLauncher, LauncherDoc, RiffWriter, RiffReader, IconConvert;

const
  ENTRY_COUNT = 5;

function MakeIconPixels(Seed: Integer): TIndexGrid;
var
  i: Integer;
begin
  for i := 0 to ICON_PIXEL_COUNT - 1 do
    Result[i] := (Seed + i) mod 16;
end;

function BuildEntry(Idx: Integer; WithIcon: Boolean): TAppEntry;
var
  Pixels: TIndexGrid;
begin
  Result.Title := Format('Game %d', [Idx]);
  Result.Desc := Format('Description for game %d', [Idx]);
  Result.ExecPath := Format('C:\GAMES\G%d\GAME.EXE', [Idx]);
  if Idx mod 2 = 0 then
    Result.Args := '-fast'
  else
    Result.Args := '';
  { exercise both launch flag bits across entries, as the round-trip
    scenario calls for a "specific order" with mixed flags/icons }
  Result.Flags := Idx and 3;
  Result.HasIcon := WithIcon;
  if WithIcon then
  begin
    Pixels := MakeIconPixels(Idx);
    Result.IconData := EncodeIconPCX(Pixels);
  end
  else
    SetLength(Result.IconData, 0);
end;

function EntriesEqual(const A, B: TAppEntry): Boolean;
begin
  Result := (A.Title = B.Title) and (A.Desc = B.Desc) and
            (A.ExecPath = B.ExecPath) and (A.Args = B.Args) and
            (A.Flags = B.Flags) and (A.HasIcon = B.HasIcon);
  if Result and A.HasIcon then
    Result := (Length(A.IconData) = Length(B.IconData)) and
              CompareMem(@A.IconData[0], @B.IconData[0], Length(A.IconData));
end;

var
  Doc: TLauncherDoc;
  Entries: TAppEntryArray;
  Reloaded: TAppEntryArray;
  i: Integer;
  ErrMsg: string;
  Bytes: TBytes;
  Stream: TFileStream;
  OutPath: string;
  AllMatch: Boolean;
begin
  Doc := TLauncherDoc.Create;
  try
    { Deliberately reordered / mixed: odd entries get icons, so the on-disk
      order is not simply "all icons first". }
    SetLength(Entries, ENTRY_COUNT);
    for i := 0 to ENTRY_COUNT - 1 do
      Entries[i] := BuildEntry(i + 1, (i mod 2) = 0);

    for i := 0 to ENTRY_COUNT - 1 do
      if not Doc.AddEntry(Entries[i], ErrMsg) then
      begin
        WriteLn('FAIL: AddEntry ', i, ': ', ErrMsg);
        Halt(1);
      end;

    WriteLn('Editor document built: ', Doc.Count, ' entries');

    { Write via the real RiffWriter unit, same call MainForm's save path
      uses (through SaveIO), to a real file on disk. }
    OutPath := 'LAUNCHER.DAT';
    if FileExists(OutPath) then
      DeleteFile(OutPath);

    Bytes := SerializeLauncherEntries(Doc.ToArray);
    Stream := TFileStream.Create(OutPath, fmCreate);
    try
      if Length(Bytes) > 0 then
        Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;

    WriteLn('Wrote ', OutPath, ' (', Length(Bytes), ' bytes) in cwd ', GetCurrentDir);
    WriteLn('EDITOR_ENTRY_COUNT=', Doc.Count);

    { Reload the real on-disk file through the real RiffReader unit (the
      same one MainForm's "Open" uses) and confirm it is byte-for-byte
      identical, field-by-field, to what was written -- this is the
      round-trip scenario exercised against a real file rather than an
      in-memory stream. }
    Reloaded := LoadRiffEntries(OutPath);
    WriteLn('RELOADED_ENTRY_COUNT=', Length(Reloaded));

    AllMatch := Length(Reloaded) = Doc.Count;
    if not AllMatch then
      WriteLn('FAIL: reloaded entry count mismatch')
    else
      for i := 0 to Doc.Count - 1 do
        if not EntriesEqual(Doc.GetEntry(i), Reloaded[i]) then
        begin
          AllMatch := False;
          WriteLn('FAIL: entry ', i, ' (', Doc.GetEntry(i).Title, ') mismatched after reload');
        end;

    if AllMatch then
      WriteLn('ROUND_TRIP=PASS (', Doc.Count, ' entries identical after real-file reload)')
    else
      WriteLn('ROUND_TRIP=FAIL');
  finally
    Doc.Free;
  end;

  if not AllMatch then
    Halt(1);
end.
