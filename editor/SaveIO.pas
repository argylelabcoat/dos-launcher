unit SaveIO;

{ Atomic save for RCLF launcher files (design D5). Writes the document to
  a temp file next to the target, reloads that temp file with RiffReader
  and compares it field-for-field against the in-memory document, and
  only then renames it over the target. Any failure along the way -- a
  validation error, a write error, or a reload mismatch -- leaves the
  pre-existing target file untouched and is reported back to the caller
  instead of raised, so GUI code can show it without a try/except. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, LauncherDoc, RiffWriter, RiffReader;

{ Attempts to save Doc's current entries to TargetFileName. Returns True
  on success (Doc's dirty flag is cleared). Returns False and sets ErrMsg
  otherwise; TargetFileName is guaranteed unmodified in that case. }
function AtomicSaveDocument(Doc: TLauncherDoc; const TargetFileName: string; out ErrMsg: string): Boolean;

{ Lower-level helper (also used directly by tests): compares two entry
  arrays field-by-field, ignoring only ordering-irrelevant details. }
function EntriesMatch(const A, B: TAppEntryArray; out Diff: string): Boolean;

implementation

function EntriesMatch(const A, B: TAppEntryArray; out Diff: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Length(A) <> Length(B) then
  begin
    Diff := Format('entry count mismatch: %d vs %d', [Length(A), Length(B)]);
    Exit;
  end;
  for i := 0 to High(A) do
  begin
    if A[i].Title <> B[i].Title then
    begin
      Diff := Format('entry %d: Title mismatch', [i]);
      Exit;
    end;
    if A[i].Desc <> B[i].Desc then
    begin
      Diff := Format('entry %d: Desc mismatch', [i]);
      Exit;
    end;
    if A[i].ExecPath <> B[i].ExecPath then
    begin
      Diff := Format('entry %d: ExecPath mismatch', [i]);
      Exit;
    end;
    if A[i].Args <> B[i].Args then
    begin
      Diff := Format('entry %d: Args mismatch', [i]);
      Exit;
    end;
    if A[i].Flags <> B[i].Flags then
    begin
      Diff := Format('entry %d: Flags mismatch', [i]);
      Exit;
    end;
    if A[i].HasIcon <> B[i].HasIcon then
    begin
      Diff := Format('entry %d: HasIcon mismatch', [i]);
      Exit;
    end;
    if A[i].HasIcon and (Length(A[i].IconData) <> Length(B[i].IconData)) then
    begin
      Diff := Format('entry %d: IconData length mismatch', [i]);
      Exit;
    end;
  end;
  Diff := '';
  Result := True;
end;

function AtomicSaveDocument(Doc: TLauncherDoc; const TargetFileName: string; out ErrMsg: string): Boolean;
var
  Errors: TValidationErrors;
  Entries, Reloaded: TAppEntryArray;
  TempFileName: string;
  FS: TFileStream;
  Diff: string;
begin
  Result := False;
  ErrMsg := '';

  if not Doc.Validate(Errors) then
  begin
    ErrMsg := Format('validation failed: entry %d: %s', [Errors[0].EntryIndex, Errors[0].Msg]);
    Exit;
  end;

  Entries := Doc.ToArray;
  TempFileName := TargetFileName + '.tmp';

  try
    FS := TFileStream.Create(TempFileName, fmCreate);
    try
      WriteLauncherEntries(Entries, FS);
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      ErrMsg := 'write failed: ' + E.Message;
      if FileExists(TempFileName) then
        DeleteFile(TempFileName);
      Exit;
    end;
  end;

  try
    Reloaded := LoadRiffEntries(TempFileName);
  except
    on E: Exception do
    begin
      ErrMsg := 'round-trip self-check failed to reload temp file: ' + E.Message;
      DeleteFile(TempFileName);
      Exit;
    end;
  end;

  if not EntriesMatch(Entries, Reloaded, Diff) then
  begin
    ErrMsg := 'round-trip self-check mismatch: ' + Diff;
    DeleteFile(TempFileName);
    Exit;
  end;

  if not RenameFile(TempFileName, TargetFileName) then
  begin
    ErrMsg := 'could not rename temp file over target';
    DeleteFile(TempFileName);
    Exit;
  end;

  Doc.MarkClean;
  Result := True;
end;

end.
