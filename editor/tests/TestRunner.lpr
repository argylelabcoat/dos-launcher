program TestRunner;

{$MODE OBJFPC}{$H+}

uses
  Classes, consoletestrunner,
  TestPlaceholder,
  TestLauncherDoc,
  TestRiffReader,
  TestRiffWriter,
  TestIconConvert;

var
  App: TTestRunner;

begin
  App := TTestRunner.Create(nil);
  App.Title := 'dos-launcher editor format-unit tests';
  App.Run;
  App.Free;
end.
