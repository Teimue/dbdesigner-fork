unit Main;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit Main.pas
// -------------
// Description
//   Main form of the Test Data Generator plugin: choose the tables of the
//   model and the number of rows, the target database and a few options, and
//   get a script of INSERT statements (see TestDataGen.pas) to copy, to save
//   or to execute in a database (TestDataExec.pas).
//
//   Usage: DBDplugin_TestDataGenerator modelfilename.xml
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses
  SysUtils, Types, Classes, Variants, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, Buttons, Grids, Spin, Clipbrd,
  EERModel;

type

  { TMainForm }

  TMainForm = class(TForm)
    TablesLbl: TLabel;
    TablesGrid: TStringGrid;
    AllBtn: TButton;
    NoneBtn: TButton;
    RowsForAllLbl: TLabel;
    RowsForAllEd: TSpinEdit;
    SetRowsBtn: TButton;

    TargetLbl: TLabel;
    TargetCBox: TComboBox;
    LanguageLbl: TLabel;
    LanguageCBox: TComboBox;
    SeedLbl: TLabel;
    SeedEd: TSpinEdit;
    NullLbl: TLabel;
    NullEd: TSpinEdit;
    DeleteCBox: TCheckBox;
    SkipAutoIncCBox: TCheckBox;
    CommitCBox: TCheckBox;

    GenerateBtn: TButton;
    CopyBtn: TButton;
    SaveBtn: TButton;
    ExecBtn: TButton;
    CloseBtn: TButton;

    OutputLbl: TLabel;
    OutputMemo: TMemo;
    StatusLbl: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    procedure AllBtnClick(Sender: TObject);
    procedure SetRowsBtnClick(Sender: TObject);
    procedure GenerateBtnClick(Sender: TObject);
    procedure CopyBtnClick(Sender: TObject);
    procedure SaveBtnClick(Sender: TObject);
    procedure ExecBtnClick(Sender: TObject);
    procedure CloseBtnClick(Sender: TObject);
  private
    { Private declarations }
    Tables: TList;       //the tables of the model in the order of the grid
    German: Boolean;     //language of the user interface

    function Tr(const en, de: string): string;
    procedure InitControls;
    //The script for the selected tables and options. False when no table
    //is selected. AppendToDatabase: the keys go on after those of the rows
    //the connected database has already
    function BuildScript(Script: TStrings; out Statements, TableCount: integer;
      AppendToDatabase: Boolean = False): Boolean;
  public
    { Public declarations }
    EERModel: TEERModel;
  end;

var
  MainForm: TMainForm;

implementation

uses MainDM, EERDM, DBDM, TestDataGen, TestDataExec;

{$R *.lfm}

const
  colCheck = 0;
  colTable = 1;
  colRows = 2;

function TMainForm.Tr(const en, de: string): string;
begin
  if(German)then
    Result:=de
  else
    Result:=en;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var i: integer;
begin
  Tables:=TList.Create;
  EERModel:=nil;

  //Create Main DataModule, containing general functions
  DMMain:=TDMMain.Create(self);
  //The dialogs are scaled to the application font and the DPI
  DMMain.FitDialogsToFont:=True;
  DMMain.MainFormIsDialog:=True;
  //Create EER DateModule, containing additional functions for the EERModel
  DMEER:=TDMEER.Create(self);
  //The database connections, to execute the script
  DMDB:=TDMDB.Create(self);

  //Font and layout. The texts are set below: the translations of the main
  //program belong to its own forms of the same name
  DMMain.InitForm(self, False, False);

  //The language of the main program
  DMMain.LoadLanguageFromIniFile;
  DMMain.LoadTranslatedMessages;
  German:=(CompareText(DMMain.GetLanguageCode, 'de')=0);

  if(ParamCount<1)then
  begin
    MessageDlg(Tr('You have to specify a model.', 'Es muss ein Modell angegeben werden.')+#13#10#13#10+
      Tr('Usage', 'Aufruf')+': DBDplugin_TestDataGenerator modelfilename.xml', mtError,
      [mbOK], 0);
    Application.Terminate;
  end
  else
  begin
    for i:=1 to ParamCount do
      if(FileExists(ParamStr(i)))then
      begin
        EERModel:=TEERModel.Create(self);
        //the model is needed for its data only
        EERModel.Visible:=False;
        EERModel.LoadFromFile(ParamStr(i), True, False, False);
        DMEER.SetCurrentWorkTool(wtPointer);
        break;
      end;
  end;

  InitControls;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Tables.Free;
  EERModel.Free;
end;

procedure TMainForm.InitControls;
var i: integer;
  T: TEERTable;
begin
  Caption:=Tr('Test Data Generator', 'Testdatengenerator');
  if(EERModel<>nil)then
    Caption:=Caption+' - '+EERModel.GetModelName;

  TablesLbl.Caption:=Tr('Tables', 'Tabellen');
  AllBtn.Caption:=Tr('All', 'Alle');
  NoneBtn.Caption:=Tr('None', 'Keine');
  RowsForAllLbl.Caption:=Tr('Rows:', 'Zeilen:');
  SetRowsBtn.Caption:=Tr('Set for all', 'Für alle setzen');
  TargetLbl.Caption:=Tr('Target database:', 'Zieldatenbank:');
  LanguageLbl.Caption:=Tr('Language of the data:', 'Sprache der Daten:');
  SeedLbl.Caption:=Tr('Seed:', 'Startwert:');
  SeedEd.Hint:=Tr('The same seed gives the same data', 'Derselbe Startwert ergibt dieselben Daten');
  SeedEd.ShowHint:=True;
  NullLbl.Caption:=Tr('NULL values (%):', 'NULL-Werte (%):');
  DeleteCBox.Caption:=Tr('Delete the existing rows first (DELETE)', 'Vorhandene Zeilen zuerst löschen (DELETE)');
  SkipAutoIncCBox.Caption:=Tr('Leave auto increment columns to the database', 'Auto-Increment-Spalten der Datenbank überlassen');
  CommitCBox.Caption:=Tr('COMMIT at the end', 'COMMIT am Ende');
  GenerateBtn.Caption:=Tr('Generate', 'Erzeugen');
  CopyBtn.Caption:=Tr('Copy', 'Kopieren');
  SaveBtn.Caption:=Tr('Save ...', 'Speichern ...');
  ExecBtn.Caption:=Tr('Execute in database ...', 'In Datenbank ausführen ...');
  CloseBtn.Caption:=Tr('Close', 'Schließen');
  OutputLbl.Caption:=Tr('Script', 'Skript');
  StatusLbl.Caption:='';

  //a font of fixed width in the size of the application font
  OutputMemo.Font.Name:='Consolas';
  OutputMemo.Font.Size:=DMMain.ApplicationFontSize;

  LanguageCBox.Items.Clear;
  LanguageCBox.Items.Add('Deutsch');
  LanguageCBox.Items.Add('English');
  LanguageCBox.ItemIndex:=Ord(Not(German));

  TestDataTargets(TargetCBox.Items);
  if(EERModel<>nil)then
    TargetCBox.ItemIndex:=TargetCBox.Items.IndexOf(TargetDBOfModel(EERModel));
  if(TargetCBox.ItemIndex<0)then
    TargetCBox.ItemIndex:=TargetCBox.Items.IndexOf('My SQL');

  //The tables: checked, name, number of rows
  TablesGrid.Columns.Clear;
  with TablesGrid.Columns.Add do
  begin
    ButtonStyle:=cbsCheckboxColumn;
    Title.Caption:='';
    Width:=DMMain.ScaleForFont(24);
  end;
  with TablesGrid.Columns.Add do
  begin
    Title.Caption:=Tr('Table', 'Tabelle');
    ReadOnly:=True;
    Width:=DMMain.ScaleForFont(210);
  end;
  with TablesGrid.Columns.Add do
  begin
    Title.Caption:=Tr('Rows', 'Zeilen');
    Alignment:=taRightJustify;
    Width:=DMMain.ScaleForFont(60);
  end;
  TablesGrid.DefaultRowHeight:=DMMain.ScaleForFont(18);
  //the name of the table takes the rest of the width
  TablesGrid.Columns[colCheck].SizePriority:=0;
  TablesGrid.Columns[colRows].SizePriority:=0;
  TablesGrid.AutoFillColumns:=True;

  Tables.Clear;
  if(EERModel<>nil)then
    EERModel.GetEERObjectList([EERTable], Tables);

  TablesGrid.RowCount:=Tables.Count+1;
  for i:=0 to Tables.Count-1 do
  begin
    T:=TEERTable(Tables[i]);
    //a table of a linked model is not part of the database of this model
    if(TableHasSQL(EERModel, T))then
      TablesGrid.Cells[colCheck, i+1]:='1'
    else
      TablesGrid.Cells[colCheck, i+1]:='0';
    TablesGrid.Cells[colTable, i+1]:=T.ObjName;
    TablesGrid.Cells[colRows, i+1]:=IntToStr(RowsForAllEd.Value);
  end;

  GenerateBtn.Enabled:=(Tables.Count>0);
  ExecBtn.Enabled:=(Tables.Count>0);
  CopyBtn.Enabled:=False;
  SaveBtn.Enabled:=False;
end;

procedure TMainForm.AllBtnClick(Sender: TObject);
var i: integer;
begin
  //AllBtn and NoneBtn
  for i:=1 to TablesGrid.RowCount-1 do
    if(Sender=AllBtn)then
      TablesGrid.Cells[colCheck, i]:='1'
    else
      TablesGrid.Cells[colCheck, i]:='0';
end;

procedure TMainForm.SetRowsBtnClick(Sender: TObject);
var i: integer;
begin
  for i:=1 to TablesGrid.RowCount-1 do
    TablesGrid.Cells[colRows, i]:=IntToStr(RowsForAllEd.Value);
end;

function TMainForm.BuildScript(Script: TStrings; out Statements, TableCount: integer;
  AppendToDatabase: Boolean = False): Boolean;
var Opt: TTestDataOptions;
  Selected: TList;
  RowCounts, Offsets: TStringList;
  i: integer;
begin
  Result:=False;
  Statements:=0;
  TableCount:=0;
  if(EERModel=nil)then
    Exit;

  //a value that is still being edited
  TablesGrid.EditorMode:=False;

  Selected:=TList.Create;
  RowCounts:=TStringList.Create;
  Offsets:=TStringList.Create;
  Screen.Cursor:=crHourGlass;
  try
    for i:=0 to Tables.Count-1 do
      if(TablesGrid.Cells[colCheck, i+1]='1')then
      begin
        Selected.Add(Tables[i]);
        RowCounts.Values[TEERTable(Tables[i]).ObjName]:=
          IntToStr(StrToIntDef(Trim(TablesGrid.Cells[colRows, i+1]), RowsForAllEd.Value));
      end;

    if(Selected.Count=0)then
    begin
      Screen.Cursor:=crDefault;
      MessageDlg(Tr('Please select at least one table.', 'Bitte mindestens eine Tabelle auswählen.'),
        mtInformation, [mbOK], 0);
      Exit;
    end;

    Opt:=DefaultTestDataOptions;
    Opt.TargetDB:=TargetCBox.Text;
    Opt.DefaultRows:=RowsForAllEd.Value;
    Opt.Seed:=SeedEd.Value;
    Opt.NullPercent:=NullEd.Value;
    Opt.German:=(LanguageCBox.ItemIndex=0);
    Opt.DeleteFirst:=DeleteCBox.Checked;
    Opt.SkipAutoInc:=SkipAutoIncCBox.Checked;
    Opt.Commit:=CommitCBox.Checked;

    //New rows beside the existing ones: their keys must not be taken
    if(AppendToDatabase)and(Not(Opt.DeleteFirst))then
    begin
      ExistingKeyOffsets(Selected, Opt.TargetDB, Offsets);
      Opt.KeyOffsets:=Offsets;
    end;

    Script.Clear;
    Statements:=GenerateTestData(EERModel, Selected, RowCounts, Opt, Script);
    TableCount:=Selected.Count;

    OutputMemo.Lines.BeginUpdate;
    try
      OutputMemo.Lines.Assign(Script);
    finally
      OutputMemo.Lines.EndUpdate;
    end;

    StatusLbl.Caption:=Format(Tr('%d INSERT statements for %d tables', '%d INSERT-Anweisungen für %d Tabellen'),
      [Statements, TableCount]);
    CopyBtn.Enabled:=True;
    SaveBtn.Enabled:=True;
    Result:=True;
  finally
    Screen.Cursor:=crDefault;
    Selected.Free;
    RowCounts.Free;
    Offsets.Free;
  end;
end;

procedure TMainForm.GenerateBtnClick(Sender: TObject);
var Script: TStringList;
  n, t: integer;
begin
  Script:=TStringList.Create;
  try
    BuildScript(Script, n, t);
  finally
    Script.Free;
  end;
end;

procedure TMainForm.ExecBtnClick(Sender: TObject);
var Conn: TDBConn;
  Script: TStringList;
  n, t, Done: integer;
  Target, Msg, ErrMsg, ErrStmt, ConnText: string;
begin
  if(EERModel=nil)then
    Exit;

  //Which database?
  DMDB.DisconnectFromDB;
  Conn:=DMDB.GetUserSelectedDBConn(EERModel.DefSyncDBConn);
  if(Conn=nil)then
    Exit;
  DMDB.ConnectToDB(Conn);
  if(DMDB.CurrentDBConn=nil)then
    Exit;

  Script:=TStringList.Create;
  try
    //The script in the SQL of this database
    Target:=TargetDBOfDriver(Conn.DriverName);
    if(Target<>'')and(TargetCBox.Items.IndexOf(Target)>=0)then
      TargetCBox.ItemIndex:=TargetCBox.Items.IndexOf(Target);

    if(Not(BuildScript(Script, n, t, True)))then
      Exit;

    ConnText:=Conn.Name;
    if(Conn.Params.Values['Database']<>'')then
      ConnText:=ConnText+' ('+Conn.Params.Values['Database']+')';

    Msg:=Format(Tr('Insert %d rows into %d tables of the database connection'#13#10'%s?',
      '%d Zeilen in %d Tabellen der Datenbankverbindung'#13#10'%s einfügen?'), [n, t, ConnText]);
    if(DeleteCBox.Checked)then
      Msg:=Msg+#13#10#13#10+Tr('ALL existing rows of these tables are deleted first.',
        'Vorher werden ALLE vorhandenen Zeilen dieser Tabellen gelöscht.')
    else
      Msg:=Msg+#13#10#13#10+Tr('The existing rows are kept, the keys of the new rows follow theirs.',
        'Die vorhandenen Zeilen bleiben erhalten, die Schlüssel der neuen Zeilen schließen an.');

    if(MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0)<>mrYes)then
    begin
      StatusLbl.Caption:=Tr('Nothing was written to the database.', 'Es wurde nichts in die Datenbank geschrieben.');
      Exit;
    end;

    Screen.Cursor:=crHourGlass;
    try
      Done:=ExecuteTestDataScript(Script, ErrMsg, ErrStmt);
    finally
      Screen.Cursor:=crDefault;
    end;

    if(Done<0)then
    begin
      StatusLbl.Caption:=Tr('Error - nothing was written to the database.',
        'Fehler - es wurde nichts in die Datenbank geschrieben.');
      MessageDlg(Tr('The database has rejected a statement. All changes of the script were rolled back.',
        'Die Datenbank hat eine Anweisung abgelehnt. Alle Änderungen des Skripts wurden zurückgenommen.')+
        #13#10#13#10+ErrMsg+#13#10#13#10+Copy(ErrStmt, 1, 600), mtError, [mbOK], 0);
    end
    else
      StatusLbl.Caption:=Format(Tr('%d rows written to %s (%d statements).',
        '%d Zeilen in %s geschrieben (%d Anweisungen).'), [n, ConnText, Done]);
  finally
    Script.Free;
    DMDB.DisconnectFromDB;
  end;
end;

procedure TMainForm.CopyBtnClick(Sender: TObject);
begin
  Clipboard.AsText:=OutputMemo.Lines.Text;
  StatusLbl.Caption:=Tr('The script is in the clipboard.', 'Das Skript liegt in der Zwischenablage.');
end;

procedure TMainForm.SaveBtnClick(Sender: TObject);
var theSaveDialog: TSaveDialog;
begin
  theSaveDialog:=TSaveDialog.Create(nil);
  try
    theSaveDialog.Title:=Tr('Save the script as ...', 'Skript speichern unter ...');
    theSaveDialog.DefaultExt:='sql';
    theSaveDialog.Filter:=Tr('SQL files', 'SQL-Dateien')+' (*.sql)|*.sql|'+
      Tr('All files', 'Alle Dateien')+' (*.*)|*.*';
    theSaveDialog.Options:=theSaveDialog.Options+[ofOverwritePrompt];
    if(EERModel<>nil)then
      theSaveDialog.FileName:=ChangeFileExt(ExtractFileName(EERModel.ModelFilename), '')+'_testdata.sql';

    if(theSaveDialog.Execute)then
    begin
      //UTF-8, as the LCL holds the text
      OutputMemo.Lines.SaveToFile(theSaveDialog.FileName);
      StatusLbl.Caption:=Tr('Saved: ', 'Gespeichert: ')+theSaveDialog.FileName;
    end;
  finally
    theSaveDialog.Free;
  end;
end;

procedure TMainForm.CloseBtnClick(Sender: TObject);
begin
  Close;
end;

end.
