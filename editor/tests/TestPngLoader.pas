unit TestPngLoader;

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, IconConvert, PngLoader;

type
  TTestPngLoader = class(TTestCase)
  private
    function FixturePath(const FileName: string): string;
  published
    procedure LoadsAndNearestNeighborResizesQuadrants;
    procedure SolidColorImageResizesToUniformGrid;
    procedure MissingFileReturnsError;
  end;

implementation

function TTestPngLoader.FixturePath(const FileName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + FileName;
  if not FileExists(Result) then
    { Running from the source tree (fpc TestRunner.lpr) rather than an
      installed location -- fixtures sit next to this .pas file. }
    Result := 'fixtures' + PathDelim + FileName;
end;

procedure TTestPngLoader.LoadsAndNearestNeighborResizesQuadrants;
var
  Pixels: TIndexGrid;
  ErrMsg: string;
  Ok: Boolean;
begin
  Ok := LoadAndQuantizePngTo32x32(FixturePath('quad.png'), Pixels, ErrMsg);
  AssertTrue('load should succeed: ' + ErrMsg, Ok);
  { quad.png is 8x8: red top-left, blue top-right, white bottom-left,
    black bottom-right quadrants -- a clean 4x nearest-neighbor scale to
    32x32 keeps each corner pixel within its source quadrant. }
  AssertEquals('top-left corner should be Red (4)', 4, Pixels[0 * 32 + 0]);
  AssertEquals('top-right corner should be Blue (1)', 1, Pixels[0 * 32 + 31]);
  AssertEquals('bottom-left corner should be White (15)', 15, Pixels[31 * 32 + 0]);
  AssertEquals('bottom-right corner should be Black (0)', 0, Pixels[31 * 32 + 31]);
end;

procedure TTestPngLoader.SolidColorImageResizesToUniformGrid;
var
  Pixels: TIndexGrid;
  ErrMsg: string;
  i: Integer;
begin
  AssertTrue(LoadAndQuantizePngTo32x32(FixturePath('solid_brown.png'), Pixels, ErrMsg));
  for i := 0 to ICON_PIXEL_COUNT - 1 do
    AssertEquals('every pixel of a solid-color source should quantize to the same index',
      6 { Brown }, Pixels[i]);
end;

procedure TTestPngLoader.MissingFileReturnsError;
var
  Pixels: TIndexGrid;
  ErrMsg: string;
begin
  AssertFalse(LoadAndQuantizePngTo32x32('does-not-exist-anywhere.png', Pixels, ErrMsg));
  AssertTrue('ErrMsg should be set on failure', ErrMsg <> '');
end;

initialization
  RegisterTest(TTestPngLoader);
end.
