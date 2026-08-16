unit TestYamlManifest;

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, YamlManifest;

type
  TTestYamlManifest = class(TTestCase)
  published
    procedure ParsesSingleEntryAllFields;
    procedure ParsesMultipleEntries;
    procedure IconFieldIsOptional;
    procedure BooleansDefaultFalseWhenOmitted;
    procedure QuotedValuesStripQuotes;
    procedure UnquotedValuesAreTrimmed;
    procedure BlankLinesAndCommentsAreIgnored;
    procedure MissingAppsKeyIsRejected;
    procedure UnknownKeyIsRejected;
    procedure InvalidBooleanValueIsRejected;
    procedure KeyOutsideAnEntryIsRejected;
    procedure EmptyAppsListYieldsZeroEntries;
  end;

implementation

function LinesOf(const S: array of string): TStrings;
var
  i: Integer;
begin
  Result := TStringList.Create;
  for i := Low(S) to High(S) do
    Result.Add(S[i]);
end;

procedure TTestYamlManifest.ParsesSingleEntryAllFields;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
  Ok: Boolean;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Game 1"',
    '    desc: "Description for game 1"',
    '    exec: "C:\GAMES\G1\GAME.EXE"',
    '    args: "-fast"',
    '    pause_on_exit: true',
    '    clear_screen: false',
    '    icon: "icons/game1.png"'
  ]);
  try
    Ok := ParseManifest(Lines, Entries, ErrMsg);
    AssertTrue('parse should succeed: ' + ErrMsg, Ok);
    AssertEquals(1, Length(Entries));
    AssertEquals('Game 1', Entries[0].Title);
    AssertEquals('Description for game 1', Entries[0].Desc);
    AssertEquals('C:\GAMES\G1\GAME.EXE', Entries[0].ExecPath);
    AssertEquals('-fast', Entries[0].Args);
    AssertTrue(Entries[0].PauseOnExit);
    AssertFalse(Entries[0].ClearScreen);
    AssertEquals('icons/game1.png', Entries[0].IconPath);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.ParsesMultipleEntries;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Game 1"',
    '    exec: "C:\G1.EXE"',
    '  - title: "Game 2"',
    '    exec: "C:\G2.EXE"',
    '  - title: "Game 3"',
    '    exec: "C:\G3.EXE"'
  ]);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals(3, Length(Entries));
    AssertEquals('Game 1', Entries[0].Title);
    AssertEquals('Game 2', Entries[1].Title);
    AssertEquals('Game 3', Entries[2].Title);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.IconFieldIsOptional;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "No Icon Game"',
    '    exec: "C:\G.EXE"'
  ]);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals(1, Length(Entries));
    AssertEquals('', Entries[0].IconPath);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.BooleansDefaultFalseWhenOmitted;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Game"',
    '    exec: "C:\G.EXE"'
  ]);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertFalse(Entries[0].PauseOnExit);
    AssertFalse(Entries[0].ClearScreen);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.QuotedValuesStripQuotes;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Quoted Title"',
    '    exec: "C:\G.EXE"'
  ]);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals('Quoted Title', Entries[0].Title);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.UnquotedValuesAreTrimmed;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: Unquoted Title',
    '    exec: C:\G.EXE'
  ]);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals('Unquoted Title', Entries[0].Title);
    AssertEquals('C:\G.EXE', Entries[0].ExecPath);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.BlankLinesAndCommentsAreIgnored;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    '# a manifest',
    'apps:',
    '',
    '  # first game',
    '  - title: "Game 1"',
    '    exec: "C:\G1.EXE"',
    ''
  ]);
  try
    AssertTrue('parse should succeed: ' + ErrMsg, ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals(1, Length(Entries));
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.MissingAppsKeyIsRejected;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    '  - title: "Game 1"',
    '    exec: "C:\G1.EXE"'
  ]);
  try
    AssertFalse(ParseManifest(Lines, Entries, ErrMsg));
    AssertTrue('error should mention apps', Pos('apps', ErrMsg) > 0);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.UnknownKeyIsRejected;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Game 1"',
    '    exec: "C:\G1.EXE"',
    '    titel: "typo"'
  ]);
  try
    AssertFalse(ParseManifest(Lines, Entries, ErrMsg));
    AssertTrue('error should mention the bad key', Pos('titel', ErrMsg) > 0);
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.InvalidBooleanValueIsRejected;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '  - title: "Game 1"',
    '    exec: "C:\G1.EXE"',
    '    pause_on_exit: yes'
  ]);
  try
    AssertFalse(ParseManifest(Lines, Entries, ErrMsg));
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.KeyOutsideAnEntryIsRejected;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf([
    'apps:',
    '    exec: "C:\G1.EXE"'
  ]);
  try
    AssertFalse(ParseManifest(Lines, Entries, ErrMsg));
  finally
    Lines.Free;
  end;
end;

procedure TTestYamlManifest.EmptyAppsListYieldsZeroEntries;
var
  Lines: TStrings;
  Entries: TManifestEntries;
  ErrMsg: string;
begin
  Lines := LinesOf(['apps:']);
  try
    AssertTrue(ParseManifest(Lines, Entries, ErrMsg));
    AssertEquals(0, Length(Entries));
  finally
    Lines.Free;
  end;
end;

initialization
  RegisterTest(TTestYamlManifest);
end.
