unit YamlManifest;

{ Parses the CLI's app-list manifest format. This is deliberately NOT a
  general-purpose YAML parser -- it accepts exactly one fixed shape:

    apps:
      - title: "Game 1"
        desc: "Description for game 1"
        exec: "C:\GAMES\G1\GAME.EXE"
        args: "-fast"
        pause_on_exit: true
        clear_screen: false
        icon: "icons/game1.png"
      - title: "Game 2"
        ...

  Rules: a top-level "apps:" line starts the list; each entry begins with
  a line indented exactly 2 spaces starting "- ", whose first key:value
  pair follows the dash on that same line; subsequent keys for that entry
  are indented exactly 4 spaces. Values are either double-quoted (quotes
  stripped, no escape processing) or bare (trimmed). Blank lines and
  lines whose first non-blank character is '#' are ignored anywhere.
  Unknown keys and malformed booleans are rejected with a line-numbered
  error rather than silently ignored, since a typo'd key silently
  dropping a field would be a much worse authoring experience than a
  parse error -- content-level validation (non-empty exec path, field
  length limits) is deliberately NOT done here; that stays LauncherDoc's
  job, same separation of concerns as its own AddEntry/Validate split. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TManifestEntry = record
    Title       : string;
    Desc        : string;
    ExecPath    : string;
    Args        : string;
    PauseOnExit : Boolean;
    ClearScreen : Boolean;
    IconPath    : string;
  end;

  TManifestEntries = array of TManifestEntry;

{ Parses Lines into Entries. Returns False (with ErrMsg set, usually
  including a 1-based line number) on any structural problem: missing
  "apps:" root key, a key appearing outside an entry, an unrecognized
  key, or a non-true/false value for a boolean field. }
function ParseManifest(Lines: TStrings; out Entries: TManifestEntries; out ErrMsg: string): Boolean;

implementation

function IsBlankOrComment(const Line: string): Boolean;
var
  T: string;
begin
  T := Trim(Line);
  Result := (T = '') or (T[1] = '#');
end;

{ Splits "key: value" into Key/Value, trimming both and stripping a
  matched pair of double quotes from Value. Returns False if there's no
  colon. }
function SplitKeyValue(const S: string; out Key, Value: string): Boolean;
var
  ColonPos: Integer;
begin
  ColonPos := Pos(':', S);
  if ColonPos = 0 then
  begin
    Result := False;
    Exit;
  end;
  Key := Trim(Copy(S, 1, ColonPos - 1));
  Value := Trim(Copy(S, ColonPos + 1, Length(S)));
  if (Length(Value) >= 2) and (Value[1] = '"') and (Value[Length(Value)] = '"') then
    Value := Copy(Value, 2, Length(Value) - 2);
  Result := True;
end;

function ParseBool(const S: string; out BoolVal: Boolean): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  Result := True;
  if L = 'true' then
    BoolVal := True
  else if L = 'false' then
    BoolVal := False
  else
    Result := False;
end;

{ Applies one Key/Value pair to Entry. Returns False (ErrMsg set) for an
  unrecognized key or an invalid boolean. }
function ApplyField(var Entry: TManifestEntry; const Key, Value: string; out ErrMsg: string): Boolean;
var
  BoolVal: Boolean;
begin
  Result := True;
  ErrMsg := '';
  if Key = 'title' then
    Entry.Title := Value
  else if Key = 'desc' then
    Entry.Desc := Value
  else if Key = 'exec' then
    Entry.ExecPath := Value
  else if Key = 'args' then
    Entry.Args := Value
  else if Key = 'icon' then
    Entry.IconPath := Value
  else if Key = 'pause_on_exit' then
  begin
    if not ParseBool(Value, BoolVal) then
    begin
      ErrMsg := Format('pause_on_exit must be true or false, got "%s"', [Value]);
      Result := False;
      Exit;
    end;
    Entry.PauseOnExit := BoolVal;
  end
  else if Key = 'clear_screen' then
  begin
    if not ParseBool(Value, BoolVal) then
    begin
      ErrMsg := Format('clear_screen must be true or false, got "%s"', [Value]);
      Result := False;
      Exit;
    end;
    Entry.ClearScreen := BoolVal;
  end
  else
  begin
    ErrMsg := Format('unknown key "%s"', [Key]);
    Result := False;
  end;
end;

function ParseManifest(Lines: TStrings; out Entries: TManifestEntries; out ErrMsg: string): Boolean;
const
  ENTRY_MARKER = '  - ';   { 2-space indent + dash + space }
  FIELD_INDENT = '    ';   { 4-space indent for subsequent keys }
var
  i: Integer;
  Line, Rest, Key, Value: string;
  SeenAppsKey: Boolean;
  HaveCurrentEntry: Boolean;
  Current: TManifestEntry;
  Count: Integer;

  procedure InitEntry(out E: TManifestEntry);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Title := '';
    E.Desc := '';
    E.ExecPath := '';
    E.Args := '';
    E.IconPath := '';
    E.PauseOnExit := False;
    E.ClearScreen := False;
  end;

  procedure CommitCurrentEntry;
  begin
    if not HaveCurrentEntry then Exit;
    if Count >= Length(Entries) then
      SetLength(Entries, Count + 4);
    Entries[Count] := Current;
    Inc(Count);
    HaveCurrentEntry := False;
  end;

begin
  Result := False;
  ErrMsg := '';
  SetLength(Entries, 0);
  Count := 0;
  SeenAppsKey := False;
  HaveCurrentEntry := False;

  for i := 0 to Lines.Count - 1 do
  begin
    Line := Lines[i];
    if IsBlankOrComment(Line) then Continue;

    if not SeenAppsKey then
    begin
      if Trim(Line) = 'apps:' then
      begin
        SeenAppsKey := True;
        Continue;
      end;
      ErrMsg := Format('line %d: expected top-level "apps:" key, got "%s"', [i + 1, Line]);
      Exit;
    end;

    if (Length(Line) >= Length(ENTRY_MARKER)) and (Copy(Line, 1, Length(ENTRY_MARKER)) = ENTRY_MARKER) then
    begin
      CommitCurrentEntry;
      InitEntry(Current);
      HaveCurrentEntry := True;
      Rest := Copy(Line, Length(ENTRY_MARKER) + 1, Length(Line));
      if not SplitKeyValue(Rest, Key, Value) then
      begin
        ErrMsg := Format('line %d: expected "key: value" after "- ", got "%s"', [i + 1, Rest]);
        Exit;
      end;
      if not ApplyField(Current, Key, Value, ErrMsg) then
      begin
        ErrMsg := Format('line %d: %s', [i + 1, ErrMsg]);
        Exit;
      end;
      Continue;
    end;

    if (Length(Line) >= Length(FIELD_INDENT)) and (Copy(Line, 1, Length(FIELD_INDENT)) = FIELD_INDENT)
       and (Length(Trim(Line)) > 0) and (Line[Length(FIELD_INDENT) + 1] <> ' ') then
    begin
      if not HaveCurrentEntry then
      begin
        ErrMsg := Format('line %d: field outside of an "apps:" entry: "%s"', [i + 1, Line]);
        Exit;
      end;
      Rest := Copy(Line, Length(FIELD_INDENT) + 1, Length(Line));
      if not SplitKeyValue(Rest, Key, Value) then
      begin
        ErrMsg := Format('line %d: expected "key: value", got "%s"', [i + 1, Rest]);
        Exit;
      end;
      if not ApplyField(Current, Key, Value, ErrMsg) then
      begin
        ErrMsg := Format('line %d: %s', [i + 1, ErrMsg]);
        Exit;
      end;
      Continue;
    end;

    ErrMsg := Format('line %d: unrecognized line (bad indentation?): "%s"', [i + 1, Line]);
    Exit;
  end;

  CommitCurrentEntry;
  SetLength(Entries, Count);
  Result := True;
end;

end.
