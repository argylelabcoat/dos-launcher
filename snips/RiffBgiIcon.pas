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

  { FPC's Graph unit does NOT use the classic Borland BGI packed-bitplane
    image format. Per DefaultGetImage/DefaultPutImage in
    packages/graph/src/inc/graph.inc, the buffer PutImage expects is:
      - a 12-byte header: three LongInts (Width, Height, Reserved) --
        NOT the 4-byte "Width-1/Height-1 word pair" real BGI uses;
      - pixel data as one Word (raw color index) per pixel, raster
        order -- NOT 1-bit-per-plane packed bitplanes.
    Modeled here as a single Word array overlaying the whole buffer
    (words 0..2 double as the LongInt header via a second typed view at
    the same address), mirroring how graph.inc itself accesses it. }

const
  BGI_IMG_W          = 32;
  BGI_IMG_H          = 32;
  BGI_HEADER_WORDS   = 6; { 3 LongInts }
  BGI_PIXEL_COUNT    = BGI_IMG_W * BGI_IMG_H;
  BGI_BUFFER_WORDS   = BGI_HEADER_WORDS + BGI_PIXEL_COUNT;
  BGI_BUFFER_BYTES   = BGI_BUFFER_WORDS * 2; { 2060; SizeOf(Word) }

type
  PBgiWordBuffer = ^TBgiWordBuffer;
  TBgiWordBuffer = array[0..BGI_BUFFER_WORDS - 1] of Word;

  PBgiHeaderView = ^TBgiHeaderView;
  TBgiHeaderView = array[0..2] of LongInt;

procedure FreeBgiIcon(pIcon: Pointer);
begin
  if pIcon <> nil then
    FreeMem(pIcon, BGI_BUFFER_BYTES);
end;

function LoadRiffIconToBGI(var F: file; ChunkSize: LongInt): Pointer;
var
  Header            : TPCXHeader;
  pBgiBuffer        : Pointer;
  pWordArray        : PBgiWordBuffer;
  pHeaderView       : PBgiHeaderView;
  ScanLineBuffer    : array[0..3, 0..3] of Byte; { 4 planes x 4 bytes per plane }
  Plane, LineByte   : Integer;
  PixelX, PixelY, ImageWidth, ImageHeight : Integer;
  TotalBytesPerLine, BytesReadCount : Word;
  Value, RunLen     : Byte;
  ColorIndex        : Byte;
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

  { BytesPerLine must be exactly 4 for a 32px-wide 1bpp image (32/8=4);
    ScanLineBuffer below is sized for exactly that. }
  if Header.BytesPerLine <> 4 then Exit;

  { 2. Allocate Heap Memory for the FPC Graph-unit-format Image Buffer }
  GetMem(pBgiBuffer, BGI_BUFFER_BYTES);
  pWordArray  := pBgiBuffer;
  pHeaderView := pBgiBuffer;

  { Zero the buffer so a short/truncated RLE stream renders as black (color 0)
    instead of uninitialized heap garbage that shows as random colored pixels. }
  FillChar(pBgiBuffer^, BGI_BUFFER_BYTES, 0);

  { 3. Initialize the 12-byte (Width, Height, Reserved) LongInt header. }
  pHeaderView^[0] := BGI_IMG_W;
  pHeaderView^[1] := BGI_IMG_H;
  pHeaderView^[2] := 0;

  BgiOffset := BGI_HEADER_WORDS; { Start writing pixel words past the header }
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

    { 5. Combine the 4 decoded 1bpp planes into one chunky color-index Word
         per pixel (standard VGA planar-to-chunky: bit N of the pixel's
         4-bit color index comes from plane N's bit for that pixel),
         written left-to-right -- the raster-order format PutImage expects. }
    for PixelX := 0 to ImageWidth - 1 do
    begin
      ColorIndex := 0;
      for Plane := 0 to Header.NPlanes - 1 do
        if (ScanLineBuffer[Plane, PixelX shr 3] and ($80 shr (PixelX and 7))) <> 0 then
          ColorIndex := ColorIndex or (1 shl Plane);
      pWordArray^[BgiOffset] := ColorIndex;
      Inc(BgiOffset);
    end;
  end;

  LoadRiffIconToBGI := pBgiBuffer;
end;

end.
