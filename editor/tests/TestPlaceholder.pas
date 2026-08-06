unit TestPlaceholder;

{$MODE OBJFPC}{$H+}

interface

uses
  fpcunit, testregistry;

type
  { Placeholder suite proving the fpcunit harness runs. Format-unit test cases
    (TestLauncherDoc, TestRiffReader, TestRiffWriter, TestIconConvert) register
    themselves the same way once their implementation units exist; add each new
    unit to the `uses` clause in TestRunner.lpr. }
  TPlaceholderTest = class(TTestCase)
  published
    procedure HarnessRuns;
  end;

implementation

procedure TPlaceholderTest.HarnessRuns;
begin
  AssertEquals('fpcunit harness is wired up', 1, 1);
end;

initialization
  RegisterTest(TPlaceholderTest);
end.
