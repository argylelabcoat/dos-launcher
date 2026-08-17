# Tasks: pc-speaker-music

## 1. SpeakerMusic unit — intermediate format + playback

- [ ] 1.1 Create `snips/SpeakerMusic.pas` with `{$MODE TP}` unit header, `uses Crt` in implementation
- [ ] 1.2 Define `MAX_NOTES = 256`, `TNote = record Freq: Word; Duration: Word end`, `TMelody = record Notes: array[0..MAX_NOTES-1] of TNote; Count: Word end` in interface
- [ ] 1.3 Implement `const` frequency table: `array[0..95] of Word` covering MIDI 24 (C1) through MIDI 119 (B8), equal temperament A4=440, integer Hz values
- [ ] 1.4 Implement `NoteFreq(const NoteName: string; Octave: Integer): Word` — parse 1-2 char note name (A-G, optional #/b), map to table index `(Octave-1)*12 + semitoneOffset`, return 0 on invalid input or out-of-range octave (valid: 1..8)
- [ ] 1.5 Implement `PlayNote(Freq, Duration: Word)` — if Freq=0: `NoSound; Delay(Duration)`; else `Sound(Freq); Delay(Duration); NoSound`
- [ ] 1.6 Implement `Rest(Duration: Word)` — `NoSound; Delay(Duration)`
- [ ] 1.7 Implement `PlayMelody(var Melody: TMelody)` — iterate Notes[0..Count-1], call `PlayNote` for each, insert `Delay(1)` gap between consecutive notes
- [ ] 1.8 Implement `ClearMelody(var Melody: TMelody)` — `FillChar(Melody, SizeOf(Melody), 0)` (zeroes `Count` and `Notes` together)
- [ ] 1.9 Implement `AddNote(var Melody: TMelody; Freq, Duration: Word): Boolean` — return False if Count >= MAX_NOTES; else write Notes[Count], Inc(Count), return True
- [ ] 1.10 Verify: compile `SpeakerMusic.pas` standalone with FPC `-Mtp` (or syntax-review if cross-compiler unavailable)

## 2. RtttlLoader unit — RTTTL → TMelody

- [ ] 2.1 Create `snips/RtttlLoader.pas` with `{$MODE TP}` unit header, `uses SpeakerMusic` in interface
- [ ] 2.2 Implement section splitter: find first colon (name|defaults+notes), find second colon (defaults|notes); return False if fewer than 2 colons
- [ ] 2.3 Implement defaults parser: split defaults section on `,`, parse `key=value` for `d` (1-32), `o` (4-8), `b` (25-900); clamp out-of-range; ignore unknown keys; defaults: d=4, o=5, b=63
- [ ] 2.4 Implement note parser: scan left-to-right — optional duration digits (1/2/4/8/16/32), pitch letter (A-G or P for rest), optional `#` (sharp) or `b` (flat), optional octave digits (4-8), optional `.` (dotted)
- [ ] 2.5 Implement duration resolution: `var ms: LongInt; ms := (LongInt(60000) * 4) div (BPM * durationValue)`; if dotted then `ms := (ms * 3) div 2`; use per-note duration if specified, else default `d`
- [ ] 2.6 Implement pitch resolution: call `NoteFreq(pitchChar + accidental, octave)` where octave uses per-note value if specified, else default `o`; `P` produces Freq=0 (rest)
- [ ] 2.7 Wire note parser into loop: for each comma-separated token in notes section, parse and `AddNote`; skip unparseable tokens without error; if `AddNote` returns False (melody full), stop and return True
- [ ] 2.8 Return False if the notes section produced zero notes (empty melody = structural failure)
- [ ] 2.9 Verify: compile `RtttlLoader.pas` standalone with FPC `-Mtp`

## 3. MmlLoader unit — MML → TMelody

- [ ] 3.1 Create `snips/MmlLoader.pas` with `{$MODE TP}` unit header, `uses SpeakerMusic` in interface
- [ ] 3.2 Implement character scanner state: `Octave` (default 4), `Length` (default 4), `Tempo` (default 120 BPM), `TiePending` (Boolean), `LastNoteIdx` (Integer, -1 = none)
- [ ] 3.3 Implement note command (`A`-`G`): read optional `#`/`+` (sharp) or `-` (flat), optional duration digits (1/2/4/8/16/32/64), optional `.` (dotted); compute Freq via `NoteFreq`; compute Duration via `var ms: LongInt; ms := (LongInt(60000) * 4) div (Tempo * lengthValue)`, dotted: `ms := (ms * 3) div 2`; if TiePending and Freq matches last note's Freq, extend last note Duration and clear TiePending; else clear TiePending, `AddNote`, set LastNoteIdx
- [ ] 3.4 Implement rest command (`R`): read optional duration digits and `.`; compute Duration; `AddNote` with Freq=0; clear TiePending
- [ ] 3.5 Implement `O` command: read digits, set Octave (clamp 1-8)
- [ ] 3.6 Implement `L` command: read digits, set Length (1/2/4/8/16/32/64)
- [ ] 3.7 Implement `T` command: read digits, set Tempo (20-500)
- [ ] 3.8 Implement `<` and `>`: decrement/increment Octave (clamp 1-8)
- [ ] 3.9 Implement `&` (tie): set TiePending := True
- [ ] 3.10 Implement unsupported-command skip: for `@`, `v`, `$`, `[`, `]`, `{`, `}` — read and discard following digits/characters until the next recognized command letter; no error
- [ ] 3.11 Skip whitespace and unrecognized characters without error
- [ ] 3.12 Return False if zero notes were emitted (empty/whitespace-only input)
- [ ] 3.13 Verify: compile `MmlLoader.pas` standalone with FPC `-Mtp`

## 4. MusicTest program — standalone verification

- [ ] 4.1 Create `snips/MusicTest.pas` — standalone `program` with `uses Crt, SpeakerMusic, RtttlLoader, MmlLoader`
- [ ] 4.2 Add hard-coded RTTTL test string: a public-domain melody (e.g. "Ode to Joy" or a C-major scale) in RTTTL format
- [ ] 4.3 Add hard-coded MML test string: the same melody in MML format
- [ ] 4.4 Test 1: `LoadRTTTL(rttlStr, Melody)` → assert `True` → print each note (index, freq, duration) → `PlayMelody(Melody)`
- [ ] 4.5 Test 2: `LoadMML(mmlStr, Melody)` → assert `True` → print each note → `PlayMelody(Melody)`
- [ ] 4.6 Test 3: `PlayNote(880, 200)` — single A5 beep; print "playing A5 at 880Hz for 200ms"
- [ ] 4.7 Test 4: `Rest(500)` — half-second silence; print "resting 500ms"
- [ ] 4.8 Test 5 (negative): `LoadRTTTL('garbage', Melody)` → assert returns `False`; print "correctly rejected malformed RTTTL"
- [ ] 4.9 Test 6 (negative): `LoadMML('', Melody)` → assert returns `False`; print "correctly rejected empty MML"
- [ ] 4.10 Verify: run in DOSBox-X with PC speaker enabled (`pcspeaker=true`, `speaker=on`); confirm melody audible, note printout correct, negatives rejected
- [ ] 4.11 Commit all four files with message "feat: add PC-speaker music engine with RTTTL and MML loaders"

## 5. Documentation

- [ ] 5.1 Add a comment block at the top of `SpeakerMusic.pas` explaining the 8253 PIT / speaker gate mechanism and why the inter-note gap exists
- [ ] 5.2 Add a comment block at the top of `RtttlLoader.pas` summarizing the RTTTL format reference and the lenient parsing policy
- [ ] 5.3 Add a comment block at the top of `MmlLoader.pas` summarizing the supported MML command set and the unsupported-command skip policy