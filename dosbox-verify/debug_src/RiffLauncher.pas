unit RiffLauncher;

interface

{$IFDEF FPC}
  {$PACKRECORDS 1}
{$ENDIF}

type
  FourCC = array[1..4] of Char;

  { Standard 8-byte RIFF Chunk Header }
  TRIFFChunkHeader = packed record
    ID   : FourCC;
    Size : LongInt; { Little-Endian 32-bit integer }
  end;

  { Main 12-byte RIFF Root File Header }
  TRIFFHeader = packed record
    RIFFID   : FourCC;  { Must be 'RIFF' }
    FileSize : LongInt; { File size - 8 }
    FormType : FourCC;  { Must be 'RCLF' }
  end;

  { Payload for 'HDER' chunk }
  TLauncherHeader = packed record
    Version  : Word;    { Format version, e.g., 1 }
    AppCount : Word;    { Number of apps }
    Flags    : Word;    { Reserved flags }
  end;

  { Payload for 'INFO' chunk }
  TAppInfo = packed record
    Title    : string[40];
    Desc     : string[70];
    ExecPath : string[64];
    Args     : string[64];
    Flags    : Word;    { Bit 0: Pause on exit, Bit 1: Clear screen }
  end;

const
  ID_RIFF : FourCC = 'RIFF';
  ID_RCLF : FourCC = 'RCLF';
  ID_LIST : FourCC = 'LIST';
  ID_HDER : FourCC = 'HDER';
  ID_APPS : FourCC = 'APPS';
  ID_APP  : FourCC = 'APP ';
  ID_INFO : FourCC = 'INFO';
  ID_ICON : FourCC = 'ICON';

function SameFourCC(A, B: FourCC): Boolean;

implementation

function SameFourCC(A, B: FourCC): Boolean;
begin
  SameFourCC := (A[1] = B[1]) and (A[2] = B[2]) and 
                (A[3] = B[3]) and (A[4] = B[4]);
end;

end.
