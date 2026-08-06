unit IconConvert;

{ 32x32 4-plane RLE PCX icon pipeline (design D4). Mirrors the bitplane
  and RLE logic of snips/RiffBgiIcon.pas (decode side) and
  snips/PCX16Decoder.pas (also decode side; used here as the reference
  for exact bit-to-color-index mapping) with no Graph/BGI dependency.
  EncodeIconPCX is the mirror-image (inverse) of that decode logic:
  16-VGA-palette-index pixels -> 4 planes -> RLE -> a spec-valid 128-byte
  PCX header + scanline data, byte-for-byte compatible with what those
  DOS units expect to read back.

  Full PNG/BMP/TPicture import glue is out of scope here (design D4 notes
  it's exercised by the GUI task); this unit exposes exactly the tested
  conversion core: pixel-index-grid <-> PCX bytes, plus RGB->palette-index
  quantization for feeding that core from a decoded image later. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils;

const
  ICON_WIDTH        = 32;
  ICON_HEIGHT       = 32;
  ICON_PIXEL_COUNT  = ICON_WIDTH * ICON_HEIGHT;
  PCX_NPLANES       = 4;
  PCX_BYTES_PER_LINE = ICON_WIDTH div 8; { 4 bytes/plane/scanline for 32px width }
  PCX_HEADER_SIZE   = 128;

type
  { Row-major 32x32 grid of 4-bit VGA palette indices (0..15). }
  TIndexGrid = array[0..ICON_PIXEL_COUNT - 1] of Byte;

  TPaletteRGB = record
    R, G, B: Byte;
  end;

const
  { Standard EGA/VGA 16-color palette, in the same order as Borland's Graph
    unit color constants (0=Black .. 15=White). Matches the RGB triplets a
    DOS PCX16Decoder-produced file's header would carry for this palette. }
  VGA_PALETTE: array[0..15] of TPaletteRGB = (
    (R:0;   G:0;   B:0),   { 0  Black }
    (R:0;   G:0;   B:170), { 1  Blue }
    (R:0;   G:170; B:0),   { 2  Green }
    (R:0;   G:170; B:170), { 3  Cyan }
    (R:170; G:0;   B:0),   { 4  Red }
    (R:170; G:0;   B:170), { 5  Magenta }
    (R:170; G:85;  B:0),   { 6  Brown }
    (R:170; G:170; B:170), { 7  LightGray }
    (R:85;  G:85;  B:85),  { 8  DarkGray }
    (R:85;  G:85;  B:255), { 9  LightBlue }
    (R:85;  G:255; B:85),  { 10 LightGreen }
    (R:85;  G:255; B:255), { 11 LightCyan }
    (R:255; G:85;  B:85),  { 12 LightRed }
    (R:255; G:85;  B:255), { 13 LightMagenta }
    (R:255; G:255; B:85),  { 14 Yellow }
    (R:255; G:255; B:255)  { 15 White }
  );

{ Nearest-color (Euclidean RGB distance) quantization to the standard
  16-color VGA palette. }
function QuantizeColor(R, G, B: Byte): Byte;

{ Encodes a 32x32 palette-index grid as a complete, spec-valid 4-plane
  1bpp RLE PCX byte stream (128-byte header + RLE scanline data),
  suitable to use directly as a RIFF 'ICON' chunk payload. }
function EncodeIconPCX(const Pixels: TIndexGrid): TBytes;

{ Inverse of EncodeIconPCX: decodes PCX bytes (as produced by
  EncodeIconPCX, or read back out of a RIFF 'ICON' chunk) into a 32x32
  palette-index grid. Returns False if the bytes are not a well-formed
  32x32 4-plane PCX. }
function DecodeIconPCX(const PCXBytes: TBytes; out Pixels: TIndexGrid): Boolean;

implementation

type
  { Byte-for-byte compatible with snips/RiffBgiIcon.pas's and
    snips/PCX16Decoder.pas's TPCXHeader (128 bytes total). }
  TPCXHeader = packed record
    Manufacturer : Byte;
    Version      : Byte;
    Encoding     : Byte;
    BitsPerPixel : Byte;
    XMin, YMin   : Word;
    XMax, YMax   : Word;
    HDpi, VDpi   : Word;
    Palette      : array[0..47] of Byte;
    Reserved     : Byte;
    NPlanes      : Byte;
    BytesPerLine : Word;
    PaletteInfo  : Word;
    Padding      : array[0..57] of Byte;
  end;

function QuantizeColor(R, G, B: Byte): Byte;
var
  i: Integer;
  dr, dg, db: Integer;
  Dist, BestDist: LongInt;
  BestIdx: Byte;
begin
  BestIdx := 0;
  BestDist := High(LongInt);
  for i := 0 to 15 do
  begin
    dr := Integer(R) - VGA_PALETTE[i].R;
    dg := Integer(G) - VGA_PALETTE[i].G;
    db := Integer(B) - VGA_PALETTE[i].B;
    Dist := LongInt(dr) * dr + LongInt(dg) * dg + LongInt(db) * db;
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestIdx := i;
    end;
  end;
  Result := BestIdx;
end;

{ RLE-encodes exactly one scanline's worth of raw plane bytes (16 bytes:
  4 planes x 4 bytes/plane), never letting a run cross the scanline
  boundary -- matching the DOS decoders, which reset their run/byte
  accounting per scanline and would otherwise silently drop the tail of
  an over-long run. }
procedure EncodeScanlineRLE(const Line: array of Byte; var Output: TBytes);
var
  i, RunLen: Integer;
  Val: Byte;
  OutLen: Integer;

  procedure Emit(B: Byte);
  begin
    SetLength(Output, OutLen + 1);
    Output[OutLen] := B;
    Inc(OutLen);
  end;

begin
  OutLen := Length(Output);
  i := 0;
  while i < Length(Line) do
  begin
    Val := Line[i];
    RunLen := 1;
    while (i + RunLen < Length(Line)) and (Line[i + RunLen] = Val) and (RunLen < 63) do
      Inc(RunLen);

    if (RunLen = 1) and ((Val and $C0) <> $C0) then
      Emit(Val)
    else
    begin
      Emit($C0 or RunLen);
      Emit(Val);
    end;

    Inc(i, RunLen);
  end;
end;

function EncodeIconPCX(const Pixels: TIndexGrid): TBytes;
var
  Header: TPCXHeader;
  HeaderBytes: TBytes;
  Body: TBytes;
  Planes: array[0..PCX_NPLANES - 1, 0..PCX_BYTES_PER_LINE - 1] of Byte;
  x, y, Plane, LineByte, BitPos, Mask: Integer;
  ColorIdx: Byte;
  ScanLine: array[0..(PCX_NPLANES * PCX_BYTES_PER_LINE) - 1] of Byte;
  i: Integer;
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Manufacturer := $0A;
  Header.Version := 5;
  Header.Encoding := 1;
  Header.BitsPerPixel := 1;
  Header.XMin := 0;
  Header.YMin := 0;
  Header.XMax := ICON_WIDTH - 1;
  Header.YMax := ICON_HEIGHT - 1;
  Header.HDpi := 300;
  Header.VDpi := 300;
  for i := 0 to 15 do
  begin
    Header.Palette[i * 3]     := VGA_PALETTE[i].R;
    Header.Palette[i * 3 + 1] := VGA_PALETTE[i].G;
    Header.Palette[i * 3 + 2] := VGA_PALETTE[i].B;
  end;
  Header.Reserved := 0;
  Header.NPlanes := PCX_NPLANES;
  Header.BytesPerLine := PCX_BYTES_PER_LINE;
  Header.PaletteInfo := 1;

  SetLength(HeaderBytes, SizeOf(Header));
  Move(Header, HeaderBytes[0], SizeOf(Header));

  SetLength(Body, 0);

  for y := 0 to ICON_HEIGHT - 1 do
  begin
    for Plane := 0 to PCX_NPLANES - 1 do
      for LineByte := 0 to PCX_BYTES_PER_LINE - 1 do
        Planes[Plane, LineByte] := 0;

    for x := 0 to ICON_WIDTH - 1 do
    begin
      ColorIdx := Pixels[y * ICON_WIDTH + x];
      LineByte := x div 8;
      BitPos := 7 - (x mod 8);
      Mask := 1 shl BitPos;
      if (ColorIdx and 1) <> 0 then Planes[0, LineByte] := Planes[0, LineByte] or Mask;
      if (ColorIdx and 2) <> 0 then Planes[1, LineByte] := Planes[1, LineByte] or Mask;
      if (ColorIdx and 4) <> 0 then Planes[2, LineByte] := Planes[2, LineByte] or Mask;
      if (ColorIdx and 8) <> 0 then Planes[3, LineByte] := Planes[3, LineByte] or Mask;
    end;

    for Plane := 0 to PCX_NPLANES - 1 do
      for LineByte := 0 to PCX_BYTES_PER_LINE - 1 do
        ScanLine[Plane * PCX_BYTES_PER_LINE + LineByte] := Planes[Plane, LineByte];

    EncodeScanlineRLE(ScanLine, Body);
  end;

  SetLength(Result, 0);
  Result := Copy(HeaderBytes, 0, Length(HeaderBytes));
  SetLength(Result, Length(Result) + Length(Body));
  if Length(Body) > 0 then
    Move(Body[0], Result[Length(HeaderBytes)], Length(Body));
end;

function DecodeIconPCX(const PCXBytes: TBytes; out Pixels: TIndexGrid): Boolean;
var
  Header: TPCXHeader;
  ImageWidth, ImageHeight: Integer;
  Pos: Integer;
  TotalBytesPerLine: Integer;
  BytesReadCount: Integer;
  Value, RunLen: Byte;
  Plane, LineByte, PixelY, PixelX, Bit, Mask: Integer;
  ScanLineBuffer: array[0..PCX_NPLANES - 1, 0..PCX_BYTES_PER_LINE - 1] of Byte;
  ColorIndex: Byte;

  function GetNextByte(out B: Byte): Boolean;
  begin
    if Pos >= Length(PCXBytes) then
    begin
      B := 0;
      Result := False;
      Exit;
    end;
    B := PCXBytes[Pos];
    Inc(Pos);
    Result := True;
  end;

begin
  Result := False;
  FillChar(Pixels, SizeOf(Pixels), 0);

  if Length(PCXBytes) < PCX_HEADER_SIZE then Exit;
  Move(PCXBytes[0], Header, SizeOf(Header));

  if (Header.Manufacturer <> $0A) or (Header.NPlanes <> PCX_NPLANES) then Exit;

  ImageWidth := (Header.XMax - Header.XMin) + 1;
  ImageHeight := (Header.YMax - Header.YMin) + 1;
  if (ImageWidth <> ICON_WIDTH) or (ImageHeight <> ICON_HEIGHT) then Exit;
  if Header.BytesPerLine <> PCX_BYTES_PER_LINE then Exit;

  Pos := PCX_HEADER_SIZE;
  TotalBytesPerLine := Header.NPlanes * Header.BytesPerLine;

  for PixelY := 0 to ImageHeight - 1 do
  begin
    BytesReadCount := 0;
    while BytesReadCount < TotalBytesPerLine do
    begin
      if not GetNextByte(Value) then Exit;

      if (Value and $C0) = $C0 then
      begin
        RunLen := Value and $3F;
        if not GetNextByte(Value) then Exit;
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

    for LineByte := 0 to Header.BytesPerLine - 1 do
    begin
      for Bit := 7 downto 0 do
      begin
        PixelX := (LineByte * 8) + (7 - Bit);
        if PixelX < ImageWidth then
        begin
          Mask := 1 shl Bit;
          ColorIndex := 0;
          if (ScanLineBuffer[0, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 1;
          if (ScanLineBuffer[1, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 2;
          if (ScanLineBuffer[2, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 4;
          if (ScanLineBuffer[3, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 8;
          Pixels[PixelY * ICON_WIDTH + PixelX] := ColorIndex;
        end;
      end;
    end;
  end;

  Result := True;
end;

end.
