unit TestRiffWriter;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry,
  RiffLauncher, LauncherDoc, RiffWriter;

type
  TTestRiffWriter = class(TTestCase)
  published
    procedure RootHeaderIsSpecCompliant;
    procedure StructureHasHderAndAppsList;
    procedure WordAlignmentPadsOddIconPayload;
    procedure NoIconMeansNoIconChunk;
    procedure AppEntriesAreFlatChunksNotNestedList;
  end;

implementation

function MakeEntry(const Title, ExecPath: string): TAppEntry;
begin
  Result.Title := Title;
  Result.Desc := 'd';
  Result.ExecPath := ExecPath;
  Result.Args := '';
  Result.Flags := 0;
  Result.HasIcon := False;
  SetLength(Result.IconData, 0);
end;

procedure TTestRiffWriter.RootHeaderIsSpecCompliant;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  RIFFId, FormType: FourCC;
  Sz: LongInt;
begin
  SetLength(Entries, 1);
  Entries[0] := MakeEntry('A', 'C:\A.EXE');

  Bytes := SerializeLauncherEntries(Entries);
  AssertTrue('at least a 12-byte root header', Length(Bytes) >= 12);

  Move(Bytes[0], RIFFId, SizeOf(FourCC));
  Move(Bytes[4], Sz, SizeOf(LongInt));
  Move(Bytes[8], FormType, SizeOf(FourCC));

  AssertTrue('RIFF id', SameFourCC(RIFFId, ID_RIFF));
  AssertTrue('RCLF form type', SameFourCC(FormType, ID_RCLF));
  AssertEquals('declared size = total - 8', Length(Bytes) - 8, Sz);
end;

procedure TTestRiffWriter.StructureHasHderAndAppsList;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  Stream: TMemoryStream;
  Chunk: TRIFFChunkHeader;
  ListType: FourCC;
  Hder: TLauncherHeader;
  SawHder, SawApps: Boolean;
begin
  SetLength(Entries, 2);
  Entries[0] := MakeEntry('A', 'C:\A.EXE');
  Entries[1] := MakeEntry('B', 'C:\B.EXE');

  Bytes := SerializeLauncherEntries(Entries);

  Stream := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Stream.Position := 12; { past the 12-byte root header }

    SawHder := False;
    SawApps := False;

    { HDER must come first per the writer's contract. }
    Stream.ReadBuffer(Chunk, SizeOf(Chunk));
    AssertTrue('first chunk is HDER', SameFourCC(Chunk.ID, ID_HDER));
    Stream.ReadBuffer(Hder, SizeOf(Hder));
    AssertEquals(1, Hder.Version);
    AssertEquals(2, Hder.AppCount);
    AssertEquals(0, Hder.Flags);
    SawHder := True;
    if (Chunk.Size and 1) <> 0 then
      Stream.Seek(1, soFromCurrent);

    Stream.ReadBuffer(Chunk, SizeOf(Chunk));
    AssertTrue('second chunk is LIST', SameFourCC(Chunk.ID, ID_LIST));
    Stream.ReadBuffer(ListType, SizeOf(ListType));
    AssertTrue('LIST subtype is APPS', SameFourCC(ListType, ID_APPS));
    SawApps := True;

    AssertTrue(SawHder);
    AssertTrue(SawApps);
    AssertEquals('root declares no trailing bytes past the LIST',
      Stream.Size, Int64(12) + Int64(SizeOf(TRIFFChunkHeader)) + Int64(SizeOf(Hder)) +
        Int64(SizeOf(TRIFFChunkHeader)) + Int64(Chunk.Size));
  finally
    Stream.Free;
  end;
end;

procedure TTestRiffWriter.WordAlignmentPadsOddIconPayload;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
begin
  SetLength(Entries, 1);
  Entries[0] := MakeEntry('A', 'C:\A.EXE');
  Entries[0].HasIcon := True;
  SetLength(Entries[0].IconData, 129); { odd length payload }

  Bytes := SerializeLauncherEntries(Entries);
  { The whole file must remain evenly sized: every chunk pads itself to
    an even length, so any concatenation of them is even too. }
  AssertEquals(0, Length(Bytes) mod 2);
end;

procedure TTestRiffWriter.NoIconMeansNoIconChunk;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  s: string;
  i: Integer;
begin
  SetLength(Entries, 1);
  Entries[0] := MakeEntry('A', 'C:\A.EXE');
  Entries[0].HasIcon := False;

  Bytes := SerializeLauncherEntries(Entries);

  { Crude but sufficient: the 4-byte ASCII 'ICON' should not appear
    anywhere in the output when no entry has an icon. }
  SetLength(s, Length(Bytes));
  for i := 0 to High(Bytes) do
    s[i + 1] := Chr(Bytes[i]);
  AssertEquals(0, Pos('ICON', s));
end;

{ Regression guard for the rclf-container spec's APPS/APP requirement: each
  application entry inside LIST/APPS is a flat 'APP ' chunk (ID_APP), never a
  nested LIST chunk with subtype 'APP '. A generic RIFF walker (or an earlier
  draft of the spec) might expect the latter; the writer must never produce it. }
procedure TTestRiffWriter.AppEntriesAreFlatChunksNotNestedList;
var
  Entries: TAppEntryArray;
  Bytes: TBytes;
  Stream: TMemoryStream;
  Chunk: TRIFFChunkHeader;
  ListType: FourCC;
  Hder: TLauncherHeader;
  ListPayloadEnd: Int64;
  EntryChunk: TRIFFChunkHeader;
  SeenEntries: Integer;
begin
  SetLength(Entries, 2);
  Entries[0] := MakeEntry('A', 'C:\A.EXE');
  Entries[1] := MakeEntry('B', 'C:\B.EXE');

  Bytes := SerializeLauncherEntries(Entries);

  Stream := TMemoryStream.Create;
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    Stream.Position := 12;

    { Skip HDER }
    Stream.ReadBuffer(Chunk, SizeOf(Chunk));
    AssertTrue('first chunk is HDER', SameFourCC(Chunk.ID, ID_HDER));
    Stream.ReadBuffer(Hder, SizeOf(Hder));
    if (Chunk.Size and 1) <> 0 then
      Stream.Seek(1, soFromCurrent);

    { Enter LIST/APPS }
    Stream.ReadBuffer(Chunk, SizeOf(Chunk));
    AssertTrue('second chunk is LIST', SameFourCC(Chunk.ID, ID_LIST));
    ListPayloadEnd := Stream.Position + Chunk.Size;
    Stream.ReadBuffer(ListType, SizeOf(ListType));
    AssertTrue('LIST subtype is APPS', SameFourCC(ListType, ID_APPS));

    SeenEntries := 0;
    while Stream.Position < ListPayloadEnd do
    begin
      Stream.ReadBuffer(EntryChunk, SizeOf(EntryChunk));
      AssertTrue('each APPS entry is a flat APP chunk, not a nested LIST',
        SameFourCC(EntryChunk.ID, ID_APP));
      AssertFalse('an APPS entry must never be a LIST chunk',
        SameFourCC(EntryChunk.ID, ID_LIST));
      Inc(SeenEntries);
      Stream.Seek(EntryChunk.Size, soFromCurrent);
      if (EntryChunk.Size and 1) <> 0 then
        Stream.Seek(1, soFromCurrent);
    end;

    AssertEquals('both entries walked as flat APP chunks', 2, SeenEntries);
  finally
    Stream.Free;
  end;
end;

initialization
  RegisterTest(TTestRiffWriter);
end.
