program LauncherEditor;

{$MODE OBJFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  MainForm;

begin
  Application.Title := 'DOS Launcher Editor';
  Application.Scaled := True;
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.CreateForm(TMainForm, frmMain);
  Application.Run;
end.
