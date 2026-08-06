program PCX16Decoder;

uses Crt, Graph;

type
  TPCXHeader = record
    Manufacturer : Byte;       { Must be $0A }
    Version      : Byte;
    Encoding     : Byte;       { 1 = RLE }
    BitsPerPixel : Byte;       { Usually 1 for 16-color planar }
    XMin, YMin   : Word;
    XMax, YMax   : Word;
    HDpi, VDpi   : Word;
    Palette      : array[0..47] of Byte; { 16 RGB triplets }
    Reserved     : Byte;
    NPlanes      : Byte;       { 4 for 16-color }
    BytesPerLine : Word;       { Bytes per scanline plane }
    PaletteInfo  : Word;
    Padding      : array[0..57] of Byte; { Total struct = 128 bytes }
  end;

var
  Header : TPCXHeader;
  F      : file;
  Gd, Gm : Integer;

procedure SetVgaPalette(Index: Integer; R, G, B: Byte);
begin
  Port[$3C8] := Index;
  Port[$3C9] := R shr 2; { Scale 0-255 down to VGA 0-63 DAC range }
  Port[$3C9] := G shr 2;
  Port[$3C9] := B shr 2;
end;

procedure DecodePCX(FileName: string; StartX, StartY: Integer);
var
  ScanLineBuffer : array[0..3, 0..159] of Byte; { Plane, ByteIndex }
  Plane, LineByte, Bit, Mask : Integer;
  PixelX, PixelY, ImageWidth, ImageHeight : Integer;
  TotalBytesPerLine, BytesReadCount : Word;
  Value, RunLen, ColorIndex : Byte;
  
  procedure GetNextRLEByte(out B: Byte);
  begin
    BlockRead(F, B, 1);
  end;

begin
  Assign(F, FileName);
  {$I-} Reset(F, 1); {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('Error: Cannot open ', FileName);
    Exit;
  end;

  { 1. Read 128-byte Header }
  BlockRead(F, Header, SizeOf(Header));
  if (Header.Manufacturer <> $0A) or (Header.NPlanes <> 4) then
  begin
    WriteLn('Error: Unsupported file format (Must be 16-color 4-plane PCX).');
    Close(F);
    Exit;
  end;

  { Calculate image dimensions }
  ImageWidth  := (Header.XMax - Header.XMin) + 1;
  ImageHeight := (Header.YMax - Header.YMin) + 1;

  { 2. Apply Header Palette to VGA DAC }
  for Plane := 0 to 15 do
    SetVgaPalette(Plane, 
                  Header.Palette[Plane * 3], 
                  Header.Palette[Plane * 3 + 1], 
                  Header.Palette[Plane * 3 + 2]);

  TotalBytesPerLine := Header.NPlanes * Header.BytesPerLine;

  { 3. Decode Line by Line }
  for PixelY := 0 to ImageHeight - 1 do
  begin
    BytesReadCount := 0;
    
    { Decode one full scanline across all 4 planes }
    while BytesReadCount < TotalBytesPerLine do
    begin
      GetNextRLEByte(Value);
      
      { Check if it is an RLE count byte }
      if (Value and $C0) = $C0 then
      begin
        RunLen := Value and $3F;
        GetNextRLEByte(Value); { Read the actual pixel value }
      end
      else
        RunLen := 1;

      { Deposit bytes into planar scanline buffer }
      while (RunLen > 0) and (BytesReadCount < TotalBytesPerLine) do
      begin
        Plane := BytesReadCount div Header.BytesPerLine;
        LineByte := BytesReadCount mod Header.BytesPerLine;
        
        ScanLineBuffer[Plane, LineByte] := Value;
        Inc(BytesReadCount);
        Dec(RunLen);
      end;
    end;

    { 4. Reconstruct and render pixels for this scanline }
    for LineByte := 0 to Header.BytesPerLine - 1 do
    begin
      for Bit := 7 downto 0 do
      begin
        PixelX := (LineByte * 8) + (7 - Bit);
        if PixelX < ImageWidth then
        begin
          Mask := 1 shl Bit;
          
          { Extract bit from each plane to construct 4-bit color index }
          ColorIndex := 0;
          if (ScanLineBuffer[0, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 1; { Red/Plane 0 }
          if (ScanLineBuffer[1, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 2; { Green/Plane 1 }
          if (ScanLineBuffer[2, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 4; { Blue/Plane 2 }
          if (ScanLineBuffer[3, LineByte] and Mask) <> 0 then ColorIndex := ColorIndex or 8; { Intensity/Plane 3 }

          PutPixel(StartX + PixelX, StartY + PixelY, ColorIndex);
        end;
      end;
    end;
  end;

  Close(F);
end;

begin
  Gd := VGA;
  Gm := VGAHi; { 640x480 16-color }
  InitGraph(Gd, Gm, '');

  if GraphResult <> grOk then
  begin
    WriteLn('Graphics error: ', GraphErrorMsg(GraphResult));
    Halt(1);
  end;

  DecodePCX('IMAGE.PCX', 10, 10);

  ReadLn;
  CloseGraph;
end.
