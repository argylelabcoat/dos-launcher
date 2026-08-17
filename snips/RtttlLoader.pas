unit RtttlLoader;

{ RtttlLoader - parses an RTTTL (Ring Tone Text Transfer Language) string
  into the shared TMelody intermediate format.

  RTTTL format reference (the classic Nokia ringtone text format):

      <name>:<defaults>:<notes>

  The three sections are separated by the first TWO colons, not by commas:
  the defaults and notes sections are themselves comma-separated, so colons
  are the only reliable section delimiter.

    name     - free text, ignored by this loader.
    defaults - comma-separated key=value pairs:
                 d=duration   note length 1..32 (default 4)
                 o=octave     octave 4..8   (default 5)
                 b=beats      BPM 25..900   (default 63)
    notes    - comma-separated note tokens of the form
                 [duration][pitch][accidental][octave][.]
               duration    1,2,4,8,16,32 (whole=1 .. thirty-second=32)
               pitch       A-G (note) or P (pause/rest)
               accidental  # (sharp) or b (flat)
               octave      4-8, overrides the default o
               .           dotted - multiplies the duration by 1.5

  Parsing is deliberately LENIENT to survive real-world dialect variation:
  unknown default keys are ignored, out-of-range values clamp to their
  bounds, and a note token that does not match the grammar is skipped
  rather than treated as a fatal error. The only hard failures are a string
  with fewer than two colons and a notes section that yields zero notes. A
  melody that fills all MAX_NOTES entries is truncated and still reported
  as success - truncation is valid, not an error.

  Duration math uses LongInt because 60000 * 4 = 240000 overflows a 16-bit
  Integer/Word. Everything here is integer-only, heap-free, and short-string
  only. }

{$MODE TP}

interface

uses SpeakerMusic;

{ Parse an RTTTL string into Melody. Returns True on success (including
  truncation at MAX_NOTES), False on structural failure: fewer than two
  colons, or a notes section that yields zero notes. On False the melody is
  cleared and must not be played. }
function LoadRTTTL(const S: string; var Melody: TMelody): Boolean;

implementation

{ Extract leading decimal digits from Token starting at Pos. Advances Pos
  past the digits and returns the accumulated value. Returns False if no
  digit is present at Pos. The accumulator is capped so junk input of many
  digits cannot overflow a 16-bit Integer. }
function ScanDigits(const Token: string; var Pos: Integer; var Value: Integer): Boolean;
begin
  Value := 0;
  ScanDigits := False;
  while (Pos <= Length(Token)) and (Token[Pos] in ['0'..'9']) do
  begin
    if Value <= 10000 then
      Value := Value * 10 + (Ord(Token[Pos]) - Ord('0'));
    Inc(Pos);
    ScanDigits := True;
  end;
end;

{ RTTTL note lengths are the power-of-two set 1,2,4,8,16,32 only. }
function ValidDuration(V: Integer): Boolean;
begin
  ValidDuration := (V = 1) or (V = 2) or (V = 4) or (V = 8) or
                   (V = 16) or (V = 32);
end;

{ Parse the defaults section into the three default values. Unknown keys are
  ignored; out-of-range values clamp to bounds; a key with no numeric value
  is ignored. Always succeeds - defaults parsing is never a hard failure. }
procedure ParseDefaults(const Def: string; var DefDur, DefOct, DefBPM: Integer);
var
  n    : Integer;
  p    : Integer;
  Pair : string;
  Eq   : Integer;
  Key  : Char;
  Val  : Integer;
  i    : Integer;
begin
  DefDur := 4;
  DefOct := 5;
  DefBPM := 63;

  p := 1;
  n := Length(Def);
  while p <= n do
  begin
    { Slice one comma-separated pair, dropping spaces (lenient). }
    Pair := '';
    while (p <= n) and (Def[p] <> ',') do
    begin
      if Def[p] <> ' ' then Pair := Pair + Def[p];
      Inc(p);
    end;
    Inc(p);  { skip the comma }

    { A pair must look like 'k=v' (single-char key). }
    Eq := Pos('=', Pair);
    if Eq = 2 then
    begin
      Key := UpCase(Pair[1]);
      i := Eq + 1;
      if ScanDigits(Pair, i, Val) then
      begin
        case Key of
          'D': begin
                 if Val < 1  then Val := 1;
                 if Val > 32 then Val := 32;
                 DefDur := Val;
               end;
          'O': begin
                 if Val < 4 then Val := 4;
                 if Val > 8 then Val := 8;
                 DefOct := Val;
               end;
          'B': begin
                 if Val < 25  then Val := 25;
                 if Val > 900 then Val := 900;
                 DefBPM := Val;
               end;
        end;
      end;
    end;
  end;
end;

{ Parse one note token into a (Freq, Duration) pair. Sets Ok=False and leaves
  Freq/Duration undefined if the token does not match the note grammar; the
  caller skips such tokens (lenient). }
procedure ParseNote(const Token: string; DefDur, DefOct, BPM: Integer;
                    var Ok: Boolean; var Freq: Word; var Duration: Word);
var
  i      : Integer;
  Len    : Integer;
  Dur    : Integer;
  Oct    : Integer;
  Pitch  : Char;
  Acc    : Char;
  Dotted : Boolean;
  Name   : string;
  ms     : LongInt;
begin
  Ok := False;
  Len := Length(Token);
  i := 1;

  while (i <= Len) and (Token[i] = ' ') do Inc(i);
  if i > Len then Exit;

  Dur := DefDur;
  Oct := DefOct;
  Acc := #0;
  Dotted := False;

  { optional leading duration digits }
  if Token[i] in ['0'..'9'] then
  begin
    ScanDigits(Token, i, Dur);
    if not ValidDuration(Dur) then Exit;
  end;

  { pitch letter }
  if i > Len then Exit;
  Pitch := UpCase(Token[i]);
  if not (Pitch in ['A'..'G', 'P']) then Exit;
  Inc(i);

  { optional accidental: '#' sharp, 'b'/'B' flat }
  if (i <= Len) and ((Token[i] = '#') or (Token[i] = 'b') or (Token[i] = 'B')) then
  begin
    Acc := Token[i];
    Inc(i);
  end;

  { optional octave digits, clamped to the 4..8 RTTTL range }
  if (i <= Len) and (Token[i] in ['0'..'9']) then
  begin
    ScanDigits(Token, i, Oct);
    if Oct < 4 then Oct := 4;
    if Oct > 8 then Oct := 8;
  end;

  { optional dotted }
  if (i <= Len) and (Token[i] = '.') then
  begin
    Dotted := True;
    Inc(i);
  end;

  { anything left over (beyond trailing spaces) makes the token invalid }
  while (i <= Len) and (Token[i] = ' ') do Inc(i);
  if i <= Len then Exit;

  { resolve frequency: a pause is silence, otherwise look up the note }
  if Pitch = 'P' then
    Freq := 0
  else
  begin
    Name := Pitch;
    if Acc <> #0 then Name := Name + Acc;
    Freq := NoteFreq(Name, Oct);
    { Oct is clamped to 4..8 so the lookup always resolves; a 0 means the
      name/octave was rejected and the note is unusable. }
    if Freq = 0 then Exit;
  end;

  { resolve duration: LongInt because 60000 * 4 = 240000 overflows 16 bits }
  ms := (LongInt(60000) * 4) div (BPM * Dur);
  if Dotted then ms := (ms * 3) div 2;
  Duration := Word(ms);

  Ok := True;
end;

function LoadRTTTL(const S: string; var Melody: TMelody): Boolean;
var
  C1, C2   : Integer;
  Rest     : string;
  Defaults : string;
  Notes    : string;
  DefDur   : Integer;
  DefOct   : Integer;
  DefBPM   : Integer;
  n        : Integer;
  i        : Integer;
  Token    : string;
  Ok       : Boolean;
  Freq     : Word;
  Dur      : Word;
begin
  LoadRTTTL := False;
  ClearMelody(Melody);

  { Split into name:defaults:notes on the first two colons. }
  C1 := Pos(':', S);
  if C1 < 1 then Exit;

  Rest := Copy(S, C1 + 1, 255);
  C2 := Pos(':', Rest);
  if C2 < 1 then Exit;
  C2 := C2 + C1;

  Defaults := Copy(S, C1 + 1, C2 - C1 - 1);
  Notes    := Copy(S, C2 + 1, 255);

  ParseDefaults(Defaults, DefDur, DefOct, DefBPM);

  { Parse the notes section one comma-separated token at a time. }
  n := Length(Notes);
  i := 1;
  while i <= n do
  begin
    Token := '';
    while (i <= n) and (Notes[i] <> ',') do
    begin
      Token := Token + Notes[i];
      Inc(i);
    end;
    Inc(i);  { skip the comma }

    ParseNote(Token, DefDur, DefOct, DefBPM, Ok, Freq, Dur);
    if Ok then
    begin
      if not AddNote(Melody, Freq, Dur) then
      begin
        { melody full at MAX_NOTES: truncation is valid, not an error }
        LoadRTTTL := True;
        Exit;
      end;
    end;
  end;

  { success iff at least one note was produced }
  LoadRTTTL := (Melody.Count > 0);
end;

end.
