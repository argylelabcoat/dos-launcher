program DOSLAUNCHER;

{$MODE TP}
{$M 16384, 0, 65536} { 16KB stack, 64KB max heap to keep RAM footprint low }

uses Graph, Crt, Dos, RiffLauncher, RiffBgiIcon, ExecSwap;

const
  ITEMS_PER_PAGE = 7;
  ROW_HEIGHT     = 56;
  START_Y        = 40;
  MAX_APPS       = 50;

type
  TAppEntry = record
    Title    : string[40];
    Desc     : string[70];
    ExecPath : string[64];
    Args     : string[64];
    Flags    : Word;    { Copied from TAppInfo.Flags: Bit 0 = Pause on exit, Bit 1 = Clear screen }
    pBgiIcon : Pointer; { Pre-loaded 516-byte BGI RAM buffer }
  end;
  TAppEntryArray = array[0..MAX_APPS - 1] of TAppEntry;
  PAppEntryArray = ^TAppEntryArray;

var
  { Heap-allocated rather than a static global: MAX_APPS * SizeOf(TAppEntry)
    plus the Graph unit's embedded font data otherwise overflows the 64KB
    near data segment (DGROUP) under the DOS memory model. }
  AppList      : PAppEntryArray;
  TotalApps    : Integer;
  CurrentIndex : Integer;
  CurrentPage  : Integer;
  TotalPages   : Integer;
  Gd, Gm       : Integer;

{ --- RIFF Loader: Sequential chunk-walk state machine ---
  Reads the RIFF root header, then walks HDER / LIST("APPS")/APP /INFO/ICON
  chunks by declared size, tolerating unknown chunks, odd-size padding,
  missing icons and truncation. See openspec design D1-D4. }
procedure LoadLauncherData(const FileName: string);
var
  F          : file;
  RootHead   : TRIFFHeader;
  Chunk      : TRIFFChunkHeader;
  ChunkStart : LongInt;
  Hder       : TLauncherHeader;
  ListType   : FourCC;
  Got        : Word;
  FormEnd    : LongInt;
  FileLen    : LongInt;
  HeaderSeen : Boolean;
  Aborted    : Boolean; { Set on truncated/lying data; unwinds every loop below. }

  { Seek to Pos (clamped to the file bounds). False only if the seek itself
    fails at the OS level. }
  function SafeSeek(Pos: LongInt): Boolean;
  begin
    if Pos > FileLen then Pos := FileLen;
    if Pos < 0 then Pos := 0;
    {$I-} Seek(F, Pos); {$I+}
    SafeSeek := IOResult = 0;
  end;

  { Reads one 8-byte chunk header. False (and no partial state) if fewer
    than 8 bytes remain - the caller treats that as end-of-data. }
  function ReadChunkHeader(var Hdr: TRIFFChunkHeader): Boolean;
  var
    N: Word;
  begin
    ReadChunkHeader := False;
    {$I-} BlockRead(F, Hdr, SizeOf(Hdr), N); {$I+}
    if (IOResult <> 0) or (N <> SizeOf(Hdr)) then Exit;
    ReadChunkHeader := True;
  end;

  { Skips forward over a chunk payload of declared Size (plus the RIFF
    word-alignment pad byte when Size is odd), starting at ChunkStart.
    False if the declared size runs past Boundary or the file length - a
    lying size, per D3, which the caller turns into Aborted. }
  function SkipChunkPayload(ChunkStart, Size, Boundary: LongInt): Boolean;
  var
    Target: LongInt;
  begin
    SkipChunkPayload := False;
    if Size < 0 then Exit;
    Target := ChunkStart + Size;
    if (Size and 1) <> 0 then Inc(Target);
    if (Target > Boundary) or (Target > FileLen) then Exit;
    SkipChunkPayload := SafeSeek(Target);
  end;

  { Walks one 'APP ' entry occupying [FilePos(F), EntryEnd). Per D2, an ICON
    attaches to the most recent INFO in the entry; the entry only commits
    (by the caller, via TotalApps) if it had exactly one well-formed INFO. }
  procedure ProcessAppEntry(EntryEnd: LongInt);
  var
    SubChunk  : TRIFFChunkHeader;
    SubStart  : LongInt;
    AppInfo   : TAppInfo;
    N         : Word;
    HaveInfo  : Boolean;
    Malformed : Boolean;
    pIcon     : Pointer;
  begin
    HaveInfo  := False;
    Malformed := False;
    pIcon     := nil;

    while (not Aborted) and (FilePos(F) < EntryEnd) do
    begin
      if not ReadChunkHeader(SubChunk) then
      begin
        Aborted := True; { truncated header: discard this in-progress entry }
        Break;
      end;
      SubStart := FilePos(F);

      if SameFourCC(SubChunk.ID, ID_INFO) then
      begin
        if HaveInfo then
        begin
          { A second INFO in one entry is malformed (D2): discard the entry,
            but keep walking so later entries are unaffected. }
          Malformed := True;
          if not SkipChunkPayload(SubStart, SubChunk.Size, EntryEnd) then
          begin
            Aborted := True;
            Break;
          end;
        end
        else if SubChunk.Size < SizeOf(AppInfo) then
        begin
          { Truncated INFO record: discard this entry and stop loading
            further entries entirely (acceptance scenario). }
          Aborted := True;
          Break;
        end
        else
        begin
          {$I-} BlockRead(F, AppInfo, SizeOf(AppInfo), N); {$I+}
          if (IOResult <> 0) or (N <> SizeOf(AppInfo)) then
          begin
            Aborted := True; { file ended mid-record }
            Break;
          end;
          HaveInfo := True;
          if not SkipChunkPayload(SubStart, SubChunk.Size, EntryEnd) then
          begin
            Aborted := True;
            Break;
          end;
        end;
      end
      else if SameFourCC(SubChunk.ID, ID_ICON) then
      begin
        if HaveInfo and (not Malformed) then
        begin
          if pIcon <> nil then FreeBgiIcon(pIcon); { keep the newest ICON }
          pIcon := LoadRiffIconToBGI(F, SubChunk.Size);
        end;
        { Resync to the declared chunk boundary regardless of how many
          bytes the PCX decoder actually consumed (D3: trust Seek/FilePos
          arithmetic, not dummy reads). }
        if not SafeSeek(SubStart + SubChunk.Size + (SubChunk.Size and 1)) then
        begin
          Aborted := True;
          Break;
        end;
      end
      else
      begin
        { Unknown chunk inside an APP entry: skip it. }
        if not SkipChunkPayload(SubStart, SubChunk.Size, EntryEnd) then
        begin
          Aborted := True;
          Break;
        end;
      end;
    end;

    if Aborted then
    begin
      if pIcon <> nil then FreeBgiIcon(pIcon);
      Exit;
    end;

    if HaveInfo and (not Malformed) and (TotalApps < MAX_APPS) then
    begin
      AppList^[TotalApps].Title    := AppInfo.Title;
      AppList^[TotalApps].Desc     := AppInfo.Desc;
      AppList^[TotalApps].ExecPath := AppInfo.ExecPath;
      AppList^[TotalApps].Args     := AppInfo.Args;
      AppList^[TotalApps].Flags    := AppInfo.Flags;
      AppList^[TotalApps].pBgiIcon := pIcon;
      Inc(TotalApps); { Commit happens here, at entry end - not at ICON (D2). }
    end
    else if pIcon <> nil then
      FreeBgiIcon(pIcon); { Entry discarded (no INFO, or malformed): no leak. }
  end;

  { Walks the child chunks of an 'APPS' LIST, occupying [FilePos(F), ListEnd). }
  procedure ProcessAppsList(ListEnd: LongInt);
  var
    SubChunk   : TRIFFChunkHeader;
    SubStart   : LongInt;
  begin
    while (not Aborted) and (TotalApps < MAX_APPS) and (FilePos(F) < ListEnd) do
    begin
      if not ReadChunkHeader(SubChunk) then
      begin
        Aborted := True;
        Break;
      end;
      SubStart := FilePos(F);

      if SameFourCC(SubChunk.ID, ID_APP) then
      begin
        ProcessAppEntry(SubStart + SubChunk.Size);
        if Aborted then Break;
        if not SkipChunkPayload(SubStart, SubChunk.Size, ListEnd) then
        begin
          Aborted := True;
          Break;
        end;
      end
      else
      begin
        { Unknown chunk between APP entries: skip it. }
        if not SkipChunkPayload(SubStart, SubChunk.Size, ListEnd) then
        begin
          Aborted := True;
          Break;
        end;
      end;
    end;
  end;

begin
  TotalApps  := 0;
  HeaderSeen := False;
  Aborted    := False;

  Assign(F, FileName);
  {$I-} Reset(F, 1); {$I+}
  if IOResult <> 0 then Exit;

  FileLen := FileSize(F);

  {$I-} BlockRead(F, RootHead, SizeOf(RootHead), Got); {$I+}
  if (IOResult <> 0) or (Got <> SizeOf(RootHead)) then
  begin
    Close(F);
    Exit;
  end;

  if not (SameFourCC(RootHead.RIFFID, ID_RIFF) and
          SameFourCC(RootHead.FormType, ID_RCLF)) then
  begin
    Close(F);
    Exit;
  end;

  { RootHead.FileSize is "total file size - 8" (see RiffLauncher.pas); the
    absolute end-of-form offset is the 8-byte RIFF id+size prefix plus that
    value. Clamp a lying/oversized declaration to the real file length. }
  FormEnd := 8 + RootHead.FileSize;
  if (FormEnd > FileLen) or (FormEnd < FilePos(F)) then FormEnd := FileLen;

  while (not Aborted) and (TotalApps < MAX_APPS) and (FilePos(F) < FormEnd) do
  begin
    if not ReadChunkHeader(Chunk) then Break; { truncated trailing header: stop cleanly }
    ChunkStart := FilePos(F);

    if SameFourCC(Chunk.ID, ID_HDER) then
    begin
      if Chunk.Size < SizeOf(Hder) then Break; { truncated HDER payload }
      {$I-} BlockRead(F, Hder, SizeOf(Hder), Got); {$I+}
      if (IOResult <> 0) or (Got <> SizeOf(Hder)) then Break;

      if Hder.Version <> 1 then
      begin
        { Unsupported version: reject the whole file, load nothing. }
        TotalApps := 0;
        Close(F);
        Exit;
      end;

      HeaderSeen := True;
      if not SkipChunkPayload(ChunkStart, Chunk.Size, FormEnd) then Break;
    end
    else if SameFourCC(Chunk.ID, ID_LIST) then
    begin
      if Chunk.Size < SizeOf(ListType) then Break; { truncated LIST payload }
      {$I-} BlockRead(F, ListType, SizeOf(ListType), Got); {$I+}
      if (IOResult <> 0) or (Got <> SizeOf(ListType)) then Break;

      if HeaderSeen and SameFourCC(ListType, ID_APPS) then
      begin
        ProcessAppsList(ChunkStart + Chunk.Size);
        if Aborted then Break;
        if not SkipChunkPayload(ChunkStart, Chunk.Size, FormEnd) then Break;
      end
      else
      begin
        { An APPS list before HDER (D1 requires HDER first), or a LIST of
          some other sub-type: skip the whole thing. }
        if not SkipChunkPayload(ChunkStart, Chunk.Size, FormEnd) then Break;
      end;
    end
    else
    begin
      { Unknown chunk between known chunks: seek past it plus alignment pad. }
      if not SkipChunkPayload(ChunkStart, Chunk.Size, FormEnd) then Break;
    end;
  end;

  Close(F);
  if TotalApps > 0 then
    TotalPages := (TotalApps + ITEMS_PER_PAGE - 1) div ITEMS_PER_PAGE
  else
    TotalPages := 1;
end;

{ --- Rendering Loop --- }
procedure DrawFullPage;
var
  i, PageStart, PageEnd, YPos, LocalIndex : Integer;
begin
  SetFillStyle(SolidFill, Black);
  Bar(0, 0, 639, 479);

  { Header Bar }
  SetColor(Yellow);
  SetTextStyle(DefaultFont, HorizDir, 2);
  OutTextXY(16, 10, 'BOOK-8088 GAME LAUNCHER');

  SetColor(LightCyan);
  SetTextStyle(DefaultFont, HorizDir, 1);
  OutTextXY(480, 16, 'Page ' + Chr(Ord('1') + CurrentPage) + '/' + Chr(Ord('1') + TotalPages - 1));

  SetColor(DarkGray);
  Line(16, 34, 624, 34);

  PageStart := CurrentPage * ITEMS_PER_PAGE;
  PageEnd   := PageStart + ITEMS_PER_PAGE - 1;
  if PageEnd >= TotalApps then PageEnd := TotalApps - 1;

  YPos := START_Y;
  SetTextStyle(DefaultFont, HorizDir, 1);

  for i := PageStart to PageEnd do
  begin
    LocalIndex := i;

    { Draw Selection Box }
    if LocalIndex = CurrentIndex then
    begin
      SetColor(Yellow);
      Rectangle(12, YPos - 4, 628, YPos + 36);
      SetFillStyle(SolidFill, Blue);
      Bar(13, YPos - 3, 627, YPos + 35);
    end;

    { Blit 32x32 Icon instantly }
    if AppList^[LocalIndex].pBgiIcon <> nil then
      PutImage(16, YPos, AppList^[LocalIndex].pBgiIcon^, NormalPut);

    { App Title }
    if LocalIndex = CurrentIndex then SetColor(White) else SetColor(LightGray);
    OutTextXY(60, YPos + 4, AppList^[LocalIndex].Title);

    { App Description }
    SetColor(DarkGray);
    OutTextXY(60, YPos + 20, AppList^[LocalIndex].Desc);

    { Row separator: thin line below each row's content, in the inter-row gap,
      so each row is visually bounded even without a selection box. Drawn for
      all rows including the last on the page for a clean bottom edge. }
    SetColor(DarkGray);
    Line(16, YPos + 40, 624, YPos + 40);

    Inc(YPos, ROW_HEIGHT);
  end;

  { Footer Instructions }
  SetColor(LightGreen);
  Line(16, 450, 624, 450);
  OutTextXY(16, 460, '[UP/DOWN] Select   [LEFT/RIGHT] Page   [ENTER] Play Game');
end;

{ --- Single-Row Repaint (for dirty-rectangle navigation) ---
  Draws one row at the given index in the given selection state. Does NOT
  clear the screen — fills only the row's content area with black, then
  redraws the box/icon/text/separator for that row. Used by UpdateSelection
  for same-page UP/DOWN moves. }
procedure DrawRow(RowIndex: Integer; Selected: Boolean);
var
  YPos : Integer;
begin
  YPos := START_Y + (RowIndex - CurrentPage * ITEMS_PER_PAGE) * ROW_HEIGHT;

  { Erase: fill the row's content area with black regardless of prior state.
    Solid-fill Bar writes all 4 VGA planes in one pass — cheap, and avoids
    tracking "was this row selected before". }
  SetFillStyle(SolidFill, Black);
  Bar(12, YPos - 4, 628, YPos + 36);

  { Selection box (if selected) }
  if Selected then
  begin
    SetColor(Yellow);
    Rectangle(12, YPos - 4, 628, YPos + 36);
    SetFillStyle(SolidFill, Blue);
    Bar(13, YPos - 3, 627, YPos + 35);
  end;

  { Blit 32x32 Icon }
  if AppList^[RowIndex].pBgiIcon <> nil then
    PutImage(16, YPos, AppList^[RowIndex].pBgiIcon^, NormalPut);

  { App Title }
  SetTextStyle(DefaultFont, HorizDir, 1);
  if Selected then SetColor(White) else SetColor(LightGray);
  OutTextXY(60, YPos + 4, AppList^[RowIndex].Title);

  { App Description }
  SetColor(DarkGray);
  OutTextXY(60, YPos + 20, AppList^[RowIndex].Desc);

  { Row separator line }
  SetColor(DarkGray);
  Line(16, YPos + 40, 624, YPos + 40);
end;

{ --- Same-page selection move: repaint only the old and new rows ---
  Called by RunLauncher when CurrentIndex changes but CurrentPage does not.
  Redraws the old row in unselected state and the new row in selected state.
  No screen clear — just two DrawRow calls. }
procedure UpdateSelection(OldIndex, NewIndex: Integer);
begin
  DrawRow(OldIndex, False);
  DrawRow(NewIndex, True);
end;

{ --- Main Event Loop --- }
procedure RunLauncher;
var
  Ch: Char;
  ScanCode: Byte;
  Done: Boolean;
  SwapRes: Integer;
begin
  CurrentIndex := 0;
  CurrentPage  := 0;
  Done         := False;

  while not Done do
  begin
    DrawFullPage;

    Ch := ReadKey;
    if Ch = #0 then
    begin
      ScanCode := Ord(ReadKey);
      case ScanCode of
        72: { UP Arrow }
          if CurrentIndex > 0 then
          begin
            Dec(CurrentIndex);
            CurrentPage := CurrentIndex div ITEMS_PER_PAGE;
          end;
        80: { DOWN Arrow }
          if CurrentIndex < TotalApps - 1 then
          begin
            Inc(CurrentIndex);
            CurrentPage := CurrentIndex div ITEMS_PER_PAGE;
          end;
        75: { LEFT Arrow (Previous Page) }
          if CurrentPage > 0 then
          begin
            Dec(CurrentPage);
            CurrentIndex := CurrentPage * ITEMS_PER_PAGE;
          end;
        77: { RIGHT Arrow (Next Page) }
          if CurrentPage < TotalPages - 1 then
          begin
            Inc(CurrentPage);
            CurrentIndex := CurrentPage * ITEMS_PER_PAGE;
          end;
      end;
    end;

    { Keyrepeat flush so holding keys down doesn't queue inputs on slow 8088 }
    while KeyPressed do ReadKey;

    if Ch = #13 then { ENTER Key: Launch Game }
    begin
      if (TotalApps > 0) and (AppList^[CurrentIndex].ExecPath <> '') then
      begin
        CloseGraph;
        if (AppList^[CurrentIndex].Flags and 2) <> 0 then ClrScr;

        WriteLn('Loading ', AppList^[CurrentIndex].Title, '...');

        { Execute game with swap-to-disk (Frees ~550KB conventional RAM) }
        SwapRes := ExecWithSwap(AppList^[CurrentIndex].ExecPath,
                                AppList^[CurrentIndex].Args,
                                'C:\SWAP.TMP');

        { Pause on exit (bit 0): wait for a keypress in text mode before
          re-entering the graphical menu. }
        if (AppList^[CurrentIndex].Flags and 1) <> 0 then
        begin
          WriteLn('Press any key to continue...');
          ReadKey;
        end;

        { Re-init graphics mode upon game exit }
        InitGraph(Gd, Gm, '');
      end;
    end;

    if Ch = #27 then Done := True; { ESC to quit launcher }
  end;
end;

begin
  New(AppList);

  Gd := VGA;
  Gm := VGAHi; { 640x480 16-color }
  InitGraph(Gd, Gm, '');
  if GraphResult <> grOk then Halt(1);

  LoadLauncherData('LAUNCHER.DAT');

  if TotalApps > 0 then
    RunLauncher
  else
  begin
    CloseGraph;
    WriteLn('No games found in LAUNCHER.DAT!');
    ReadKey;
  end;

  CloseGraph;
  Dispose(AppList);
end.
