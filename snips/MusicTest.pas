program MusicTest;

{ MusicTest - standalone DOS verification of the PC-speaker music engine.

  Exercises the three music units (SpeakerMusic, RtttlLoader, MmlLoader)
  headlessly enough that the result can be checked on real hardware or in
  DOSBox-X with the PC speaker enabled:

    1. LoadRTTTL on a hard-coded public-domain melody -> print the decoded
       note list -> PlayMelody.
    2. LoadMML on the same melody -> print -> PlayMelody.
    3. PlayNote(880, 200) - a single A5 beep.
    4. Rest(500) - a half-second silence.
    5. LoadRTTTL('garbage') must return False.
    6. LoadMML('') must return False.

  Playback blocks (each note is Sound -> Delay -> NoSound), so running this
  from the DOS prompt simply takes as long as the melodies last. The WriteLn
  output is the machine-checkable part; the audio is the human-checkable
  part. Everything is TP-dialect, heap-free, integer-only, short strings. }

{$MODE TP}

uses Crt, SpeakerMusic, RtttlLoader, MmlLoader;

const
  { Public-domain C-major fragment of Beethoven's "Ode to Joy" (bars 1-8
    condensed). RTTTL uses colons to separate name:defaults:notes; the
    defaults set quarter-note (d=4), octave 5, and 140 BPM. }
  RTTTL_MELODY = 'OdeToJoy:d=4,o=5,b=140:e5,e5,f5,g5,g5,f5,e5,d5,c5,c5,d5,e5,e5,d5,d5';

  { The same melody in MML: T140 sets tempo, L4 default length, O5 octave. }
  MML_MELODY   = 'T140 L4 O5 E E F G G F E D C C D E E D D';

var
  Melody : TMelody;   { 256 notes x 4 bytes + count = 1026 bytes on the stack }
  Ok     : Boolean;

{ Print every note in a melody as (index, freq, duration). Only called when
  a loader reported success, so Melody.Count is guaranteed > 0 and the loop
  never runs the empty-range Word-wraparound case. }
procedure PrintMelody(var M: TMelody);
var
  i : Integer;
begin
  for i := 0 to Integer(M.Count) - 1 do
    WriteLn('  note ', i, ': freq=', M.Notes[i].Freq, ' Hz  duration=',
            M.Notes[i].Duration, ' ms');
end;

begin
  WriteLn('MusicTest: PC-speaker music engine verification');
  WriteLn;

  WriteLn('Test 1: LoadRTTTL');
  Ok := LoadRTTTL(RTTTL_MELODY, Melody);
  WriteLn('  RTTTL returned ', Ok);
  if Ok then
  begin
    PrintMelody(Melody);
    PlayMelody(Melody);
  end
  else
    WriteLn('  ERROR: RTTTL melody failed to decode');

  WriteLn;
  WriteLn('Test 2: LoadMML');
  Ok := LoadMML(MML_MELODY, Melody);
  WriteLn('  MML returned ', Ok);
  if Ok then
  begin
    PrintMelody(Melody);
    PlayMelody(Melody);
  end
  else
    WriteLn('  ERROR: MML melody failed to decode');

  WriteLn;
  WriteLn('Test 3: PlayNote(880, 200)');
  WriteLn('  playing A5 at 880Hz for 200ms');
  PlayNote(880, 200);

  WriteLn;
  WriteLn('Test 4: Rest(500)');
  WriteLn('  resting 500ms');
  Rest(500);

  WriteLn;
  WriteLn('Test 5: malformed RTTTL rejection');
  Ok := LoadRTTTL('garbage', Melody);
  WriteLn('  LoadRTTTL("garbage") returned ', Ok);
  if Ok then
    WriteLn('  ERROR: malformed RTTTL was accepted')
  else
    WriteLn('  correctly rejected malformed RTTTL');

  WriteLn;
  WriteLn('Test 6: empty MML rejection');
  Ok := LoadMML('', Melody);
  WriteLn('  LoadMML("") returned ', Ok);
  if Ok then
    WriteLn('  ERROR: empty MML was accepted')
  else
    WriteLn('  correctly rejected empty MML');

  WriteLn;
  WriteLn('MusicTest complete.');
end.
