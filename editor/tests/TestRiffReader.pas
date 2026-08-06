unit TestRiffReader;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry,
  RiffLauncher, LauncherDoc, RiffWriter, RiffReader;

type
  TTestRiffReader = class(TTestCase)
  private
    procedure WriteFCC(Stream: TStream; const FCC: FourCC);
    procedure WriteI32(Stream: TStream; V: LongInt);
    procedure WriteChunkHdr(Stream: TStream; const ID: FourCC; Size: LongInt);
  published
    procedure ValidRootIsAccepted;
    procedure WrongFormTypeIsRejected;
    procedure UnsupportedHderVersionIsRejected;
    procedure TruncatedRootIsRejected;
    procedure DeclaredSizeOverrunIsRejected;
    procedure MissingInfoEntryIsDiscardedNotFatal;
    procedure TruncatedInfoEntryIsDiscardedNotFatal;
    procedure IconPairsWithMostRecentInfo;
    procedure RoundTripThroughWriterPreservesFields;
  end;

implementation

procedure WriteZeroI32(Stream: TStream);
var
  Zero: LongInt;
begin
  Zero := 0;
  Stream.WriteBuffer(Zero, SizeOf(Zero));
end;

procedure WriteI32Const(Stream: TStream; V: LongInt);
begin
  Stream.WriteBuffer(V, SizeOf(V));
end;

function MakeEntry(const Title, ExecPath: string): TAppEntry;
begin
  Result.Title := Title;
  Result.Desc := 'd';
  Result.ExecPath := ExecPath;
  Result.Args := 'args';
  Result.Flags := 3;
  Result.HasIcon := False;
  SetLength(Result.IconData, 0);
end;

procedure TTestRiffReader.WriteFCC(Stream: TStream; const FCC: FourCC);
begin
  Stream.WriteBuffer(FCC, SizeOf(FCC));
end;

procedure TTestRiffReader.WriteI32(Stream: TStream; V: LongInt);
begin
  Stream.WriteBuffer(V, SizeOf(V));
end;

procedure TTestRiffReader.WriteChunkHdr(Stream: TStream; const ID: FourCC; Size: LongInt);
begin
  WriteFCC(Stream, ID);
  WriteI32(Stream, Size);
end;

procedure TTestRiffReader.ValidRootIsAccepted;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  Stream: TMemoryStream;
  Loaded: TAppEntryArray;
begin
  SetLength(Entries, 1);
  Entries[0] := MakeEntry('Game', 'C:\GAME.EXE');
  Bytes := SerializeLauncherEntries(Entries);

  Stream := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Loaded := LoadRiffEntriesFromStream(Stream);
    AssertEquals(1, Length(Loaded));
    AssertEquals('Game', Loaded[0].Title);
    AssertEquals('C:\GAME.EXE', Loaded[0].ExecPath);
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.WrongFormTypeIsRejected;
var
  Stream: TMemoryStream;
  Bad: FourCC;
begin
  Bad := 'BADX';
  Stream := TMemoryStream.Create;
  try
    WriteFCC(Stream, ID_RIFF);
    WriteI32(Stream, 4);
    WriteFCC(Stream, Bad);
    Stream.Position := 0;
    try
      LoadRiffEntriesFromStream(Stream);
      Fail('expected ERiffFormatError for wrong form type');
    except
      on E: ERiffFormatError do ; { expected }
    end;
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.UnsupportedHderVersionIsRejected;
var
  Stream: TMemoryStream;
  Version, AppCount, Flags: Word;
begin
  Stream := TMemoryStream.Create;
  try
    WriteFCC(Stream, ID_RIFF);
    WriteI32(Stream, 0); { patched below }
    WriteFCC(Stream, ID_RCLF);

    WriteChunkHdr(Stream, ID_HDER, 6);
    Version := 99; { unsupported }
    AppCount := 0;
    Flags := 0;
    Stream.WriteBuffer(Version, SizeOf(Version));
    Stream.WriteBuffer(AppCount, SizeOf(AppCount));
    Stream.WriteBuffer(Flags, SizeOf(Flags));

    { Patch root size = total - 8 }
    Stream.Position := 4;
    WriteI32(Stream, Stream.Size - 8);
    Stream.Position := 0;

    try
      LoadRiffEntriesFromStream(Stream);
      Fail('expected ERiffFormatError for unsupported HDER version');
    except
      on E: ERiffFormatError do ; { expected }
    end;
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.TruncatedRootIsRejected;
var
  Stream: TMemoryStream;
  b: Byte;
begin
  Stream := TMemoryStream.Create;
  try
    WriteFCC(Stream, ID_RIFF);
    b := 0;
    Stream.WriteBuffer(b, 1); { only 1 of 4 size bytes: truncated root header }
    Stream.Position := 0;
    try
      LoadRiffEntriesFromStream(Stream);
      Fail('expected ERiffFormatError for truncated root header');
    except
      on E: ERiffFormatError do ; { expected }
    end;
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.DeclaredSizeOverrunIsRejected;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    WriteFCC(Stream, ID_RIFF);
    WriteI32(Stream, 999999); { lies about the file being huge }
    WriteFCC(Stream, ID_RCLF);
    { Declare a HDER chunk whose size overruns everything that actually follows }
    WriteChunkHdr(Stream, ID_HDER, 500);
    Stream.Position := 0;
    try
      LoadRiffEntriesFromStream(Stream);
      Fail('expected ERiffFormatError for a chunk size that overruns available bytes');
    except
      on E: ERiffFormatError do ; { expected }
    end;
  finally
    Stream.Free;
  end;
end;

{ Builds a minimal-but-valid root + HDER, then hands back the stream
  positioned right after HDER so the test can append a hand-built APPS
  LIST payload. AppCount in HDER is a declared hint only -- the reader
  determines actual entries from what it finds, so tests are free to
  under/over-state it deliberately. }
procedure BuildRootWithHeader(Stream: TMemoryStream; AppCount: Word);
var
  Version, Flags: Word;
begin
  Stream.WriteBuffer(ID_RIFF, SizeOf(FourCC));
  WriteZeroI32(Stream); { patched at the end }
  Stream.WriteBuffer(ID_RCLF, SizeOf(FourCC));

  Stream.WriteBuffer(ID_HDER, SizeOf(FourCC));
  WriteI32Const(Stream, 6);
  Version := 1;
  Stream.WriteBuffer(Version, SizeOf(Word));
  Stream.WriteBuffer(AppCount, SizeOf(Word));
  Flags := 0;
  Stream.WriteBuffer(Flags, SizeOf(Word));
end;

procedure PatchRootSize(Stream: TMemoryStream);
var
  Sz: LongInt;
begin
  Sz := Stream.Size - 8;
  Stream.Position := 4;
  Stream.WriteBuffer(Sz, SizeOf(Sz));
  Stream.Position := 0;
end;

procedure TTestRiffReader.MissingInfoEntryIsDiscardedNotFatal;
var
  Stream: TMemoryStream;
  ListSizePos, ListPayloadStart, AppSizePos, AppPayloadStart: Int64;
  ListSize, AppSize: LongInt;
  Loaded: TAppEntryArray;
  GoodInfo: TAppInfo;
begin
  Stream := TMemoryStream.Create;
  try
    BuildRootWithHeader(Stream, 2);

    { LIST 'APPS' }
    Stream.WriteBuffer(ID_LIST, SizeOf(FourCC));
    ListSizePos := Stream.Position;
    WriteZeroI32(Stream);
    ListPayloadStart := Stream.Position; { LIST payload includes the 4-byte list-type FourCC }
    Stream.WriteBuffer(ID_APPS, SizeOf(FourCC));

    { Entry 1: 'APP ' with an empty payload -- no INFO at all. }
    Stream.WriteBuffer(ID_APP, SizeOf(FourCC));
    AppSizePos := Stream.Position;
    WriteZeroI32(Stream);
    AppPayloadStart := Stream.Position;
    AppSize := Stream.Position - AppPayloadStart;
    Stream.Position := AppSizePos;
    Stream.WriteBuffer(AppSize, SizeOf(AppSize));
    Stream.Position := AppPayloadStart;

    { Entry 2: 'APP ' with a well-formed INFO. }
    Stream.WriteBuffer(ID_APP, SizeOf(FourCC));
    AppSizePos := Stream.Position;
    WriteZeroI32(Stream);
    AppPayloadStart := Stream.Position;

    Stream.WriteBuffer(ID_INFO, SizeOf(FourCC));
    WriteI32Const(Stream, SizeOf(GoodInfo));
    FillChar(GoodInfo, SizeOf(GoodInfo), 0);
    GoodInfo.Title := 'Survivor';
    GoodInfo.Desc := 'ok';
    GoodInfo.ExecPath := 'C:\SURV.EXE';
    GoodInfo.Args := '';
    GoodInfo.Flags := 0;
    Stream.WriteBuffer(GoodInfo, SizeOf(GoodInfo));

    AppSize := Stream.Position - AppPayloadStart;
    Stream.Position := AppSizePos;
    Stream.WriteBuffer(AppSize, SizeOf(AppSize));
    Stream.Position := Stream.Size;

    ListSize := Stream.Position - ListPayloadStart;
    Stream.Position := ListSizePos;
    Stream.WriteBuffer(ListSize, SizeOf(ListSize));
    Stream.Position := Stream.Size;

    PatchRootSize(Stream);

    Loaded := LoadRiffEntriesFromStream(Stream);
    AssertEquals('only the well-formed entry should survive', 1, Length(Loaded));
    AssertEquals('Survivor', Loaded[0].Title);
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.TruncatedInfoEntryIsDiscardedNotFatal;
var
  Stream: TMemoryStream;
  ListSizePos, ListPayloadStart, AppSizePos, AppPayloadStart: Int64;
  ListSize, AppSize: LongInt;
  Loaded: TAppEntryArray;
  Junk: array[0..9] of Byte;
begin
  Stream := TMemoryStream.Create;
  try
    BuildRootWithHeader(Stream, 1);

    Stream.WriteBuffer(ID_LIST, SizeOf(FourCC));
    ListSizePos := Stream.Position;
    WriteZeroI32(Stream);
    ListPayloadStart := Stream.Position; { LIST payload includes the 4-byte list-type FourCC }
    Stream.WriteBuffer(ID_APPS, SizeOf(FourCC));

    { One 'APP ' whose INFO chunk declares a size smaller than TAppInfo. }
    Stream.WriteBuffer(ID_APP, SizeOf(FourCC));
    AppSizePos := Stream.Position;
    WriteZeroI32(Stream);
    AppPayloadStart := Stream.Position;

    Stream.WriteBuffer(ID_INFO, SizeOf(FourCC));
    WriteI32Const(Stream, 10); { too small for TAppInfo }
    FillChar(Junk, SizeOf(Junk), $AA);
    Stream.WriteBuffer(Junk, SizeOf(Junk));

    AppSize := Stream.Position - AppPayloadStart;
    Stream.Position := AppSizePos;
    Stream.WriteBuffer(AppSize, SizeOf(AppSize));
    Stream.Position := Stream.Size;

    ListSize := Stream.Position - ListPayloadStart;
    Stream.Position := ListSizePos;
    Stream.WriteBuffer(ListSize, SizeOf(ListSize));
    Stream.Position := Stream.Size;

    PatchRootSize(Stream);

    Loaded := LoadRiffEntriesFromStream(Stream);
    AssertEquals('the truncated-INFO entry must be discarded, not raised', 0, Length(Loaded));
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.IconPairsWithMostRecentInfo;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  Stream: TMemoryStream;
  Loaded: TAppEntryArray;
begin
  SetLength(Entries, 1);
  Entries[0] := MakeEntry('Iconned', 'C:\I.EXE');
  Entries[0].HasIcon := True;
  SetLength(Entries[0].IconData, 20);
  FillChar(Entries[0].IconData[0], 20, $5A);

  Bytes := SerializeLauncherEntries(Entries);
  Stream := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Loaded := LoadRiffEntriesFromStream(Stream);
    AssertEquals(1, Length(Loaded));
    AssertTrue(Loaded[0].HasIcon);
    AssertEquals(20, Length(Loaded[0].IconData));
    AssertEquals($5A, Loaded[0].IconData[0]);
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffReader.RoundTripThroughWriterPreservesFields;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  Stream: TMemoryStream;
  Loaded: TAppEntryArray;
begin
  SetLength(Entries, 3);
  Entries[0] := MakeEntry('One', 'C:\ONE.EXE');
  Entries[1] := MakeEntry('Two', 'C:\TWO.EXE');
  Entries[1].Flags := 1;
  Entries[2] := MakeEntry('Three', 'C:\THREE.EXE');

  Bytes := SerializeLauncherEntries(Entries);
  Stream := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Loaded := LoadRiffEntriesFromStream(Stream);
    AssertEquals(3, Length(Loaded));
    AssertEquals('One', Loaded[0].Title);
    AssertEquals('Two', Loaded[1].Title);
    AssertEquals(1, Loaded[1].Flags);
    AssertEquals('Three', Loaded[2].Title);
    AssertEquals('C:\THREE.EXE', Loaded[2].ExecPath);
  finally
    Stream.Free;
  end;
end;

initialization
  RegisterTest(TTestRiffReader);
end.
