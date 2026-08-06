unit RiffWriter;

{ RCLF serializer (design D3). Builds each chunk bottom-up as a byte
  blob that is already word-aligned (padded to an even length) by the
  time it is handed to its parent, so parent chunk sizes -- and the
  eventual RIFF root size -- never need a separate alignment pass; only
  the size *value* needs to be known once the child blob's length is
  final, which falls out naturally from building bottom-up. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, RiffLauncher, LauncherDoc;

{ Serializes Entries into a complete RCLF byte stream: RIFF/RCLF root,
  one HDER (Version=1, AppCount=Length(Entries), Flags=0), one LIST/APPS
  containing one 'APP ' chunk per entry with an INFO chunk and an
  optional ICON chunk. }
function SerializeLauncherEntries(const Entries: TAppEntryArray): TBytes;

{ Convenience wrapper writing the serialized bytes to Stream. }
procedure WriteLauncherEntries(const Entries: TAppEntryArray; Stream: TStream);

implementation

{ Appends B onto the end of A (in place). }
procedure AppendBytes(var A: TBytes; const B: TBytes);
var
  OldLen: Integer;
begin
  if Length(B) = 0 then Exit;
  OldLen := Length(A);
  SetLength(A, OldLen + Length(B));
  Move(B[0], A[OldLen], Length(B));
end;

{ Builds a complete chunk: 8-byte header (ID + declared payload size) +
  Payload + a zero pad byte if Payload's length is odd. The result is
  therefore always an even number of bytes, which is what lets callers
  concatenate child chunk blobs directly into a parent payload without
  any extra alignment bookkeeping. }
function BuildChunk(const ID: FourCC; const Payload: TBytes): TBytes;
var
  Hdr: TRIFFChunkHeader;
  Sz: Integer;
  Pad: TBytes;
begin
  Hdr.ID := ID;
  Hdr.Size := Length(Payload);
  SetLength(Result, SizeOf(Hdr));
  Move(Hdr, Result[0], SizeOf(Hdr));
  AppendBytes(Result, Payload);
  Sz := Length(Payload);
  if (Sz and 1) <> 0 then
  begin
    SetLength(Pad, 1);
    Pad[0] := 0;
    AppendBytes(Result, Pad);
  end;
end;

{ Wraps a FourCC value as a 4-byte TBytes for AppendBytes. }
function FourCCBytes(const FCC: FourCC): TBytes;
begin
  SetLength(Result, SizeOf(FourCC));
  Move(FCC, Result[0], SizeOf(FourCC));
end;

function BuildInfoChunk(const Entry: TAppEntry): TBytes;
var
  Info: TAppInfo;
  Payload: TBytes;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.Title := Entry.Title;
  Info.Desc := Entry.Desc;
  Info.ExecPath := Entry.ExecPath;
  Info.Args := Entry.Args;
  Info.Flags := Entry.Flags;

  SetLength(Payload, SizeOf(Info));
  Move(Info, Payload[0], SizeOf(Info));
  Result := BuildChunk(ID_INFO, Payload);
end;

function BuildAppChunk(const Entry: TAppEntry): TBytes;
var
  Payload: TBytes;
begin
  SetLength(Payload, 0);
  AppendBytes(Payload, BuildInfoChunk(Entry));
  if Entry.HasIcon and (Length(Entry.IconData) > 0) then
    AppendBytes(Payload, BuildChunk(ID_ICON, Entry.IconData));
  Result := BuildChunk(ID_APP, Payload);
end;

function BuildAppsList(const Entries: TAppEntryArray): TBytes;
var
  Payload: TBytes;
  i: Integer;
begin
  Payload := FourCCBytes(ID_APPS);
  for i := 0 to High(Entries) do
    AppendBytes(Payload, BuildAppChunk(Entries[i]));
  Result := BuildChunk(ID_LIST, Payload);
end;

function BuildHederChunk(AppCount: Word): TBytes;
var
  Hder: TLauncherHeader;
  Payload: TBytes;
begin
  Hder.Version := 1;
  Hder.AppCount := AppCount;
  Hder.Flags := 0;
  SetLength(Payload, SizeOf(Hder));
  Move(Hder, Payload[0], SizeOf(Hder));
  Result := BuildChunk(ID_HDER, Payload);
end;

function SerializeLauncherEntries(const Entries: TAppEntryArray): TBytes;
var
  FormBody: TBytes;
  RootHead: TRIFFHeader;
  RootBytes: TBytes;
begin
  SetLength(FormBody, 0);
  AppendBytes(FormBody, BuildHederChunk(Length(Entries)));
  AppendBytes(FormBody, BuildAppsList(Entries));

  RootHead.RIFFID := ID_RIFF;
  RootHead.FormType := ID_RCLF;
  { FileSize = total file size - 8; total = 8 (RIFF id+size) + 4 (form
    type) + FormBody. }
  RootHead.FileSize := 4 + Length(FormBody);

  SetLength(RootBytes, 8); { ID + Size, written manually since FormType sits between them }
  Move(RootHead.RIFFID, RootBytes[0], SizeOf(FourCC));
  Move(RootHead.FileSize, RootBytes[4], SizeOf(LongInt));
  AppendBytes(RootBytes, FourCCBytes(RootHead.FormType));
  AppendBytes(RootBytes, FormBody);

  Result := RootBytes;
end;

procedure WriteLauncherEntries(const Entries: TAppEntryArray; Stream: TStream);
var
  Bytes: TBytes;
begin
  Bytes := SerializeLauncherEntries(Entries);
  if Length(Bytes) > 0 then
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
end;

end.
