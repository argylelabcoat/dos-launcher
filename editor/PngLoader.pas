unit PngLoader;

{ Loads a PNG file and reduces it to the 32x32/16-VGA-color TIndexGrid
  IconConvert.EncodeIconPCX expects, without any LCL dependency -- uses
  FPC's own fcl-image package (fpImage/FPReadPNG) instead of the LCL's
  TPicture, so this unit works in a plain console program. Mirrors
  MainForm.pas's TPicture->StretchDraw->QuantizeColor flow: nearest-
  neighbor resize (fitting for pixel icons, and the simplest correct
  thing fcl-image gives us without pulling in its canvas machinery)
  followed by per-pixel QuantizeColor. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, FPImage, FPReadPNG, IconConvert;

{ Loads FileName, nearest-neighbor-resizes to 32x32, and quantizes every
  pixel to the nearest of the 16 standard VGA colors. Pixels with partial
  alpha are composited against black (alpha 0 == fully transparent ==
  pure black) before quantizing, since PCX/VGA has no alpha channel.
  Returns False (ErrMsg set) if the file can't be read as a PNG. }
function LoadAndQuantizePngTo32x32(const FileName: string; out Pixels: TIndexGrid; out ErrMsg: string): Boolean;

implementation

function LoadAndQuantizePngTo32x32(const FileName: string; out Pixels: TIndexGrid; out ErrMsg: string): Boolean;
var
  Img: TFPMemoryImage;
  Reader: TFPReaderPNG;
  ox, oy, sx, sy: Integer;
  Color: TFPColor;
  R, G, B: Byte;
  Alpha: Word;
begin
  Result := False;
  ErrMsg := '';
  FillChar(Pixels, SizeOf(Pixels), 0);

  if not FileExists(FileName) then
  begin
    ErrMsg := Format('icon file not found: %s', [FileName]);
    Exit;
  end;

  Img := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  try
    try
      Img.LoadFromFile(FileName, Reader);
    except
      on E: Exception do
      begin
        ErrMsg := Format('failed to read "%s" as PNG: %s', [FileName, E.Message]);
        Exit;
      end;
    end;

    if (Img.Width <= 0) or (Img.Height <= 0) then
    begin
      ErrMsg := Format('"%s" decoded to an empty image', [FileName]);
      Exit;
    end;

    for oy := 0 to ICON_HEIGHT - 1 do
    begin
      sy := (oy * Img.Height) div ICON_HEIGHT;
      for ox := 0 to ICON_WIDTH - 1 do
      begin
        sx := (ox * Img.Width) div ICON_WIDTH;
        Color := Img.Colors[sx, sy];
        { TFPColor channels are 16-bit (0..65535); composite against
          black by alpha before dropping to 8-bit for quantization. }
        Alpha := Color.Alpha;
        R := ((LongInt(Color.Red) * Alpha) div 65535) shr 8;
        G := ((LongInt(Color.Green) * Alpha) div 65535) shr 8;
        B := ((LongInt(Color.Blue) * Alpha) div 65535) shr 8;
        Pixels[oy * ICON_WIDTH + ox] := QuantizeColor(R, G, B);
      end;
    end;

    Result := True;
  finally
    Reader.Free;
    Img.Free;
  end;
end;

end.
