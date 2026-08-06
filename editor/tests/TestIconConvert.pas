unit TestIconConvert;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, IconConvert;

type
  TTestIconConvert = class(TTestCase)
  published
    procedure QuantizeExactPaletteColorsRoundTrip;
    procedure QuantizeNearestColorPicksClosest;
    procedure EncodeProducesValidPCXHeader;
    procedure EncodeDecodeRoundTripMatchesSourcePixels;
    procedure SolidColorImageRoundTrips;
    procedure AllSixteenColorsRoundTrip;
  end;

implementation

procedure TTestIconConvert.QuantizeExactPaletteColorsRoundTrip;
var
  i: Integer;
begin
  for i := 0 to 15 do
    AssertEquals('exact palette RGB should quantize back to its own index',
      i, QuantizeColor(VGA_PALETTE[i].R, VGA_PALETTE[i].G, VGA_PALETTE[i].B));
end;

procedure TTestIconConvert.QuantizeNearestColorPicksClosest;
begin
  { Pure white should map to White (15), pure black to Black (0). }
  AssertEquals(15, QuantizeColor(255, 255, 255));
  AssertEquals(0, QuantizeColor(0, 0, 0));
  { A color very close to LightGreen (85,255,85) should map to index 10. }
  AssertEquals(10, QuantizeColor(90, 250, 90));
end;

procedure TTestIconConvert.EncodeProducesValidPCXHeader;
var
  Pixels: TIndexGrid;
  PCX: TBytes;
begin
  FillChar(Pixels, SizeOf(Pixels), 0);
  PCX := EncodeIconPCX(Pixels);

  AssertTrue('PCX must be at least the 128-byte header', Length(PCX) >= PCX_HEADER_SIZE);
  AssertEquals('Manufacturer byte = $0A', $0A, PCX[0]);
  AssertEquals('NPlanes offset (byte 65) = 4', 4, PCX[65]);
end;

procedure TTestIconConvert.EncodeDecodeRoundTripMatchesSourcePixels;
var
  Pixels, Decoded: TIndexGrid;
  PCX: TBytes;
  i: Integer;
  Ok: Boolean;
begin
  for i := 0 to ICON_PIXEL_COUNT - 1 do
    Pixels[i] := i mod 16;

  PCX := EncodeIconPCX(Pixels);
  Ok := DecodeIconPCX(PCX, Decoded);
  AssertTrue('decode should succeed on our own encoder output', Ok);

  for i := 0 to ICON_PIXEL_COUNT - 1 do
    AssertEquals('pixel ' + IntToStr(i) + ' should round-trip exactly', Pixels[i], Decoded[i]);
end;

procedure TTestIconConvert.SolidColorImageRoundTrips;
var
  Pixels, Decoded: TIndexGrid;
  PCX: TBytes;
  i: Integer;
begin
  for i := 0 to ICON_PIXEL_COUNT - 1 do
    Pixels[i] := 4; { solid red -- exercises the RLE long-run path }

  PCX := EncodeIconPCX(Pixels);
  AssertTrue(DecodeIconPCX(PCX, Decoded));
  for i := 0 to ICON_PIXEL_COUNT - 1 do
    AssertEquals(4, Decoded[i]);

  { A solid-color 32x32 image should compress well under RLE. }
  AssertTrue('RLE should shrink a solid-color image well below raw bitmap size',
    Length(PCX) < PCX_HEADER_SIZE + (32 * 32));
end;

procedure TTestIconConvert.AllSixteenColorsRoundTrip;
var
  Pixels, Decoded: TIndexGrid;
  PCX: TBytes;
  x, y: Integer;
begin
  for y := 0 to 31 do
    for x := 0 to 31 do
      Pixels[y * 32 + x] := (x + y) mod 16; { diagonal stripes: forces plenty of run breaks }

  PCX := EncodeIconPCX(Pixels);
  AssertTrue(DecodeIconPCX(PCX, Decoded));
  for y := 0 to 31 do
    for x := 0 to 31 do
      AssertEquals(Pixels[y * 32 + x], Decoded[y * 32 + x]);
end;

initialization
  RegisterTest(TTestIconConvert);
end.
