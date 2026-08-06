unit TestLauncherDoc;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, LauncherDoc, RiffWriter, RiffReader, SaveIO;

type
  TTestLauncherDoc = class(TTestCase)
  private
    function MakeEntry(const Title, ExecPath: string): TAppEntry;
  published
    procedure EntryLimitEnforced;
    procedure ReorderPreservesDataAndIcon;
    procedure EmptyExecPathBlocksValidation;
    procedure ValidateFlagsTooLongFields;
    procedure AddEntrySetsDirty;
    procedure RemoveEntryShiftsIndices;
    procedure ClearIconRemovesIconReference;
    procedure AtomicSavePreservesFileOnFailure;
    procedure AtomicSaveRoundTripSelfCheck;
  end;

implementation

function TTestLauncherDoc.MakeEntry(const Title, ExecPath: string): TAppEntry;
begin
  Result.Title := Title;
  Result.Desc := 'desc';
  Result.ExecPath := ExecPath;
  Result.Args := '';
  Result.Flags := 0;
  Result.HasIcon := False;
  SetLength(Result.IconData, 0);
end;

procedure TTestLauncherDoc.EntryLimitEnforced;
var
  Doc: TLauncherDoc;
  i: Integer;
  ErrMsg: string;
  Ok: Boolean;
begin
  Doc := TLauncherDoc.Create;
  try
    for i := 1 to MAX_APPS do
      AssertTrue('adding entry ' + IntToStr(i) + ' should succeed',
        Doc.AddEntry(MakeEntry('T' + IntToStr(i), 'C:\G' + IntToStr(i) + '.EXE'), ErrMsg));
    AssertEquals(MAX_APPS, Doc.Count);

    Ok := Doc.AddEntry(MakeEntry('Overflow', 'C:\X.EXE'), ErrMsg);
    AssertFalse('51st entry must be refused', Ok);
    AssertTrue('error message should mention the MAX_APPS limit',
      Pos(IntToStr(MAX_APPS), ErrMsg) > 0);
    AssertEquals(MAX_APPS, Doc.Count);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.ReorderPreservesDataAndIcon;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  E0, E1: TAppEntry;
  Moved: Boolean;
begin
  Doc := TLauncherDoc.Create;
  try
    E0 := MakeEntry('First', 'C:\A.EXE');
    E1 := MakeEntry('Second', 'C:\B.EXE');
    E1.HasIcon := True;
    SetLength(E1.IconData, 3);
    E1.IconData[0] := 1; E1.IconData[1] := 2; E1.IconData[2] := 3;

    Doc.AddEntry(E0, ErrMsg);
    Doc.AddEntry(E1, ErrMsg);

    Moved := Doc.MoveUp(1);
    AssertTrue('MoveUp(1) should succeed', Moved);
    AssertEquals('Second', Doc.GetEntry(0).Title);
    AssertEquals('First', Doc.GetEntry(1).Title);
    AssertTrue('icon reference should follow its entry', Doc.GetEntry(0).HasIcon);
    AssertEquals(3, Length(Doc.GetEntry(0).IconData));
    AssertEquals(1, Doc.GetEntry(0).IconData[0]);

    Moved := Doc.MoveUp(0);
    AssertFalse('entry already at top should refuse to move further up', Moved);

    Moved := Doc.MoveDown(0);
    AssertTrue(Moved);
    AssertEquals('First', Doc.GetEntry(0).Title);
    AssertEquals('Second', Doc.GetEntry(1).Title);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.EmptyExecPathBlocksValidation;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  Errors: TValidationErrors;
  Ok: Boolean;
begin
  Doc := TLauncherDoc.Create;
  try
    Doc.AddEntry(MakeEntry('Good', 'C:\GOOD.EXE'), ErrMsg);
    Doc.AddEntry(MakeEntry('Bad', ''), ErrMsg);

    Ok := Doc.Validate(Errors);
    AssertFalse('validation must fail with an empty ExecPath present', Ok);
    AssertTrue('at least one error reported', Length(Errors) > 0);
    AssertEquals('offending entry index should be the second entry (index 1)', 1, Errors[0].EntryIndex);
    AssertTrue('message should reference ExecPath', Pos('ExecPath', Errors[0].Msg) > 0);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.ValidateFlagsTooLongFields;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  Errors: TValidationErrors;
  E: TAppEntry;
begin
  Doc := TLauncherDoc.Create;
  try
    E := MakeEntry(StringOfChar('T', 41), 'C:\OK.EXE');
    Doc.AddEntry(E, ErrMsg);
    AssertFalse(Doc.Validate(Errors));
    AssertTrue(Length(Errors) > 0);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.AddEntrySetsDirty;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
begin
  Doc := TLauncherDoc.Create;
  try
    AssertFalse(Doc.Dirty);
    Doc.AddEntry(MakeEntry('A', 'C:\A.EXE'), ErrMsg);
    AssertTrue(Doc.Dirty);
    Doc.MarkClean;
    AssertFalse(Doc.Dirty);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.RemoveEntryShiftsIndices;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
begin
  Doc := TLauncherDoc.Create;
  try
    Doc.AddEntry(MakeEntry('A', 'C:\A.EXE'), ErrMsg);
    Doc.AddEntry(MakeEntry('B', 'C:\B.EXE'), ErrMsg);
    Doc.AddEntry(MakeEntry('C', 'C:\C.EXE'), ErrMsg);
    Doc.RemoveEntry(1);
    AssertEquals(2, Doc.Count);
    AssertEquals('A', Doc.GetEntry(0).Title);
    AssertEquals('C', Doc.GetEntry(1).Title);
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.ClearIconRemovesIconReference;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  E: TAppEntry;
  Bytes: TBytes;
  s: string;
  i: Integer;
begin
  Doc := TLauncherDoc.Create;
  try
    E := MakeEntry('Iconned', 'C:\I.EXE');
    E.HasIcon := True;
    SetLength(E.IconData, 5);
    Doc.AddEntry(E, ErrMsg);

    { Clear the icon on entry 0 -- LauncherDoc/IconConvert record no icon
      for it, and RiffWriter must then emit no ICON chunk for that entry. }
    E := Doc.GetEntry(0);
    E.HasIcon := False;
    SetLength(E.IconData, 0);
    Doc.SetEntry(0, E);

    AssertFalse('icon flag cleared on the document entry', Doc.GetEntry(0).HasIcon);

    Bytes := SerializeLauncherEntries(Doc.ToArray);
    SetLength(s, Length(Bytes));
    for i := 0 to High(Bytes) do
      s[i + 1] := Chr(Bytes[i]);
    AssertEquals('no ICON chunk should be emitted once the icon is cleared', 0, Pos('ICON', s));
  finally
    Doc.Free;
  end;
end;

procedure TTestLauncherDoc.AtomicSavePreservesFileOnFailure;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  TargetFile, SentinelContent, ContentAfter: string;
  FS: TFileStream;
  Ok: Boolean;
  Buf: array of Byte;
begin
  TargetFile := GetTempDir(False) + 'lted_atomic_fail_' + IntToStr(Random(1000000)) + '.dat';
  SentinelContent := 'PRE-EXISTING-CONTENT';

  FS := TFileStream.Create(TargetFile, fmCreate);
  try
    FS.WriteBuffer(SentinelContent[1], Length(SentinelContent));
  finally
    FS.Free;
  end;

  Doc := TLauncherDoc.Create;
  try
    { An entry with an empty ExecPath fails Validate, so AtomicSaveDocument
      must refuse before ever touching the target file. }
    Doc.AddEntry(MakeEntry('Bad', ''), ErrMsg);

    Ok := AtomicSaveDocument(Doc, TargetFile, ErrMsg);
    AssertFalse('save should be refused for an invalid document', Ok);
    AssertTrue(ErrMsg <> '');

    FS := TFileStream.Create(TargetFile, fmOpenRead);
    try
      SetLength(Buf, FS.Size);
      if FS.Size > 0 then FS.ReadBuffer(Buf[0], FS.Size);
    finally
      FS.Free;
    end;
    SetLength(ContentAfter, Length(Buf));
    if Length(Buf) > 0 then
      Move(Buf[0], ContentAfter[1], Length(Buf));
    AssertEquals('pre-existing target file content must be untouched',
      SentinelContent, ContentAfter);

    AssertFalse('temp file must not be left behind', FileExists(TargetFile + '.tmp'));
  finally
    Doc.Free;
    if FileExists(TargetFile) then DeleteFile(TargetFile);
    if FileExists(TargetFile + '.tmp') then DeleteFile(TargetFile + '.tmp');
  end;
end;

procedure TTestLauncherDoc.AtomicSaveRoundTripSelfCheck;
var
  Doc: TLauncherDoc;
  ErrMsg: string;
  TargetFile: string;
  Ok: Boolean;
  Reloaded: TAppEntryArray;
begin
  TargetFile := GetTempDir(False) + 'lted_atomic_ok_' + IntToStr(Random(1000000)) + '.dat';

  Doc := TLauncherDoc.Create;
  try
    Doc.AddEntry(MakeEntry('Alpha', 'C:\ALPHA.EXE'), ErrMsg);
    Doc.AddEntry(MakeEntry('Beta', 'C:\BETA.EXE'), ErrMsg);

    Ok := AtomicSaveDocument(Doc, TargetFile, ErrMsg);
    AssertTrue('save should succeed: ' + ErrMsg, Ok);
    AssertFalse('dirty flag should be cleared after a successful save', Doc.Dirty);
    AssertTrue('target file should now exist', FileExists(TargetFile));
    AssertFalse('temp file should be gone after a successful rename', FileExists(TargetFile + '.tmp'));

    Reloaded := LoadRiffEntries(TargetFile);
    AssertEquals(2, Length(Reloaded));
    AssertEquals('Alpha', Reloaded[0].Title);
    AssertEquals('Beta', Reloaded[1].Title);
  finally
    Doc.Free;
    if FileExists(TargetFile) then DeleteFile(TargetFile);
    if FileExists(TargetFile + '.tmp') then DeleteFile(TargetFile + '.tmp');
  end;
end;

initialization
  RegisterTest(TTestLauncherDoc);
end.
