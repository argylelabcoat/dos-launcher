unit MainForm;

{ Main editor form for LAUNCHER.DAT (design D1: GUI code touches only
  LauncherDoc/RiffWriter/RiffReader/IconConvert/SaveIO -- never RCLF bytes
  directly). Built entirely in code (no .lfm) via the standard
  "inherited CreateNew" pattern, so the whole UI tree is visible and
  reviewable as plain Object Pascal rather than a separately-authored
  resource file. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Menus, ActnList, LCLType,
  LauncherDoc, RiffReader, IconConvert, SaveIO;

type

  { TMainForm }

  TMainForm = class(TForm)
  private
    FDoc: TLauncherDoc;
    FCurrentFileName: string;
    FUpdating: Boolean;
    FHighlightIndex: Integer;          { entry index to flag red in the list, -1 = none }
    FCurrentIconPixels: TIndexGrid;
    FHasCurrentIcon: Boolean;

    { Menu }
    MainMenu1: TMainMenu;
    { Toolbar }
    ToolBar1: TToolBar;
    { Actions }
    ActionList1: TActionList;
    ActionNew, ActionOpen, ActionSave,
      ActionAdd, ActionRemove, ActionUp, ActionDown,
      ActionImportIcon, ActionClearIcon: TAction;
    { Dialogs }
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    OpenIconDialog1: TOpenDialog;
    { Entry list }
    ListBoxEntries: TListBox;
    { Edit panel }
    PanelEdit: TPanel;
    EditTitle, EditDesc, EditExec, EditArgs: TEdit;
    CheckPause, CheckClear: TCheckBox;
    { Icon preview }
    PanelIcon: TPanel;
    PaintBoxPreview: TPaintBox;

    procedure BuildComponents;
    procedure RefreshList;
    procedure LoadEntryToPanel(Index: Integer);
    procedure ClearEditPanel;
    function BuildEntryFromPanel(const Existing: TAppEntry): TAppEntry;
    function DoSave(const FileName: string): Boolean;
    function VgaColor(Idx: Byte): TColor;

    procedure ListBoxEntriesDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure ListBoxEntriesSelectionChange(Sender: TObject; User: Boolean);
    procedure EditFieldChange(Sender: TObject);
    procedure CheckFlagChange(Sender: TObject);
    procedure PaintBoxPreviewPaint(Sender: TObject);

    procedure ActionNewExecute(Sender: TObject);
    procedure ActionOpenExecute(Sender: TObject);
    procedure ActionSaveExecute(Sender: TObject);
    procedure ActionAddExecute(Sender: TObject);
    procedure ActionRemoveExecute(Sender: TObject);
    procedure ActionUpExecute(Sender: TObject);
    procedure ActionDownExecute(Sender: TObject);
    procedure ActionImportIconExecute(Sender: TObject);
    procedure ActionClearIconExecute(Sender: TObject);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TMainForm;

implementation

{ ---------------------------------------------------------------- }
{ Construction }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);
  Caption := 'DOS Launcher Editor';
  Width := 820;
  Height := 560;
  Position := poScreenCenter;

  FDoc := TLauncherDoc.Create;
  FCurrentFileName := '';
  FHighlightIndex := -1;
  FHasCurrentIcon := False;

  BuildComponents;
  RefreshList;
  ClearEditPanel;
end;

destructor TMainForm.Destroy;
begin
  FDoc.Free;
  inherited Destroy;
end;

procedure TMainForm.BuildComponents;
var
  MiFile, MiEntries: TMenuItem;

  function NewMenuItem(Parent: TMenuItem; const ACaption: string; AnAction: TAction): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    if AnAction <> nil then
      Result.Action := AnAction;
    Parent.Add(Result);
  end;

  function NewToolButton(AnAction: TAction): TToolButton;
  begin
    Result := TToolButton.Create(Self);
    Result.Parent := ToolBar1;
    Result.Action := AnAction;
  end;

  function NewLabel(AParent: TWinControl; const ACaption: string; ATop: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Left := 8;
    Result.Top := ATop;
  end;

begin
  { Actions -- shared between the menu bar and the toolbar so each command
    has exactly one handler. }
  ActionList1 := TActionList.Create(Self);

  ActionNew := TAction.Create(Self);
  ActionNew.ActionList := ActionList1;
  ActionNew.Caption := 'New';
  ActionNew.OnExecute := @ActionNewExecute;

  ActionOpen := TAction.Create(Self);
  ActionOpen.ActionList := ActionList1;
  ActionOpen.Caption := 'Open';
  ActionOpen.OnExecute := @ActionOpenExecute;

  ActionSave := TAction.Create(Self);
  ActionSave.ActionList := ActionList1;
  ActionSave.Caption := 'Save';
  ActionSave.OnExecute := @ActionSaveExecute;

  ActionAdd := TAction.Create(Self);
  ActionAdd.ActionList := ActionList1;
  ActionAdd.Caption := 'Add';
  ActionAdd.OnExecute := @ActionAddExecute;

  ActionRemove := TAction.Create(Self);
  ActionRemove.ActionList := ActionList1;
  ActionRemove.Caption := 'Remove';
  ActionRemove.OnExecute := @ActionRemoveExecute;

  ActionUp := TAction.Create(Self);
  ActionUp.ActionList := ActionList1;
  ActionUp.Caption := 'Up';
  ActionUp.OnExecute := @ActionUpExecute;

  ActionDown := TAction.Create(Self);
  ActionDown.ActionList := ActionList1;
  ActionDown.Caption := 'Down';
  ActionDown.OnExecute := @ActionDownExecute;

  ActionImportIcon := TAction.Create(Self);
  ActionImportIcon.ActionList := ActionList1;
  ActionImportIcon.Caption := 'Import Icon';
  ActionImportIcon.OnExecute := @ActionImportIconExecute;

  ActionClearIcon := TAction.Create(Self);
  ActionClearIcon.ActionList := ActionList1;
  ActionClearIcon.Caption := 'Clear Icon';
  ActionClearIcon.OnExecute := @ActionClearIconExecute;

  { Dialogs }
  OpenDialog1 := TOpenDialog.Create(Self);
  OpenDialog1.Title := 'Open LAUNCHER.DAT';
  OpenDialog1.Filter := 'Launcher data (*.dat)|*.DAT|All files|*.*';
  OpenDialog1.DefaultExt := 'DAT';

  SaveDialog1 := TSaveDialog.Create(Self);
  SaveDialog1.Title := 'Save LAUNCHER.DAT';
  SaveDialog1.Filter := 'Launcher data (*.dat)|*.DAT|All files|*.*';
  SaveDialog1.DefaultExt := 'DAT';

  OpenIconDialog1 := TOpenDialog.Create(Self);
  OpenIconDialog1.Title := 'Import Icon';
  OpenIconDialog1.Filter := 'Bitmap files (*.bmp)|*.BMP';
  OpenIconDialog1.DefaultExt := 'BMP';

  { Menu }
  MainMenu1 := TMainMenu.Create(Self);
  Menu := MainMenu1;

  MiFile := TMenuItem.Create(Self);
  MiFile.Caption := '&File';
  MainMenu1.Items.Add(MiFile);
  NewMenuItem(MiFile, 'New', ActionNew);
  NewMenuItem(MiFile, 'Open...', ActionOpen);
  NewMenuItem(MiFile, 'Save', ActionSave);

  MiEntries := TMenuItem.Create(Self);
  MiEntries.Caption := '&Entries';
  MainMenu1.Items.Add(MiEntries);
  NewMenuItem(MiEntries, 'Add', ActionAdd);
  NewMenuItem(MiEntries, 'Remove', ActionRemove);
  NewMenuItem(MiEntries, 'Move Up', ActionUp);
  NewMenuItem(MiEntries, 'Move Down', ActionDown);
  NewMenuItem(MiEntries, 'Import Icon...', ActionImportIcon);
  NewMenuItem(MiEntries, 'Clear Icon', ActionClearIcon);

  { Toolbar }
  ToolBar1 := TToolBar.Create(Self);
  ToolBar1.Parent := Self;
  ToolBar1.Align := alTop;
  ToolBar1.Height := 32;
  ToolBar1.ShowCaptions := True;
  ToolBar1.Flat := True;
  NewToolButton(ActionNew);
  NewToolButton(ActionOpen);
  NewToolButton(ActionSave);
  NewToolButton(ActionAdd);
  NewToolButton(ActionRemove);
  NewToolButton(ActionUp);
  NewToolButton(ActionDown);
  NewToolButton(ActionImportIcon);
  NewToolButton(ActionClearIcon);

  { Entry list -- owner-drawn so each row can show a title plus icon
    thumbnail (Scenario: "Entry list shows title and icon"). }
  ListBoxEntries := TListBox.Create(Self);
  ListBoxEntries.Parent := Self;
  ListBoxEntries.Align := alLeft;
  ListBoxEntries.Width := 280;
  ListBoxEntries.Style := lbOwnerDrawFixed;
  ListBoxEntries.ItemHeight := 36;
  ListBoxEntries.OnDrawItem := @ListBoxEntriesDrawItem;
  ListBoxEntries.OnSelectionChange := @ListBoxEntriesSelectionChange;

  { Icon preview panel -- on the right, above the edit fields. }
  PanelIcon := TPanel.Create(Self);
  PanelIcon.Parent := Self;
  PanelIcon.Align := alRight;
  PanelIcon.Width := 220;
  PanelIcon.BevelOuter := bvNone;
  PanelIcon.Caption := '';

  PaintBoxPreview := TPaintBox.Create(Self);
  PaintBoxPreview.Parent := PanelIcon;
  PaintBoxPreview.Left := 10;
  PaintBoxPreview.Top := 10;
  PaintBoxPreview.Width := 192; { 32px icon x 6 scale }
  PaintBoxPreview.Height := 192;
  PaintBoxPreview.OnPaint := @PaintBoxPreviewPaint;

  { Edit panel -- fills the remaining client area. }
  PanelEdit := TPanel.Create(Self);
  PanelEdit.Parent := Self;
  PanelEdit.Align := alClient;
  PanelEdit.BevelOuter := bvNone;

  NewLabel(PanelEdit, 'Title (max 40):', 8);
  EditTitle := TEdit.Create(Self);
  EditTitle.Parent := PanelEdit;
  EditTitle.Left := 8;
  EditTitle.Top := 26;
  EditTitle.Width := 380;
  EditTitle.MaxLength := MAX_TITLE_LEN;
  EditTitle.OnChange := @EditFieldChange;

  NewLabel(PanelEdit, 'Description (max 70):', 56);
  EditDesc := TEdit.Create(Self);
  EditDesc.Parent := PanelEdit;
  EditDesc.Left := 8;
  EditDesc.Top := 74;
  EditDesc.Width := 380;
  EditDesc.MaxLength := MAX_DESC_LEN;
  EditDesc.OnChange := @EditFieldChange;

  NewLabel(PanelEdit, 'Exec path (max 64):', 104);
  EditExec := TEdit.Create(Self);
  EditExec.Parent := PanelEdit;
  EditExec.Left := 8;
  EditExec.Top := 122;
  EditExec.Width := 380;
  EditExec.MaxLength := MAX_EXEC_LEN;
  EditExec.OnChange := @EditFieldChange;

  NewLabel(PanelEdit, 'Args (max 64):', 152);
  EditArgs := TEdit.Create(Self);
  EditArgs.Parent := PanelEdit;
  EditArgs.Left := 8;
  EditArgs.Top := 170;
  EditArgs.Width := 380;
  EditArgs.MaxLength := MAX_ARGS_LEN;
  EditArgs.OnChange := @EditFieldChange;

  CheckPause := TCheckBox.Create(Self);
  CheckPause.Parent := PanelEdit;
  CheckPause.Left := 8;
  CheckPause.Top := 206;
  CheckPause.Width := 200;
  CheckPause.Caption := 'Pause on exit (bit 0)';
  CheckPause.OnClick := @CheckFlagChange;

  CheckClear := TCheckBox.Create(Self);
  CheckClear.Parent := PanelEdit;
  CheckClear.Left := 8;
  CheckClear.Top := 230;
  CheckClear.Width := 200;
  CheckClear.Caption := 'Clear screen (bit 1)';
  CheckClear.OnClick := @CheckFlagChange;
end;

{ ---------------------------------------------------------------- }
{ Helpers }

function TMainForm.VgaColor(Idx: Byte): TColor;
begin
  if Idx > 15 then Idx := 15;
  Result := RGBToColor(VGA_PALETTE[Idx].R, VGA_PALETTE[Idx].G, VGA_PALETTE[Idx].B);
end;

procedure TMainForm.RefreshList;
var
  i, OldIndex: Integer;
begin
  OldIndex := ListBoxEntries.ItemIndex;
  ListBoxEntries.Items.BeginUpdate;
  try
    ListBoxEntries.Items.Clear;
    for i := 0 to FDoc.Count - 1 do
      ListBoxEntries.Items.Add(FDoc.GetEntry(i).Title);
  finally
    ListBoxEntries.Items.EndUpdate;
  end;
  if (OldIndex >= 0) and (OldIndex < FDoc.Count) then
    ListBoxEntries.ItemIndex := OldIndex;
  ListBoxEntries.Invalidate;
end;

procedure TMainForm.ClearEditPanel;
begin
  FUpdating := True;
  try
    EditTitle.Text := '';
    EditDesc.Text := '';
    EditExec.Text := '';
    EditArgs.Text := '';
    CheckPause.Checked := False;
    CheckClear.Checked := False;
  finally
    FUpdating := False;
  end;
  FHasCurrentIcon := False;
  PaintBoxPreview.Invalidate;
end;

procedure TMainForm.LoadEntryToPanel(Index: Integer);
var
  Entry: TAppEntry;
begin
  if (Index < 0) or (Index >= FDoc.Count) then
  begin
    ClearEditPanel;
    Exit;
  end;
  Entry := FDoc.GetEntry(Index);
  FUpdating := True;
  try
    EditTitle.Text := Entry.Title;
    EditDesc.Text := Entry.Desc;
    EditExec.Text := Entry.ExecPath;
    EditArgs.Text := Entry.Args;
    CheckPause.Checked := (Entry.Flags and 1) <> 0;
    CheckClear.Checked := (Entry.Flags and 2) <> 0;
  finally
    FUpdating := False;
  end;

  if Entry.HasIcon and IconConvert.DecodeIconPCX(Entry.IconData, FCurrentIconPixels) then
    FHasCurrentIcon := True
  else
    FHasCurrentIcon := False;
  PaintBoxPreview.Invalidate;
end;

function TMainForm.BuildEntryFromPanel(const Existing: TAppEntry): TAppEntry;
begin
  Result := Existing;
  Result.Title := EditTitle.Text;
  Result.Desc := EditDesc.Text;
  Result.ExecPath := EditExec.Text;
  Result.Args := EditArgs.Text;
  Result.Flags := 0;
  if CheckPause.Checked then Result.Flags := Result.Flags or 1;
  if CheckClear.Checked then Result.Flags := Result.Flags or 2;
  { Icon fields (HasIcon/IconData) are left as-is from Existing; they are
    only changed via Import Icon / Clear Icon, never via the text fields. }
end;

function TMainForm.DoSave(const FileName: string): Boolean;
var
  Errors: TValidationErrors;
  ErrMsg: string;
begin
  Result := False;

  if not FDoc.Validate(Errors) then
  begin
    FHighlightIndex := Errors[0].EntryIndex;
    ListBoxEntries.ItemIndex := FHighlightIndex;
    LoadEntryToPanel(FHighlightIndex);
    ListBoxEntries.Invalidate;
    MessageDlg('Cannot save',
      Format('Entry %d: %s', [Errors[0].EntryIndex + 1, Errors[0].Msg]),
      mtError, [mbOK], 0);
    Exit;
  end;

  if not AtomicSaveDocument(FDoc, FileName, ErrMsg) then
  begin
    MessageDlg('Save failed', ErrMsg, mtError, [mbOK], 0);
    Exit;
  end;

  FHighlightIndex := -1;
  FCurrentFileName := FileName;
  ListBoxEntries.Invalidate;
  Result := True;
end;

{ ---------------------------------------------------------------- }
{ Owner-draw / paint }

procedure TMainForm.ListBoxEntriesDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  Entry: TAppEntry;
  IconPixels: TIndexGrid;
  HasThumb: Boolean;
  x, y, ThumbSize, PixelSize: Integer;
  TextLeft: Integer;
begin
  if (Index < 0) or (Index >= FDoc.Count) then Exit;
  Entry := FDoc.GetEntry(Index);

  with ListBoxEntries.Canvas do
  begin
    if odSelected in State then
    begin
      Brush.Color := clHighlight;
      Font.Color := clHighlightText;
    end
    else if Index = FHighlightIndex then
    begin
      Brush.Color := clRed;
      Font.Color := clWhite;
    end
    else
    begin
      Brush.Color := clWindow;
      Font.Color := clWindowText;
    end;
    FillRect(ARect);

    ThumbSize := (ARect.Bottom - ARect.Top) - 4;
    HasThumb := Entry.HasIcon and IconConvert.DecodeIconPCX(Entry.IconData, IconPixels);
    if HasThumb then
    begin
      PixelSize := ThumbSize div ICON_WIDTH;
      if PixelSize < 1 then PixelSize := 1;
      for y := 0 to ICON_HEIGHT - 1 do
        for x := 0 to ICON_WIDTH - 1 do
        begin
          Brush.Color := VgaColor(IconPixels[y * ICON_WIDTH + x]);
          FillRect(Rect(
            ARect.Left + 2 + x * PixelSize, ARect.Top + 2 + y * PixelSize,
            ARect.Left + 2 + (x + 1) * PixelSize, ARect.Top + 2 + (y + 1) * PixelSize));
        end;
      TextLeft := ARect.Left + 4 + (ICON_WIDTH * PixelSize) + 8;
    end
    else
      TextLeft := ARect.Left + 4;

    Brush.Style := bsClear;
    TextOut(TextLeft, ARect.Top + (ThumbSize div 2) - 6, Entry.Title);
    Brush.Style := bsSolid;
  end;
end;

procedure TMainForm.PaintBoxPreviewPaint(Sender: TObject);
var
  x, y, PixelSize: Integer;
begin
  with PaintBoxPreview.Canvas do
  begin
    Brush.Color := clBtnFace;
    FillRect(PaintBoxPreview.ClientRect);
    if not FHasCurrentIcon then Exit;

    PixelSize := PaintBoxPreview.Width div ICON_WIDTH;
    if PixelSize < 1 then PixelSize := 1;
    for y := 0 to ICON_HEIGHT - 1 do
      for x := 0 to ICON_WIDTH - 1 do
      begin
        Brush.Color := VgaColor(FCurrentIconPixels[y * ICON_WIDTH + x]);
        FillRect(Rect(x * PixelSize, y * PixelSize, (x + 1) * PixelSize, (y + 1) * PixelSize));
      end;
  end;
end;

{ ---------------------------------------------------------------- }
{ Selection / field events }

procedure TMainForm.ListBoxEntriesSelectionChange(Sender: TObject; User: Boolean);
begin
  LoadEntryToPanel(ListBoxEntries.ItemIndex);
end;

procedure TMainForm.EditFieldChange(Sender: TObject);
var
  Idx: Integer;
  Entry: TAppEntry;
begin
  if FUpdating then Exit;
  Idx := ListBoxEntries.ItemIndex;
  if (Idx < 0) or (Idx >= FDoc.Count) then Exit;
  Entry := BuildEntryFromPanel(FDoc.GetEntry(Idx));
  FDoc.SetEntry(Idx, Entry);
  { Keep the list row's title text in sync without losing selection. }
  ListBoxEntries.Items[Idx] := Entry.Title;
end;

procedure TMainForm.CheckFlagChange(Sender: TObject);
begin
  EditFieldChange(Sender);
end;

{ ---------------------------------------------------------------- }
{ Actions }

procedure TMainForm.ActionNewExecute(Sender: TObject);
begin
  FDoc.Clear;
  FCurrentFileName := '';
  FHighlightIndex := -1;
  RefreshList;
  ClearEditPanel;
end;

procedure TMainForm.ActionOpenExecute(Sender: TObject);
var
  Entries: TAppEntryArray;
begin
  if not OpenDialog1.Execute then Exit;
  try
    Entries := LoadRiffEntries(OpenDialog1.FileName);
  except
    on E: ERiffFormatError do
    begin
      MessageDlg('Open failed', E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FDoc.LoadEntries(Entries);
  FCurrentFileName := OpenDialog1.FileName;
  FHighlightIndex := -1;
  RefreshList;
  if FDoc.Count > 0 then
  begin
    ListBoxEntries.ItemIndex := 0;
    LoadEntryToPanel(0);
  end
  else
    ClearEditPanel;
end;

procedure TMainForm.ActionSaveExecute(Sender: TObject);
begin
  if FCurrentFileName <> '' then
  begin
    DoSave(FCurrentFileName);
    Exit;
  end;

  { New, unsaved document: default the save dialog's file name to
    LAUNCHER.DAT (8.3-safe), per Scenario "Default save file name is
    DOS-friendly". }
  SaveDialog1.FileName := 'LAUNCHER.DAT';
  if not SaveDialog1.Execute then Exit;
  DoSave(SaveDialog1.FileName);
end;

procedure TMainForm.ActionAddExecute(Sender: TObject);
var
  NewEntry: TAppEntry;
  ErrMsg: string;
begin
  FillChar(NewEntry, SizeOf(NewEntry), 0);
  NewEntry.Title := 'New Entry';
  NewEntry.Desc := '';
  NewEntry.ExecPath := '';
  NewEntry.Args := '';
  NewEntry.Flags := 0;
  NewEntry.HasIcon := False;
  SetLength(NewEntry.IconData, 0);

  if not FDoc.AddEntry(NewEntry, ErrMsg) then
  begin
    { Surfaces LauncherDoc's own MAX_APPS refusal message verbatim --
      Scenario "Entry limit message shown in the GUI". }
    MessageDlg('Cannot add entry', ErrMsg, mtError, [mbOK], 0);
    Exit;
  end;

  RefreshList;
  ListBoxEntries.ItemIndex := FDoc.Count - 1;
  LoadEntryToPanel(FDoc.Count - 1);
end;

procedure TMainForm.ActionRemoveExecute(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ListBoxEntries.ItemIndex;
  if (Idx < 0) or (Idx >= FDoc.Count) then Exit;
  FDoc.RemoveEntry(Idx);
  if FHighlightIndex = Idx then FHighlightIndex := -1;
  RefreshList;
  if Idx >= FDoc.Count then Idx := FDoc.Count - 1;
  if Idx >= 0 then
  begin
    ListBoxEntries.ItemIndex := Idx;
    LoadEntryToPanel(Idx);
  end
  else
    ClearEditPanel;
end;

procedure TMainForm.ActionUpExecute(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ListBoxEntries.ItemIndex;
  if Idx < 0 then Exit;
  if FDoc.MoveUp(Idx) then
  begin
    RefreshList;
    ListBoxEntries.ItemIndex := Idx - 1;
    LoadEntryToPanel(Idx - 1);
  end;
end;

procedure TMainForm.ActionDownExecute(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ListBoxEntries.ItemIndex;
  if Idx < 0 then Exit;
  if FDoc.MoveDown(Idx) then
  begin
    RefreshList;
    ListBoxEntries.ItemIndex := Idx + 1;
    LoadEntryToPanel(Idx + 1);
  end;
end;

procedure TMainForm.ActionImportIconExecute(Sender: TObject);
var
  Idx: Integer;
  Entry: TAppEntry;
  SrcPicture: TPicture;
  ScaledBmp: TBitmap;
  x, y: Integer;
  Pixels: TIndexGrid;
  RGBValue: Longint;
  R, G, B: Byte;
begin
  Idx := ListBoxEntries.ItemIndex;
  if (Idx < 0) or (Idx >= FDoc.Count) then
  begin
    MessageDlg('Import Icon', 'Select an entry first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if not OpenIconDialog1.Execute then Exit;

  SrcPicture := TPicture.Create;
  ScaledBmp := TBitmap.Create;
  try
    try
      SrcPicture.LoadFromFile(OpenIconDialog1.FileName);
    except
      on E: Exception do
      begin
        MessageDlg('Import Icon failed', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;

    ScaledBmp.SetSize(ICON_WIDTH, ICON_HEIGHT);
    ScaledBmp.Canvas.StretchDraw(Rect(0, 0, ICON_WIDTH, ICON_HEIGHT), SrcPicture.Graphic);

    for y := 0 to ICON_HEIGHT - 1 do
      for x := 0 to ICON_WIDTH - 1 do
      begin
        RGBValue := ColorToRGB(ScaledBmp.Canvas.Pixels[x, y]);
        R := RGBValue and $FF;
        G := (RGBValue shr 8) and $FF;
        B := (RGBValue shr 16) and $FF;
        Pixels[y * ICON_WIDTH + x] := QuantizeColor(R, G, B);
      end;
  finally
    ScaledBmp.Free;
    SrcPicture.Free;
  end;

  Entry := FDoc.GetEntry(Idx);
  Entry.HasIcon := True;
  Entry.IconData := EncodeIconPCX(Pixels);
  FDoc.SetEntry(Idx, Entry);

  FCurrentIconPixels := Pixels;
  FHasCurrentIcon := True;
  PaintBoxPreview.Invalidate;
  ListBoxEntries.Invalidate;
end;

procedure TMainForm.ActionClearIconExecute(Sender: TObject);
var
  Idx: Integer;
  Entry: TAppEntry;
begin
  Idx := ListBoxEntries.ItemIndex;
  if (Idx < 0) or (Idx >= FDoc.Count) then Exit;
  Entry := FDoc.GetEntry(Idx);
  Entry.HasIcon := False;
  SetLength(Entry.IconData, 0);
  FDoc.SetEntry(Idx, Entry);

  FHasCurrentIcon := False;
  PaintBoxPreview.Invalidate;
  ListBoxEntries.Invalidate;
end;

end.
