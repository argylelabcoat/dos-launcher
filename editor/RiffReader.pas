unit RiffReader;

{ Desktop-side RCLF loader. Independent implementation of the same
  rclf-container spec that snips/launcher.pas's LoadLauncherData
  implements (design D6) -- deliberately not shared code, so a
  disagreement between the two flags a spec ambiguity rather than being
  silently hidden by a shared bug.

  Structural problems (bad root signature, unsupported HDER version, a
  declared chunk size that runs past its container's bounds, or a chunk
  header that can't be fully read where the container declares more data
  should follow) raise a descriptive ERiffFormatError -- unlike the DOS
  loader's silent-degrade-to-empty convention, exceptions are the desktop
  convention here (design D6), and the caller is expected to catch them
  and leave its existing document unmodified.

  Content-level problems fully contained within one APP entry's declared
  bounds (missing INFO, a second INFO, a too-small INFO payload) discard
  just that entry and continue -- the entry's bounds are already known
  good by the time those are detected, so there's always a safe resync
  point and no need to abort the whole load. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, RiffLauncher, LauncherDoc;

type
  ERiffFormatError = class(Exception);

{ Loads all well-formed APP entries from FileName. Raises
  ERiffFormatError on any structural problem; on success returns the
  entries in file order (already clamped to MAX_APPS). }
function LoadRiffEntries(const FileName: string): TAppEntryArray;

{ Stream-based variant, used by both LoadRiffEntries and SaveIO's
  post-write reload self-check. }
function LoadRiffEntriesFromStream(Stream: TStream): TAppEntryArray;

implementation

type
  TByteBuf = array of Byte;

function ReadFourCC(Stream: TStream; out FCC: FourCC): Boolean;
var
  N: Integer;
begin
  N := Stream.Read(FCC, SizeOf(FCC));
  Result := N = SizeOf(FCC);
end;

function ReadChunkHeader(Stream: TStream; out Hdr: TRIFFChunkHeader): Boolean;
var
  N: Integer;
begin
  N := Stream.Read(Hdr, SizeOf(Hdr));
  Result := N = SizeOf(Hdr);
end;

{ Seeks to Pos (clamped to [0, Limit]). }
procedure SafeSeek(Stream: TStream; Pos, Limit: Int64);
begin
  if Pos > Limit then Pos := Limit;
  if Pos < 0 then Pos := 0;
  Stream.Position := Pos;
end;

{ Validates that a declared chunk payload of Size bytes starting at
  ChunkStart fits within Boundary and the stream's actual length; returns
  the offset just past the (possibly padded) payload. Raises
  ERiffFormatError if the declared size lies about what's available --
  this is the "truncated chunk" structural failure the reader is
  required to reject outright. }
function ChunkPayloadEnd(Stream: TStream; ChunkStart, Size, Boundary: Int64): Int64;
var
  Target: Int64;
begin
  if Size < 0 then
    raise ERiffFormatError.Create('RCLF: negative chunk size');
  Target := ChunkStart + Size;
  if (Size and 1) <> 0 then Inc(Target);
  if (Target > Boundary) or (Target > Stream.Size) then
    raise ERiffFormatError.CreateFmt('RCLF: chunk at %d declares size %d past its container bounds', [ChunkStart, Size]);
  Result := Target;
end;

{ Parses one 'APP ' entry's payload, bounded to [Stream.Position, EntryEnd).
  Discards (does not raise for) missing/duplicate/truncated INFO -- those
  are content-level, not structural. Always leaves Stream positioned at
  EntryEnd on return. }
function ProcessAppEntry(Stream: TStream; EntryEnd: Int64; out Entry: TAppEntry): Boolean;
var
  SubChunk  : TRIFFChunkHeader;
  SubStart  : Int64;
  AppInfo   : TAppInfo;
  HaveInfo  : Boolean;
  Malformed : Boolean;
  HasIcon   : Boolean;
  IconBytes : TBytes;
  N         : Integer;
  PayloadEnd: Int64;
begin
  HaveInfo  := False;
  Malformed := False;
  HasIcon   := False;
  SetLength(IconBytes, 0);
  FillChar(AppInfo, SizeOf(AppInfo), 0);

  while Stream.Position < EntryEnd do
  begin
    if (EntryEnd - Stream.Position) < SizeOf(SubChunk) then
    begin
      { A dangling partial header inside a declared-good entry region is
        itself content-level (the entry's own bounds are already known
        valid) -- treat it as "entry has no more usable data" and stop
        scanning this entry. }
      Break;
    end;
    if not ReadChunkHeader(Stream, SubChunk) then Break;
    SubStart := Stream.Position;

    if SameFourCC(SubChunk.ID, ID_INFO) then
    begin
      if HaveInfo then
      begin
        Malformed := True;
        PayloadEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, EntryEnd);
        SafeSeek(Stream, PayloadEnd, EntryEnd);
      end
      else if SubChunk.Size < SizeOf(AppInfo) then
      begin
        { Truncated INFO payload: discard this entry only. }
        HaveInfo := False;
        Malformed := True;
        SafeSeek(Stream, EntryEnd, EntryEnd);
        Break;
      end
      else
      begin
        N := Stream.Read(AppInfo, SizeOf(AppInfo));
        if N <> SizeOf(AppInfo) then
        begin
          Malformed := True;
          SafeSeek(Stream, EntryEnd, EntryEnd);
          Break;
        end;
        HaveInfo := True;
        PayloadEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, EntryEnd);
        SafeSeek(Stream, PayloadEnd, EntryEnd);
      end;
    end
    else if SameFourCC(SubChunk.ID, ID_ICON) then
    begin
      PayloadEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, EntryEnd);
      if HaveInfo and (not Malformed) then
      begin
        SetLength(IconBytes, SubChunk.Size);
        if SubChunk.Size > 0 then
        begin
          N := Stream.Read(IconBytes[0], SubChunk.Size);
          if N <> SubChunk.Size then
          begin
            SetLength(IconBytes, 0);
            HasIcon := False;
          end
          else
            HasIcon := True;
        end
        else
          HasIcon := True;
      end;
      SafeSeek(Stream, PayloadEnd, EntryEnd);
    end
    else
    begin
      { Unknown chunk inside an APP entry: skip it. }
      PayloadEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, EntryEnd);
      SafeSeek(Stream, PayloadEnd, EntryEnd);
    end;
  end;

  SafeSeek(Stream, EntryEnd, EntryEnd);

  Result := HaveInfo and (not Malformed);
  if Result then
  begin
    Entry.Title    := AppInfo.Title;
    Entry.Desc     := AppInfo.Desc;
    Entry.ExecPath := AppInfo.ExecPath;
    Entry.Args     := AppInfo.Args;
    Entry.Flags    := AppInfo.Flags;
    Entry.HasIcon  := HasIcon;
    Entry.IconData := IconBytes;
  end;
end;

{ Parses the children of a 'LIST'/'APPS' payload, bounded to
  [Stream.Position, ListEnd). }
procedure ProcessAppsList(Stream: TStream; ListEnd: Int64; var Entries: TAppEntryArray);
var
  SubChunk : TRIFFChunkHeader;
  SubStart : Int64;
  AppEnd, PayloadEnd: Int64;
  Entry    : TAppEntry;
begin
  while (Length(Entries) < MAX_APPS) and (Stream.Position < ListEnd) do
  begin
    if (ListEnd - Stream.Position) < SizeOf(SubChunk) then
      raise ERiffFormatError.Create('RCLF: truncated chunk header inside APPS list');
    if not ReadChunkHeader(Stream, SubChunk) then
      raise ERiffFormatError.Create('RCLF: truncated chunk header inside APPS list');
    SubStart := Stream.Position;

    if SameFourCC(SubChunk.ID, ID_APP) then
    begin
      AppEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, ListEnd);
      { Un-padded end for the entry's own content walk. }
      if ProcessAppEntry(Stream, SubStart + SubChunk.Size, Entry) then
      begin
        SetLength(Entries, Length(Entries) + 1);
        Entries[High(Entries)] := Entry;
      end;
      SafeSeek(Stream, AppEnd, ListEnd);
    end
    else
    begin
      PayloadEnd := ChunkPayloadEnd(Stream, SubStart, SubChunk.Size, ListEnd);
      SafeSeek(Stream, PayloadEnd, ListEnd);
    end;
  end;
end;

function LoadRiffEntriesFromStream(Stream: TStream): TAppEntryArray;
var
  RootHead  : TRIFFHeader;
  N         : Integer;
  FormEnd   : Int64;
  FileLen   : Int64;
  HeaderSeen: Boolean;
  Chunk     : TRIFFChunkHeader;
  ChunkStart: Int64;
  Hder      : TLauncherHeader;
  ListType  : FourCC;
  PayloadEnd: Int64;
begin
  SetLength(Result, 0);
  Stream.Position := 0;
  FileLen := Stream.Size;

  if FileLen < SizeOf(RootHead) then
    raise ERiffFormatError.Create('RCLF: file too small for a RIFF root header');

  N := Stream.Read(RootHead, SizeOf(RootHead));
  if N <> SizeOf(RootHead) then
    raise ERiffFormatError.Create('RCLF: truncated RIFF root header');

  if not SameFourCC(RootHead.RIFFID, ID_RIFF) then
    raise ERiffFormatError.Create('RCLF: not a RIFF file (bad RIFF id)');
  if not SameFourCC(RootHead.FormType, ID_RCLF) then
    raise ERiffFormatError.Create('RCLF: wrong form type (expected RCLF)');

  FormEnd := 8 + RootHead.FileSize;
  if (FormEnd > FileLen) or (FormEnd < Stream.Position) then
    FormEnd := FileLen;

  HeaderSeen := False;

  while (Length(Result) < MAX_APPS) and (Stream.Position < FormEnd) do
  begin
    if (FormEnd - Stream.Position) < SizeOf(Chunk) then
      raise ERiffFormatError.Create('RCLF: truncated chunk header at top level');
    if not ReadChunkHeader(Stream, Chunk) then
      raise ERiffFormatError.Create('RCLF: truncated chunk header at top level');
    ChunkStart := Stream.Position;

    if SameFourCC(Chunk.ID, ID_HDER) then
    begin
      if Chunk.Size < SizeOf(Hder) then
        raise ERiffFormatError.Create('RCLF: truncated HDER payload');
      N := Stream.Read(Hder, SizeOf(Hder));
      if N <> SizeOf(Hder) then
        raise ERiffFormatError.Create('RCLF: truncated HDER payload');
      if Hder.Version <> 1 then
        raise ERiffFormatError.CreateFmt('RCLF: unsupported HDER version %d (expected 1)', [Hder.Version]);
      HeaderSeen := True;
      PayloadEnd := ChunkPayloadEnd(Stream, ChunkStart, Chunk.Size, FormEnd);
      SafeSeek(Stream, PayloadEnd, FormEnd);
    end
    else if SameFourCC(Chunk.ID, ID_LIST) then
    begin
      if Chunk.Size < SizeOf(ListType) then
        raise ERiffFormatError.Create('RCLF: truncated LIST payload');
      N := Stream.Read(ListType, SizeOf(ListType));
      if N <> SizeOf(ListType) then
        raise ERiffFormatError.Create('RCLF: truncated LIST payload');

      if SameFourCC(ListType, ID_APPS) then
      begin
        if not HeaderSeen then
          raise ERiffFormatError.Create('RCLF: APPS list encountered before HDER chunk');
        PayloadEnd := ChunkPayloadEnd(Stream, ChunkStart, Chunk.Size, FormEnd);
        ProcessAppsList(Stream, ChunkStart + Chunk.Size, Result);
        SafeSeek(Stream, PayloadEnd, FormEnd);
      end
      else
      begin
        PayloadEnd := ChunkPayloadEnd(Stream, ChunkStart, Chunk.Size, FormEnd);
        SafeSeek(Stream, PayloadEnd, FormEnd);
      end;
    end
    else
    begin
      PayloadEnd := ChunkPayloadEnd(Stream, ChunkStart, Chunk.Size, FormEnd);
      SafeSeek(Stream, PayloadEnd, FormEnd);
    end;
  end;

  if not HeaderSeen then
    raise ERiffFormatError.Create('RCLF: no HDER chunk found');
end;

function LoadRiffEntries(const FileName: string): TAppEntryArray;
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := LoadRiffEntriesFromStream(FS);
  finally
    FS.Free;
  end;
end;

end.
