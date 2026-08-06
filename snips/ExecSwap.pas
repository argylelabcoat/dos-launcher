unit ExecSwap;

interface

uses Dos;

{ Swaps the current program to a file on disk and executes Path with CmdLine.
  Returns:
    0 = Success
    1 = Could not create swap file
    2 = Could not write to swap file
    3 = Exec error (check DosError)
}
function ExecWithSwap(Path, CmdLine, SwapPath: string): Integer;

implementation

{$F+} { Force Far Calls for Assembly Interoperability }

type
  { Structure stored in the resident stub memory }
  TStubData = record
    OldSS, OldSP : Word;
    OldCS, OldIP : Word;
    Handle       : Word;
    ExePath      : array[0..79] of Char;
    CmdBuffer    : array[0..127] of Char;
  end;

function ExecWithSwap(Path, CmdLine, SwapPath: string): Integer;
var
  SwapFile: file;
  ResultCode: Integer;
  PPath, PCmd: string;
  SaveHeapEnd: Pointer;
  BytesToSwap: LongInt;
  ActualWritten: Word;
begin
  ExecWithSwap := 0;

  { Ensure paths are null-terminated for DOS interrupts }
  PPath := Path + #0;
  PCmd := CmdLine + #13; { DOS command tails end with CR }

  { Calculate exact memory block size from PrefixSeg to HeapPtr }
  BytesToSwap := LongInt(Seg(HeapPtr^) - PrefixSeg) * 16;

  { 1. Create the swap file }
  Assign(SwapFile, SwapPath);
  {$I-} Rewrite(SwapFile, 1); {$I+}
  if IOResult <> 0 then
  begin
    ExecWithSwap := 1;
    Exit;
  end;

  { 2. Write the active program memory (PSP + Code + Data + Heap) to disk }
  {$I-} BlockWrite(SwapFile, Mem[PrefixSeg:0], BytesToSwap, ActualWritten); {$I+}
  if (IOResult <> 0) or (LongInt(ActualWritten) <> BytesToSwap) then
  begin
    Close(SwapFile);
    Erase(SwapFile);
    ExecWithSwap := 2;
    Exit;
  end;

  { 3. Close swap file before spawning child process }
  Close(SwapFile);

  { 4. Perform standard DOS Exec }
  SwapVectors;
  Exec(Path, CmdLine);
  SwapVectors;

  ResultCode := DosError;

  { 5. Reload launcher state back into RAM from the swap file }
  {$I-} Reset(SwapFile, 1); {$I+}
  if IOResult = 0 then
  begin
    BlockRead(SwapFile, Mem[PrefixSeg:0], BytesToSwap, ActualWritten);
    Close(SwapFile);
    Erase(SwapFile);
  end;

  if ResultCode <> 0 then
    ExecWithSwap := 3;
end;

end.
