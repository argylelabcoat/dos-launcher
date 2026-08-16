unit RiffBgiIcon;

interface

uses Graph, RiffLauncher;

{ Decodes a PCX stream inside a RIFF 'ICON' chunk into a BGI PutImage buffer }
function LoadRiffIconToBGI(var F: file; ChunkSize: LongInt): Pointer;

{ Helper to free a previously loaded BGI icon buffer }
procedure FreeBgiIcon(pIcon: Pointer);

implementation

type
  TPCXHeader = record
    Manufacturer : Byte;       { $0A }
    Version      : Byte;
    Encoding     : Byte;       { 1 = RLE }
    BitsPerPixel : Byte;       { 1 }
    XMin, YMin   : Word;
    XMax, YMax   : Word;
    HDpi, VDpi   : Word;
    Palette      : array[0..47] of Byte;
    Reserved     : Byte;
    NPlanes      : Byte;       { 4 }
    BytesPerLine : Word;       { 4 bytes per plane for 32px width }
    PaletteInfo  : Word;
    Padding      : array[0..57] of Byte;
  end;

  { 516-byte BGI PutImage buffer, indexed byte-by-byte while decoding. }
  PBgiByteBuffer = ^TBgiByteBuffer;
  TBgiByteBuffer = array[0..515] of Byte;

procedure FreeBgiIcon(pIcon: Pointer);
begin
  if pIcon <> nil then
    FreeMem(pIcon, 516); { 516 bytes for 32x32 16-color BGI buffer }
end;

function LoadRiffIconToBGI(var F: file; ChunkSize: LongInt): Pointer;
var
  Header            : TPCXHeader;
  pBgiBuffer        : Pointer;
  pByteArray        : PBgiByteBuffer;
  ScanLineBuffer    : array[0..3, 0..3] of Byte; { 4 planes x 4 bytes per plane }
  Plane, LineByte   : Integer;
  PixelY, ImageWidth, ImageHeight : Integer;
  TotalBytesPerLine, BytesReadCount : Word;
  Value, RunLen     : Byte;
  BgiOffset         : Word;

  procedure GetNextByte(var B: Byte);
  begin
    BlockRead(F, B, 1);
  end;

begin
  LoadRiffIconToBGI := nil;

  { 1. Validate PCX Header inside RIFF Chunk }
  if ChunkSize < SizeOf(TPCXHeader) then Exit;
  
  BlockRead(F, Header, SizeOf(Header));
  if (Header.Manufacturer <> $0A) or (Header.NPlanes <> 4) then Exit;

  ImageWidth  := (Header.XMax - Header.XMin) + 1;
  ImageHeight := (Header.YMax - Header.YMin) + 1;

  { Ensure image is 32x32 }
  if (ImageWidth <> 32) or (ImageHeight <> 32) then Exit;

  { BytesPerLine must be exactly 4 for a 32px-wide 1bpp image (32/8=4).
    A larger value would overflow the fixed 516-byte BGI buffer. }
  if Header.BytesPerLine <> 4 then Exit;

  { 2. Allocate Heap Memory for 32x32 16-color BGI Image Buffer (516 Bytes) }
  GetMem(pBgiBuffer, 516);
  pByteArray := pBgiBuffer;

  { Zero the buffer so a short/truncated RLE stream renders as black (color 0)
    instead of uninitialized heap garbage that shows as random colored pixels. }
  FillChar(pBgiBuffer^, 516, 0);

  { 3. Initialize BGI Header (Width - 1, Height - 1) }
  pByteArray^[0] := 31; { Width - 1 (Low Byte) }
  pByteArray^[1] := 0;  { Width - 1 (High Byte) }
  pByteArray^[2] := 31; { Height - 1 (Low Byte) }
  pByteArray^[3] := 0;  { Height - 1 (High Byte) }

  BgiOffset := 4; { Start writing pixel data past the 4-byte header }
  TotalBytesPerLine := Header.NPlanes * Header.BytesPerLine; { 4 * 4 = 16 bytes }

  { 4. Decode PCX RLE Scanlines directly into BGI Bitplane layout }
  for PixelY := 0 to ImageHeight - 1 do
  begin
    BytesReadCount := 0;

    { Decode one scanline across all 4 bitplanes }
    while BytesReadCount < TotalBytesPerLine do
    begin
      GetNextByte(Value);

      if (Value and $C0) = $C0 then
      begin
        RunLen := Value and $3F;
        GetNextByte(Value);
      end
      else
        RunLen := 1;

      while (RunLen > 0) and (BytesReadCount < TotalBytesPerLine) do
      begin
        Plane := BytesReadCount div Header.BytesPerLine;
        LineByte := BytesReadCount mod Header.BytesPerLine;

        ScanLineBuffer[Plane, LineByte] := Value;
        Inc(BytesReadCount);
        Dec(RunLen);
      end;
    end;

    { 5. Copy scanline bitplanes straight into BGI memory buffer.
         BGI stores VGA 16-color scanlines sequentially as Plane0, Plane1, Plane2, Plane3 }
    for Plane := 0 to 3 do
    begin
      for LineByte := 0 to Header.BytesPerLine - 1 do
      begin
        pByteArray^[BgiOffset] := ScanLineBuffer[Plane, LineByte];
        Inc(BgiOffset);
      end;
    end;
  end;

  LoadRiffIconToBGI := pBgiBuffer;
end;

end.
