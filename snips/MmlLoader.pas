unit MmlLoader;

{ MmlLoader — parses MML (Music Macro Language) source text into the shared
  TMelody intermediate format (see SpeakerMusic.pas).

  Supported command set (the common "baseline" used across NES/MSX trackers):
    A-G   note at the current octave; optional '#'/'+' (sharp) or '-'
          (flat) accidental, optional duration digits (1,2,4,8,16,32,64),
          optional '.' (dotted).
    R     rest (Freq = 0); optional duration digits and '.'.
    On    set octave (1-8, clamped). Default 4.
    Ln    set default note length (1,2,4,8,16,32,64). Default 4.
    Tn    set tempo in BPM (20-500, clamped). Default 120.
    <     octave down (clamped at 1).
    >     octave up (clamped at 8).
    &     tie: fold the NEXT note into the previous note's duration when
          they share the same pitch; ignored (and the flag cleared) when
          the pitches differ.
    .     dotted note (x 1.5), consumed inline by the note/rest handlers.

  Unsupported commands are skipped without error so real-world MML files
  that use dialect-specific features the PC speaker cannot reproduce still
  load:
    @     instrument  — command char + following digits discarded.
    v     volume      — command char + following digits discarded.
    $     macro       — command char + following digits discarded.
    [..]  loop        — the whole bracket body is discarded (not played).
    brace-enclosed grace notes — the whole body is discarded (not played).
  Whitespace and any other unrecognized character are skipped silently.

  Duration math uses LongInt because the numerator 60000 * 4 = 240000
  overflows a 16-bit Integer/Word (the 16-bit product wraps mod 65536 and
  produces garbage note lengths on the 8088):
    ms := (LongInt(60000) * 4) div (Tempo * lengthValue);
    if dotted then ms := (ms * 3) div 2;

  No heap, no exceptions, no floating point; short strings only. }
{$MODE TP}

interface

uses SpeakerMusic;

function LoadMML(const S: string; var Melody: TMelody): Boolean;

implementation

function LoadMML(const S: string; var Melody: TMelody): Boolean;
var
  i          : Integer;
  Ch         : Char;
  Octave     : Integer;
  CurLen     : Integer;   { current default note-length value (1,2,4,8,16,32,64) }
  Tempo      : Integer;   { current tempo in BPM (20-500) }
  PendingTie : Boolean;   { '&' seen; next note folds into previous if same pitch }
  LastIndex  : Integer;   { index of last emitted note in Melody.Notes, -1 = none }
  Stop       : Boolean;   { set when AddNote fails (melody full at MAX_NOTES) }
  NumVal     : Integer;
  Acc        : string[1]; { accidental mapped to NoteFreq form: '#' or 'b' }
  NameStr    : string[2]; { note letter + accidental, for NoteFreq }
  LenValue   : Integer;
  Dotted     : Boolean;

  { Reads a run of decimal digits starting at Pos and returns its value.
    Pos is advanced past the digits (left unchanged if none). }
  function ReadNumber(var Pos: Integer): Integer;
  var
    v : Integer;
  begin
    v := 0;
    while (Pos <= Length(S)) and (S[Pos] in ['0'..'9']) do
    begin
      v := v * 10 + (Ord(S[Pos]) - Ord('0'));
      Inc(Pos);
    end;
    ReadNumber := v;
  end;

  { True if v is a valid note-length value (a power of two 1..64). }
  function ValidLen(v: Integer): Boolean;
  begin
    ValidLen := (v = 1) or (v = 2) or (v = 4) or (v = 8) or
                (v = 16) or (v = 32) or (v = 64);
  end;

  { True if c (case-insensitive) begins one of the recognized MML commands.
    Used to delimit the argument of an unsupported command: skip everything
    until the next recognized command char. }
  function IsCommand(c: Char): Boolean;
  begin
    c := UpCase(c);
    IsCommand := (c in ['A'..'G', 'R', 'O', 'L', 'T', '<', '>', '&',
                        '@', 'V', '$', '[', ']', '{', '}']);
  end;

  { Resolve duration, apply tie handling, and emit one note into Melody.
    The tie flag is consumed here whether or not the notes merge. }
  procedure Emit(Freq: Word; LenValue: Integer; Dotted: Boolean);
  var
    ms : LongInt;
  begin
    ms := (LongInt(60000) * 4) div (Tempo * LenValue);
    if Dotted then ms := (ms * 3) div 2;

    if PendingTie then
    begin
      PendingTie := False;
      if (LastIndex >= 0) and (Melody.Notes[LastIndex].Freq = Freq) then
      begin
        { Same pitch: fold this note's duration into the previous note and
          emit nothing — ties chain, so the previous note keeps growing. }
        Melody.Notes[LastIndex].Duration :=
          Melody.Notes[LastIndex].Duration + Word(ms);
        Exit;
      end;
      { Different pitch: fall through and emit normally (tie ignored). }
    end;

    if not AddNote(Melody, Freq, Word(ms)) then
    begin
      Stop := True;   { melody full at MAX_NOTES: truncate, not an error }
      Exit;
    end;
    LastIndex := Melody.Count - 1;
  end;

begin
  Melody.Count := 0;
  Octave     := 4;
  CurLen     := 4;
  Tempo      := 120;
  PendingTie := False;
  LastIndex  := -1;
  Stop       := False;

  i := 1;
  while (i <= Length(S)) and (not Stop) do
  begin
    Ch := UpCase(S[i]);

    case Ch of
      'A'..'G':
        begin
          Inc(i);
          Acc := '';
          if (i <= Length(S)) and ((S[i] = '#') or (S[i] = '+')) then
          begin
            Acc := '#';
            Inc(i);
          end
          else if (i <= Length(S)) and (S[i] = '-') then
          begin
            Acc := 'b';
            Inc(i);
          end;

          LenValue := CurLen;
          if (i <= Length(S)) and (S[i] in ['0'..'9']) then
          begin
            NumVal := ReadNumber(i);
            if ValidLen(NumVal) then LenValue := NumVal;
          end;

          Dotted := False;
          if (i <= Length(S)) and (S[i] = '.') then
          begin
            Dotted := True;
            Inc(i);
          end;

          NameStr := Ch + Acc;
          Emit(NoteFreq(NameStr, Octave), LenValue, Dotted);
        end;

      'R':
        begin
          Inc(i);
          LenValue := CurLen;
          if (i <= Length(S)) and (S[i] in ['0'..'9']) then
          begin
            NumVal := ReadNumber(i);
            if ValidLen(NumVal) then LenValue := NumVal;
          end;

          Dotted := False;
          if (i <= Length(S)) and (S[i] = '.') then
          begin
            Dotted := True;
            Inc(i);
          end;

          Emit(0, LenValue, Dotted);
        end;

      'O':
        begin
          Inc(i);
          if (i <= Length(S)) and (S[i] in ['0'..'9']) then
          begin
            NumVal := ReadNumber(i);
            if NumVal < 1 then NumVal := 1;
            if NumVal > 8 then NumVal := 8;
            Octave := NumVal;
          end;
        end;

      'L':
        begin
          Inc(i);
          if (i <= Length(S)) and (S[i] in ['0'..'9']) then
          begin
            NumVal := ReadNumber(i);
            if ValidLen(NumVal) then CurLen := NumVal;
          end;
        end;

      'T':
        begin
          Inc(i);
          if (i <= Length(S)) and (S[i] in ['0'..'9']) then
          begin
            NumVal := ReadNumber(i);
            if NumVal < 20 then NumVal := 20;
            if NumVal > 500 then NumVal := 500;
            Tempo := NumVal;
          end;
        end;

      '<':
        begin
          if Octave > 1 then Dec(Octave);
          Inc(i);
        end;

      '>':
        begin
          if Octave < 8 then Inc(Octave);
          Inc(i);
        end;

      '&':
        begin
          PendingTie := True;
          Inc(i);
        end;

      '@', 'V', '$':
        begin
          { Discard the command char's numeric argument: skip digits and any
            intervening junk up to the next recognized command. }
          Inc(i);
          while (i <= Length(S)) and (not IsCommand(S[i])) do Inc(i);
        end;

      '[':
        begin
          { Loop construct: discard the whole body up to the matching ']'.
            An unmatched '[' silently discards the rest of the string. }
          Inc(i);
          while (i <= Length(S)) and (S[i] <> ']') do Inc(i);
          if i <= Length(S) then Inc(i);
        end;

      '{':
        begin
          { Grace-note construct: discard the body up to the matching close brace. }
          Inc(i);
          while (i <= Length(S)) and (S[i] <> '}') do Inc(i);
          if i <= Length(S) then Inc(i);
        end;

      ']', '}':
        Inc(i);

    else
      Inc(i);
    end;
  end;

  LoadMML := Melody.Count > 0;
end;

end.
