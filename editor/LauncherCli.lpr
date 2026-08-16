program LauncherCli;

{ CLI counterpart to the LauncherEditor GUI: builds a LAUNCHER.DAT from a
  YAML manifest (see YamlManifest.pas for the accepted subset) plus PNG
  icon files, reusing the same non-GUI format units the editor uses
  (LauncherDoc, RiffWriter, IconConvert, SaveIO) so the two front-ends
  can never disagree about the on-disk format.

  Usage: launchercli <manifest.yaml> -o <LAUNCHER.DAT> }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, Classes,
  LauncherDoc, YamlManifest, PngLoader, IconConvert, SaveIO;

const
  FLAG_PAUSE_ON_EXIT = 1;
  FLAG_CLEAR_SCREEN  = 2;

procedure PrintUsage;
begin
  WriteLn(StdErr, 'Usage: launchercli <manifest.yaml> -o <output.dat>');
end;

function IsAbsolutePath(const P: string): Boolean;
begin
  Result := (Length(P) > 0) and (P[1] in ['/', '\'])
    or ((Length(P) >= 2) and (P[2] = ':')); { e.g. "C:\..." }
end;

{ Resolves IconPath against the manifest file's own directory when it's
  relative, so icon paths in the YAML are written relative to the
  manifest rather than to wherever the CLI happens to be invoked from. }
function ResolveIconPath(const ManifestDir, IconPath: string): string;
begin
  if (IconPath = '') or IsAbsolutePath(IconPath) then
    Result := IconPath
  else
    Result := IncludeTrailingPathDelimiter(ManifestDir) + IconPath;
end;

var
  ManifestPath, OutputPath, ManifestDir: string;
  i: Integer;
  Arg: string;
  Lines: TStringList;
  ManifestEntries: TManifestEntries;
  Doc: TLauncherDoc;
  DocEntry: LauncherDoc.TAppEntry;
  Errors: TValidationErrors;
  Pixels: TIndexGrid;
  ErrMsg: string;
  ResolvedIconPath: string;
  ExitOk: Boolean;

begin
  ManifestPath := '';
  OutputPath := '';

  i := 1;
  while i <= ParamCount do
  begin
    Arg := ParamStr(i);
    if Arg = '-o' then
    begin
      if i = ParamCount then
      begin
        WriteLn(StdErr, 'error: -o requires a filename argument');
        PrintUsage;
        Halt(1);
      end;
      Inc(i);
      OutputPath := ParamStr(i);
    end
    else if ManifestPath = '' then
      ManifestPath := Arg
    else
    begin
      WriteLn(StdErr, 'error: unexpected argument "' + Arg + '"');
      PrintUsage;
      Halt(1);
    end;
    Inc(i);
  end;

  if (ManifestPath = '') or (OutputPath = '') then
  begin
    PrintUsage;
    Halt(1);
  end;

  if not FileExists(ManifestPath) then
  begin
    WriteLn(StdErr, 'error: manifest file not found: ' + ManifestPath);
    Halt(1);
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(ManifestPath);
    if not ParseManifest(Lines, ManifestEntries, ErrMsg) then
    begin
      WriteLn(StdErr, 'error: ' + ManifestPath + ': ' + ErrMsg);
      Halt(1);
    end;
  finally
    Lines.Free;
  end;

  ManifestDir := ExtractFilePath(ExpandFileName(ManifestPath));

  Doc := TLauncherDoc.Create;
  try
    ExitOk := True;
    for i := 0 to Length(ManifestEntries) - 1 do
    begin
      FillChar(DocEntry, SizeOf(DocEntry), 0);
      DocEntry.Title := ManifestEntries[i].Title;
      DocEntry.Desc := ManifestEntries[i].Desc;
      DocEntry.ExecPath := ManifestEntries[i].ExecPath;
      DocEntry.Args := ManifestEntries[i].Args;
      DocEntry.Flags := 0;
      if ManifestEntries[i].PauseOnExit then
        DocEntry.Flags := DocEntry.Flags or FLAG_PAUSE_ON_EXIT;
      if ManifestEntries[i].ClearScreen then
        DocEntry.Flags := DocEntry.Flags or FLAG_CLEAR_SCREEN;

      if ManifestEntries[i].IconPath <> '' then
      begin
        ResolvedIconPath := ResolveIconPath(ManifestDir, ManifestEntries[i].IconPath);
        if not LoadAndQuantizePngTo32x32(ResolvedIconPath, Pixels, ErrMsg) then
        begin
          WriteLn(StdErr, Format('error: entry %d ("%s"): %s',
            [i + 1, ManifestEntries[i].Title, ErrMsg]));
          ExitOk := False;
          Continue;
        end;
        DocEntry.HasIcon := True;
        DocEntry.IconData := EncodeIconPCX(Pixels);
      end
      else
        DocEntry.HasIcon := False;

      if not Doc.AddEntry(DocEntry, ErrMsg) then
      begin
        WriteLn(StdErr, Format('error: entry %d ("%s"): %s', [i + 1, ManifestEntries[i].Title, ErrMsg]));
        ExitOk := False;
      end;
    end;

    if not ExitOk then
    begin
      WriteLn(StdErr, 'aborting: fix the errors above before writing ' + OutputPath);
      Halt(1);
    end;

    if not Doc.Validate(Errors) then
    begin
      for i := 0 to Length(Errors) - 1 do
        WriteLn(StdErr, Format('error: entry %d: %s', [Errors[i].EntryIndex + 1, Errors[i].Msg]));
      WriteLn(StdErr, 'aborting: fix the errors above before writing ' + OutputPath);
      Halt(1);
    end;

    if not AtomicSaveDocument(Doc, OutputPath, ErrMsg) then
    begin
      WriteLn(StdErr, 'error: ' + ErrMsg);
      Halt(1);
    end;

    if Doc.Count = 1 then
      WriteLn(Format('wrote %s (1 app)', [OutputPath]))
    else
      WriteLn(Format('wrote %s (%d apps)', [OutputPath, Doc.Count]));
  finally
    Doc.Free;
  end;
end.
