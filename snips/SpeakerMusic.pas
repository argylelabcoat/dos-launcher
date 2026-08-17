unit SpeakerMusic;

{ SpeakerMusic — intermediate music format, shared frequency table, and
  PC-speaker playback.

  Playback drives the IBM PC speaker through Crt.Sound / Crt.NoSound /
  Crt.Delay, which program the 8253 Programmable Interval Timer channel 2
  to oscillate at the requested frequency and toggle the speaker gate bit
  on I/O port $61. There is no sound card, no envelope, and no volume
  control — the speaker is either oscillating at a fixed frequency or off.

  Sound(Freq) leaves the gate open until NoSound is called; if a melody
  ended while the gate was still open the speaker would whine forever.
  Every note therefore ends with an explicit NoSound.

  PlayMelody inserts a 1ms Delay(1) gap between consecutive notes. Without
  it, two adjacent notes of the same pitch would be indistinguishable from
  one continuous tone — Sound(Freq) -> Delay -> NoSound -> Sound(Freq)
  re-arms the same frequency with no audible boundary. The 1ms gate drop is
  long enough to produce an attack transient but short enough to be
  imperceptible as silence.

  Everything here is integer-only, heap-free, and TP-dialect: the frequency
  table is a const array in this unit's implementation section, and the two
  music loaders (RtttlLoader, MmlLoader) resolve note names through the
  single NoteFreq function below so no octave/semitone mapping is ever
  duplicated. }

{$MODE TP}

interface

const
  MAX_NOTES = 256;  { 256 notes x 4 bytes = 1KB - fits the 16KB stack }

type
  TNote = record
    Freq     : Word;   { Hz; 0 = rest (silence) }
    Duration : Word;   { milliseconds }
  end;

  TMelody = record
    Notes : array[0..MAX_NOTES - 1] of TNote;
    Count : Word;      { number of valid notes (0..MAX_NOTES) }
  end;

{ Play a single tone. Freq=0 produces silence (rest). }
procedure PlayNote(Freq, Duration: Word);

{ Play a silence gap. Equivalent to PlayNote(0, Duration). }
procedure Rest(Duration: Word);

{ Play a full melody. Blocking - uses Delay(ms) per note. }
procedure PlayMelody(var Melody: TMelody);

{ Clear a melody to zero notes (Count := 0, Notes zeroed). }
procedure ClearMelody(var Melody: TMelody);

{ Append a note to a melody. Returns False if the melody is full. }
function AddNote(var Melody: TMelody; Freq, Duration: Word): Boolean;

{ Note-name to frequency lookup. NoteName is 1-2 chars: letter A-G
  optionally followed by '#' or 'b' (sharp/flat). Octave is 1-8.
  Returns 0 if the note name or octave is invalid. }
function NoteFreq(const NoteName: string; Octave: Integer): Word;

implementation

uses Crt;

const
  { Equal-temperament frequency table, A4 = 440 Hz, rounded to integer Hz.
    Entry 0 = C1 (MIDI 24, ~32.70 Hz) through entry 95 = B8 (MIDI 119,
    ~7902.13 Hz): 96 entries, one full octave of 12 semitones each.
    Indexed by (Octave - 1) * 12 + semitoneOffset, so C1 = 0, C#1 = 1,
    ... B8 = 95. Precomputed so no floating-point math runs on the 8088. }
  FreqTable : array[0..95] of Word = (
    33,   35,   37,   39,   41,   44,   46,   49,   52,   55,   58,   62,
    65,   69,   73,   78,   82,   87,   92,   98,  104,  110,  117,  123,
    131,  139,  147,  156,  165,  175,  185,  196,  208,  220,  233,  247,
    262,  277,  294,  311,  330,  349,  370,  392,  415,  440,  466,  494,
    523,  554,  587,  622,  659,  698,  740,  784,  831,  880,  932,  988,
    1047, 1109, 1175, 1245, 1319, 1397, 1480, 1568, 1661, 1760, 1865, 1976,
    2093, 2217, 2349, 2489, 2637, 2794, 2960, 3136, 3322, 3520, 3729, 3951,
    4186, 4435, 4699, 4978, 5274, 5588, 5920, 6272, 6645, 7040, 7459, 7902
  );

procedure PlayNote(Freq, Duration: Word);
begin
  if Freq = 0 then
  begin
    NoSound;
    Delay(Duration);
  end
  else
  begin
    Sound(Freq);
    Delay(Duration);
    NoSound;
  end;
end;

procedure Rest(Duration: Word);
begin
  NoSound;
  Delay(Duration);
end;

procedure PlayMelody(var Melody: TMelody);
var
  i : Word;
begin
  for i := 0 to Melody.Count - 1 do
  begin
    PlayNote(Melody.Notes[i].Freq, Melody.Notes[i].Duration);
    { 1ms gate drop between notes so consecutive same-pitch notes do not
      merge into a single continuous tone (see the unit header comment). }
    Delay(1);
  end;
end;

procedure ClearMelody(var Melody: TMelody);
begin
  FillChar(Melody, SizeOf(Melody), 0);
end;

function AddNote(var Melody: TMelody; Freq, Duration: Word): Boolean;
begin
  if Melody.Count >= MAX_NOTES then
  begin
    AddNote := False;
    Exit;
  end;

  Melody.Notes[Melody.Count].Freq     := Freq;
  Melody.Notes[Melody.Count].Duration := Duration;
  Inc(Melody.Count);
  AddNote := True;
end;

function NoteFreq(const NoteName: string; Octave: Integer): Word;
var
  Letter : Char;
  Offset : Integer;
  Idx    : Integer;
begin
  NoteFreq := 0;

  { Octave below 1 or above 8 falls off the table - return the silence
    sentinel rather than indexing out of bounds. }
  if (Octave < 1) or (Octave > 8) then Exit;
  if Length(NoteName) < 1 then Exit;

  Letter := UpCase(NoteName[1]);
  if (Letter < 'A') or (Letter > 'G') then Exit;

  { Natural-note semitone offsets within an octave (C=0 .. B=11). }
  case Letter of
    'C': Offset := 0;
    'D': Offset := 2;
    'E': Offset := 4;
    'F': Offset := 5;
    'G': Offset := 7;
    'A': Offset := 9;
    'B': Offset := 11;
  else
    Exit;
  end;

  { Optional accidental: '#' sharpens (+1), 'b' flattens (-1). A second
    character that is neither is an invalid note name. }
  if Length(NoteName) >= 2 then
  begin
    if NoteName[2] = '#' then
      Inc(Offset)
    else if (NoteName[2] = 'b') or (NoteName[2] = 'B') then
      Dec(Offset)
    else
      Exit;
  end;

  Idx := (Octave - 1) * 12 + Offset;
  if (Idx < 0) or (Idx > 95) then Exit;

  NoteFreq := FreqTable[Idx];
end;

end.
