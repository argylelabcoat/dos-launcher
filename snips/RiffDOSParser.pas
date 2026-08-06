program RiffDOSParser;

uses RiffLauncher;

var
  F: file;
  RootHead: TRIFFHeader;
  Chunk: TRIFFChunkHeader;
  Hder: TLauncherHeader;
  AppInfo: TAppInfo;
  ListType: FourCC;
  { 512 raw bytes (4 planes x 4 bytes/line x 32 lines) can expand up to 2x
    under worst-case RLE (every byte needs a 2-byte escape), so size for the
    legitimate worst case rather than the typical case. }
  IconBuf: array[1..1024] of Byte;

procedure SkipChunk(var Size: LongInt);
begin
  { Account for RIFF 2-byte word padding rule }
  if (Size mod 2) <> 0 then Inc(Size);
  Seek(F, FilePos(F) + Size);
end;

{ Reads exactly Count bytes into Buf, guarded against I/O errors and short
  reads (e.g. a file truncated mid-chunk). Returns False on any failure
  instead of raising a runtime error, so the caller can stop parsing
  gracefully and keep whatever was already loaded -- per the rclf-container
  spec's truncation-handling requirement. }
function SafeRead(var Buf; Count: Word): Boolean;
var
  Got: Word;
begin
  {$I-}
  BlockRead(F, Buf, Count, Got);
  {$I+}
  SafeRead := (IOResult = 0) and (Got = Count);
end;

begin
  Assign(F, 'LAUNCHER.DAT');
  {$I-} Reset(F, 1); {$I+}
  if IOResult <> 0 then Halt(1);

  { Read & verify RIFF Root }
  if not SafeRead(RootHead, SizeOf(RootHead)) then
  begin
    WriteLn('Invalid RIFF launcher file.');
    Close(F);
    Halt(1);
  end;
  if not (SameFourCC(RootHead.RIFFID, ID_RIFF) and
          SameFourCC(RootHead.FormType, ID_RCLF)) then
  begin
    WriteLn('Invalid RIFF launcher file.');
    Close(F);
    Halt(1);
  end;

  WriteLn('RIFF Container Verified. Parsing Chunks...');

  { Process Chunks }
  while not EOF(F) do
  begin
    if not SafeRead(Chunk, SizeOf(Chunk)) then Break;

    if SameFourCC(Chunk.ID, ID_HDER) then
    begin
      if not SafeRead(Hder, SizeOf(Hder)) then Break;
      WriteLn('App Count: ', Hder.AppCount);
    end
    else if SameFourCC(Chunk.ID, ID_LIST) then
    begin
      { Read the Sub-Type FOURCC }
      if not SafeRead(ListType, SizeOf(ListType)) then Break;
      { Continue loop to read embedded sub-chunks naturally }
    end
    else if SameFourCC(Chunk.ID, ID_APP) then
    begin
      { Flat chunk, not a nested LIST: no subtype FourCC to read. Its payload
        is INFO + optional ICON, read naturally as the next chunks in the
        stream, same as a LIST's children. }
      WriteLn('--- App Entry ---');
    end
    else if SameFourCC(Chunk.ID, ID_INFO) then
    begin
      if not SafeRead(AppInfo, SizeOf(AppInfo)) then Break;
      WriteLn('Loaded App: ', AppInfo.Title);
    end
    else if SameFourCC(Chunk.ID, ID_ICON) then
    begin
      { ICON payloads are variable-length RLE-compressed PCX data, not a
        fixed size: read exactly the chunk's declared size (clamped to the
        buffer) and honor the RIFF alignment pad byte when it's odd. }
      if Chunk.Size <= SizeOf(IconBuf) then
      begin
        if not SafeRead(IconBuf, Chunk.Size) then Break;
        WriteLn('  [Icon Data Streamed: ', Chunk.Size, ' bytes]');
        if (Chunk.Size mod 2) <> 0 then Seek(F, FilePos(F) + 1);
      end
      else
      begin
        WriteLn('  [Icon chunk too large to buffer (', Chunk.Size, ' bytes) - skipping]');
        SkipChunk(Chunk.Size);
      end;
    end
    else
    begin
      { Unknown chunk! Safely skip it }
      SkipChunk(Chunk.Size);
    end;
  end;

  Close(F);
end.
