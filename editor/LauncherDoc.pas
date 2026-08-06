unit LauncherDoc;

{ Non-GUI document model for the launcher editor: an ordered list of app
  entries, a dirty flag, and add/edit/remove/reorder operations plus
  save-time validation. Mirrors the field limits and MAX_APPS cap baked
  into snips/RiffLauncher.pas's TAppInfo and snips/launcher.pas's
  MAX_APPS constant. No LCL dependency (design D1) so it is testable from
  a console fpcunit harness. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, RiffLauncher;

const
  MAX_APPS      = 50;
  MAX_TITLE_LEN = 40;
  MAX_DESC_LEN  = 70;
  MAX_EXEC_LEN  = 64;
  MAX_ARGS_LEN  = 64;

type
  { One app entry as held in memory. IconData holds the raw PCX chunk
    payload bytes (produced by IconConvert.EncodeIconPCX) when HasIcon is
    True; empty/ignored otherwise. }
  TAppEntry = record
    Title    : string;
    Desc     : string;
    ExecPath : string;
    Args     : string;
    Flags    : Word;
    HasIcon  : Boolean;
    IconData : TBytes;
  end;

  TAppEntryArray = array of TAppEntry;

  TValidationError = record
    EntryIndex : Integer; { 0-based index of the offending entry }
    Msg        : string;
  end;

  TValidationErrors = array of TValidationError;

  { Ordered document of app entries. }
  TLauncherDoc = class
  private
    FEntries: TAppEntryArray;
    FCount: Integer;
    FDirty: Boolean;
    procedure CheckIndex(Index: Integer);
  public
    constructor Create;

    function Count: Integer;
    function GetEntry(Index: Integer): TAppEntry;

    { Appends Entry. Returns False (with ErrMsg set) if the document is
      already at MAX_APPS. Does not itself enforce field-length limits --
      that is deferred to Validate, so free-form typing during edit isn't
      blocked mid-keystroke. }
    function AddEntry(const Entry: TAppEntry; out ErrMsg: string): Boolean;

    procedure SetEntry(Index: Integer; const Entry: TAppEntry);
    procedure RemoveEntry(Index: Integer);

    { Swaps Index with its upward/downward neighbor, preserving all field
      data (including icon) of both entries. Returns False if Index is
      already at the boundary (or out of range) and no move happened. }
    function MoveUp(Index: Integer): Boolean;
    function MoveDown(Index: Integer): Boolean;

    { Save-time validation: every entry must have a non-empty ExecPath and
      fields within TAppInfo's short-string capacities. Returns True iff
      Errors ends up empty. }
    function Validate(out Errors: TValidationErrors): Boolean;

    { Bulk-replaces the entry list (e.g. after a successful load) and
      clears the dirty flag. }
    procedure LoadEntries(const NewEntries: TAppEntryArray);

    { Snapshot of the current entries, e.g. for RiffWriter. }
    function ToArray: TAppEntryArray;

    procedure Clear;
    procedure MarkDirty;
    procedure MarkClean;

    property Dirty: Boolean read FDirty;
  end;

implementation

constructor TLauncherDoc.Create;
begin
  inherited Create;
  FCount := 0;
  FDirty := False;
  SetLength(FEntries, 0);
end;

procedure TLauncherDoc.CheckIndex(Index: Integer);
begin
  if (Index < 0) or (Index >= FCount) then
    raise ERangeError.CreateFmt('LauncherDoc: index %d out of range [0..%d)', [Index, FCount]);
end;

function TLauncherDoc.Count: Integer;
begin
  Result := FCount;
end;

function TLauncherDoc.GetEntry(Index: Integer): TAppEntry;
begin
  CheckIndex(Index);
  Result := FEntries[Index];
end;

function TLauncherDoc.AddEntry(const Entry: TAppEntry; out ErrMsg: string): Boolean;
begin
  ErrMsg := '';
  if FCount >= MAX_APPS then
  begin
    ErrMsg := Format('Cannot add entry: launcher limit of %d apps (MAX_APPS) reached', [MAX_APPS]);
    Result := False;
    Exit;
  end;

  if Length(FEntries) <= FCount then
    SetLength(FEntries, FCount + 1);
  FEntries[FCount] := Entry;
  Inc(FCount);
  FDirty := True;
  Result := True;
end;

procedure TLauncherDoc.SetEntry(Index: Integer; const Entry: TAppEntry);
begin
  CheckIndex(Index);
  FEntries[Index] := Entry;
  FDirty := True;
end;

procedure TLauncherDoc.RemoveEntry(Index: Integer);
var
  i: Integer;
begin
  CheckIndex(Index);
  for i := Index to FCount - 2 do
    FEntries[i] := FEntries[i + 1];
  Dec(FCount);
  FDirty := True;
end;

function TLauncherDoc.MoveUp(Index: Integer): Boolean;
var
  Tmp: TAppEntry;
begin
  CheckIndex(Index);
  if Index = 0 then
  begin
    Result := False;
    Exit;
  end;
  Tmp := FEntries[Index - 1];
  FEntries[Index - 1] := FEntries[Index];
  FEntries[Index] := Tmp;
  FDirty := True;
  Result := True;
end;

function TLauncherDoc.MoveDown(Index: Integer): Boolean;
var
  Tmp: TAppEntry;
begin
  CheckIndex(Index);
  if Index >= FCount - 1 then
  begin
    Result := False;
    Exit;
  end;
  Tmp := FEntries[Index + 1];
  FEntries[Index + 1] := FEntries[Index];
  FEntries[Index] := Tmp;
  FDirty := True;
  Result := True;
end;

function TLauncherDoc.Validate(out Errors: TValidationErrors): Boolean;
var
  i, n: Integer;

  procedure Add(Idx: Integer; const Msg: string);
  begin
    SetLength(Errors, n + 1);
    Errors[n].EntryIndex := Idx;
    Errors[n].Msg := Msg;
    Inc(n);
  end;

begin
  SetLength(Errors, 0);
  n := 0;
  for i := 0 to FCount - 1 do
  begin
    if Trim(FEntries[i].ExecPath) = '' then
      Add(i, 'ExecPath must not be empty');
    if Length(FEntries[i].Title) > MAX_TITLE_LEN then
      Add(i, Format('Title exceeds %d characters', [MAX_TITLE_LEN]));
    if Length(FEntries[i].Desc) > MAX_DESC_LEN then
      Add(i, Format('Desc exceeds %d characters', [MAX_DESC_LEN]));
    if Length(FEntries[i].ExecPath) > MAX_EXEC_LEN then
      Add(i, Format('ExecPath exceeds %d characters', [MAX_EXEC_LEN]));
    if Length(FEntries[i].Args) > MAX_ARGS_LEN then
      Add(i, Format('Args exceeds %d characters', [MAX_ARGS_LEN]));
  end;
  Result := (n = 0);
end;

procedure TLauncherDoc.LoadEntries(const NewEntries: TAppEntryArray);
var
  i: Integer;
begin
  FCount := Length(NewEntries);
  if FCount > MAX_APPS then
    FCount := MAX_APPS; { defensive clamp; RiffReader already enforces this }
  SetLength(FEntries, FCount);
  for i := 0 to FCount - 1 do
    FEntries[i] := NewEntries[i];
  FDirty := False;
end;

function TLauncherDoc.ToArray: TAppEntryArray;
var
  i: Integer;
begin
  SetLength(Result, FCount);
  for i := 0 to FCount - 1 do
    Result[i] := FEntries[i];
end;

procedure TLauncherDoc.Clear;
begin
  FCount := 0;
  SetLength(FEntries, 0);
  FDirty := True;
end;

procedure TLauncherDoc.MarkDirty;
begin
  FDirty := True;
end;

procedure TLauncherDoc.MarkClean;
begin
  FDirty := False;
end;

end.
