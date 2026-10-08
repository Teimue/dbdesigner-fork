unit Main;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit Main.pas
// -------------
// Description
//   Main form of the Data Browser plugin: connect to a database and look at
//   the rows of the tables of the model (or of all tables of the database).
//   Filter with a WHERE condition, sort with a click on a column title,
//   follow a foreign key to the referenced row with a double click. The
//   browser only reads.
//
//   The rows are copied into the grid and the query is closed again, so no
//   lock stays on the database while the window is open.
//
//   Usage: DBDplugin_DataBrowser modelfilename.xml
//            [--sqlite <database file>] [--table <table name>]
//   --sqlite opens a SQLite database file at once, without a stored database
//   connection; --table shows this table at the start.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses
  SysUtils, Types, Classes, Variants, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, Buttons, Grids, Spin, LCLType,
  EERModel, DBDM;

type

  { TMainForm }

  TMainForm = class(TForm)
    TopPnl: TPanel;
    ConnBtn: TButton;
    ConnLbl: TLabel;

    LeftPnl: TPanel;
    TablesLbl: TLabel;
    TablesLBox: TListBox;
    AllTablesCBox: TCheckBox;
    LeftSplitter: TSplitter;

    ClientPnl: TPanel;
    FilterPnl: TPanel;
    FilterLbl: TLabel;
    FilterEd: TEdit;
    LimitLbl: TLabel;
    LimitEd: TSpinEdit;
    RefreshBtn: TButton;
    ClearBtn: TButton;
    DataGrid: TStringGrid;
    CellSplitter: TSplitter;
    CellMemo: TMemo;
    StatusPnl: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    procedure ConnBtnClick(Sender: TObject);
    procedure AllTablesCBoxClick(Sender: TObject);
    procedure TablesLBoxClick(Sender: TObject);
    procedure RefreshBtnClick(Sender: TObject);
    procedure ClearBtnClick(Sender: TObject);
    procedure FilterEdKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

    procedure DataGridHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
    procedure DataGridSelection(Sender: TObject; aCol, aRow: Integer);
    procedure DataGridDblClick(Sender: TObject);
    procedure DataGridPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
  private
    { Private declarations }
    German: Boolean;         //language of the user interface
    DBType: string;          //database type of the connection, see DataBrowserSQL
    CurTable: TEERTable;     //the table that is shown; nil: none, or not in the model
    CurTableName: string;
    SortField: string;
    SortDesc: Boolean;
    FieldNames: TStringList; //the columns of the grid
    FieldIsNumber: array of Boolean;
    FileConn: TDBConn;       //the connection of --sqlite

    function Tr(const en, de: string): string;
    procedure InitControls;
    //--sqlite and --table of the command line
    procedure OpenFromCommandLine;
    procedure AfterConnect(Conn: TDBConn);
    function Connected: Boolean;
    procedure FillTables;
    function SQLTableName: string;
    //The table and column a column of the current table references, False
    //when it is no foreign key
    function ReferencedColumn(const ColName: string; out RefTable: TEERTable;
      out RefColumn: string): Boolean;
    procedure ShowTable(const TableName: string; T: TEERTable; const Filter: string);
    procedure LoadData;
    procedure ClearGrid;
  public
    { Public declarations }
    EERModel: TEERModel;
  end;

var
  MainForm: TMainForm;

implementation

uses DB, SQLDB, MainDM, EERDM, DataBrowserSQL;

{$R *.lfm}

const
  //marks a cell that holds NULL
  NullMark = 1;
  NullText = '(NULL)';
  //no text in the grid is longer; the whole value is in the memo below
  MaxCellText = 2000;

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
  FieldNames:=TStringList.Create;
  FileConn:=nil;
  EERModel:=nil;
  CurTable:=nil;

  //Create Main DataModule, containing general functions
  DMMain:=TDMMain.Create(self);
  //The dialogs are scaled to the application font and the DPI
  DMMain.FitDialogsToFont:=True;
  DMMain.MainFormIsDialog:=True;
  //Create EER DateModule, containing additional functions for the EERModel
  DMEER:=TDMEER.Create(self);
  //The database connections
  DMDB:=TDMDB.Create(self);

  //Font and layout. The texts are set in InitControls: the translations of
  //the main program belong to its own forms of the same name
  DMMain.InitForm(self, False, False);

  //The language of the main program
  DMMain.LoadLanguageFromIniFile;
  DMMain.LoadTranslatedMessages;
  German:=(CompareText(DMMain.GetLanguageCode, 'de')=0);

  //The model gives the tables and their foreign keys. Without one the
  //browser shows the tables of the database
  for i:=1 to ParamCount do
    if(FileExists(ParamStr(i)))and(CompareText(ExtractFileExt(ParamStr(i)), '.xml')=0)then
    begin
      EERModel:=TEERModel.Create(self);
      //the model is needed for its data only
      EERModel.Visible:=False;
      EERModel.LoadFromFile(ParamStr(i), True, False, False);
      DMEER.SetCurrentWorkTool(wtPointer);
      break;
    end;

  InitControls;
  OpenFromCommandLine;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  try
    DMDB.DisconnectFromDB;
  except
  end;
  FileConn.Free;
  FieldNames.Free;
  EERModel.Free;
end;

procedure TMainForm.InitControls;
begin
  Caption:=Tr('Data Browser', 'Datenbrowser');
  if(EERModel<>nil)then
    Caption:=Caption+' - '+EERModel.GetModelName;

  ConnBtn.Caption:=Tr('Connect ...', 'Verbinden ...');
  ConnLbl.Caption:=Tr('Not connected to a database', 'Nicht mit einer Datenbank verbunden');
  TablesLbl.Caption:=Tr('Tables', 'Tabellen');
  AllTablesCBox.Caption:=Tr('All tables of the database', 'Alle Tabellen der Datenbank');
  FilterLbl.Caption:=Tr('Filter (WHERE):', 'Filter (WHERE):');
  FilterEd.Hint:=Tr('A condition in SQL, e.g. name LIKE ''A%'' - Enter applies it',
    'Eine Bedingung in SQL, z. B. name LIKE ''A%'' - Enter wendet sie an');
  FilterEd.ShowHint:=True;
  LimitLbl.Caption:=Tr('Max. rows:', 'Max. Zeilen:');
  RefreshBtn.Caption:=Tr('Refresh', 'Aktualisieren');
  ClearBtn.Caption:=Tr('Clear filter', 'Filter löschen');
  StatusPnl.Caption:=' '+Tr('Connect to a database to see the rows of the tables.',
    'Mit einer Datenbank verbinden, um die Zeilen der Tabellen zu sehen.');

  //a model without tables: the tables of the database
  if(EERModel=nil)then
  begin
    AllTablesCBox.Checked:=True;
    AllTablesCBox.Enabled:=False;
  end;

  DataGrid.DefaultRowHeight:=DMMain.ScaleForFont(18);
  CellMemo.Font.Name:='Consolas';
  CellMemo.Font.Size:=DMMain.ApplicationFontSize;
  CellMemo.Font.Color:=clWindowText;

  ClearGrid;
  FillTables;
end;

function TMainForm.Connected: Boolean;
begin
  Result:=(DMDB.CurrentDBConn<>nil);
end;

procedure TMainForm.ConnBtnClick(Sender: TObject);
var Conn: TDBConn;
  def: string;
begin
  def:='';
  if(EERModel<>nil)then
    def:=EERModel.DefQueryDBConn;

  Conn:=DMDB.GetUserSelectedDBConn(def);
  if(Conn=nil)then
    Exit;

  DMDB.DisconnectFromDB;
  ClearGrid;
  CurTable:=nil;
  CurTableName:='';

  DMDB.ConnectToDB(Conn);
  AfterConnect(Conn);
end;

procedure TMainForm.AfterConnect(Conn: TDBConn);
begin
  if(Not(Connected))then
  begin
    ConnLbl.Caption:=Tr('Not connected to a database', 'Nicht mit einer Datenbank verbunden');
    FillTables;
    Exit;
  end;

  DBType:=BrowserDBType(Conn.DriverName);

  ConnLbl.Caption:=Conn.Name;
  if(Conn.Params.Values['Database']<>'')then
    ConnLbl.Caption:=ConnLbl.Caption+'  ('+Conn.Params.Values['Database']+')';

  FillTables;
  StatusPnl.Caption:=' '+Tr('Select a table.', 'Eine Tabelle auswählen.');
end;

procedure TMainForm.OpenFromCommandLine;
var i: integer;
  DBFile, TableName: string;
begin
  DBFile:='';
  TableName:='';
  for i:=1 to ParamCount-1 do
  begin
    if(CompareText(ParamStr(i), '--sqlite')=0)then
      DBFile:=ParamStr(i+1);
    if(CompareText(ParamStr(i), '--table')=0)then
      TableName:=ParamStr(i+1);
  end;

  if(DBFile='')then
    Exit;
  if(Not(FileExists(DBFile)))then
  begin
    StatusPnl.Caption:=' '+Tr('File not found: ', 'Datei nicht gefunden: ')+DBFile;
    Exit;
  end;

  FileConn:=TDBConn.Create;
  FileConn.Name:=ExtractFileName(DBFile);
  FileConn.DriverName:='SQLite';
  FileConn.Params.Values['Database']:=DBFile;
  try
    DMDB.ConnectToDB(FileConn);
  except
    on E: Exception do
      StatusPnl.Caption:=' '+E.Message;
  end;
  AfterConnect(FileConn);

  if(Connected)and(TableName<>'')then
    ShowTable(TableName, nil, '');
end;

procedure TMainForm.FillTables;
var theList: TStringList;
  Objs: TList;
  i: integer;
begin
  TablesLBox.Items.BeginUpdate;
  theList:=TStringList.Create;
  Objs:=TList.Create;
  try
    TablesLBox.Items.Clear;

    if(AllTablesCBox.Checked)then
    begin
      //The tables the database has. ShowTable finds the table of the model
      //with the same name, for its foreign keys
      if(Connected)then
      begin
        try
          DMDB.GetDBTables(theList);
        except
          on E: Exception do
            StatusPnl.Caption:=' '+E.Message;
        end;
        theList.Sort;
        TablesLBox.Items.Assign(theList);
      end;
    end
    else if(EERModel<>nil)then
    begin
      EERModel.GetEERObjectList([EERTable], Objs);
      for i:=0 to Objs.Count-1 do
        theList.AddObject(TEERTable(Objs[i]).ObjName, TObject(Objs[i]));
      theList.Sort;
      TablesLBox.Items.Assign(theList);
    end;
  finally
    theList.Free;
    Objs.Free;
    TablesLBox.Items.EndUpdate;
  end;
end;

procedure TMainForm.AllTablesCBoxClick(Sender: TObject);
begin
  FillTables;
end;

procedure TMainForm.TablesLBoxClick(Sender: TObject);
var i: integer;
begin
  i:=TablesLBox.ItemIndex;
  if(i<0)then
    Exit;

  if(Not(Connected))then
  begin
    StatusPnl.Caption:=' '+Tr('Connect to a database first.', 'Zuerst mit einer Datenbank verbinden.');
    Exit;
  end;

  //another table: its own filter and order
  ShowTable(TablesLBox.Items[i], TEERTable(TablesLBox.Items.Objects[i]), '');
end;

procedure TMainForm.ShowTable(const TableName: string; T: TEERTable; const Filter: string);
var i: integer;
  Objs: TList;
begin
  CurTableName:=TableName;
  CurTable:=T;

  //A table from the list of the database: the table of the model with
  //this name, for its foreign keys
  if(CurTable=nil)and(EERModel<>nil)then
  begin
    Objs:=TList.Create;
    try
      EERModel.GetEERObjectList([EERTable], Objs);
      for i:=0 to Objs.Count-1 do
        if(CompareText(TEERTable(Objs[i]).ObjName, TableName)=0)then
          CurTable:=TEERTable(Objs[i]);
    finally
      Objs.Free;
    end;
  end;

  SortField:='';
  SortDesc:=False;
  FilterEd.Text:=Filter;

  i:=TablesLBox.Items.IndexOf(TableName);
  if(i>=0)and(TablesLBox.ItemIndex<>i)then
    TablesLBox.ItemIndex:=i;

  LoadData;
end;

function TMainForm.SQLTableName: string;
begin
  //a table of the model in the list of the model: with its table prefix
  if(CurTable<>nil)and(DBType=dbtMySQL)and(Not(AllTablesCBox.Checked))then
    Result:=CurTable.GetSQLTableName
  else
    Result:=BrowserName(CurTableName, DBType, DMEER.EncloseNames);
end;

function TMainForm.ReferencedColumn(const ColName: string; out RefTable: TEERTable;
  out RefColumn: string): Boolean;
var i, k: integer;
  Rel: TEERRel;
begin
  Result:=False;
  RefTable:=nil;
  RefColumn:='';
  if(CurTable=nil)then
    Exit;

  for i:=0 to CurTable.RelEnd.Count-1 do
  begin
    Rel:=TEERRel(CurTable.RelEnd[i]);
    if(Rel.DestTbl<>CurTable)then
      continue;
    for k:=0 to Rel.FKFields.Count-1 do
      if(CompareText(Rel.FKFields.ValueFromIndex[k], ColName)=0)then
      begin
        RefTable:=TEERTable(Rel.SrcTbl);
        RefColumn:=Rel.FKFields.Names[k];
        Result:=True;
        Exit;
      end;
  end;
end;

procedure TMainForm.ClearGrid;
begin
  DataGrid.Columns.Clear;
  DataGrid.RowCount:=1;
  DataGrid.ColCount:=1;
  DataGrid.FixedCols:=1;
  DataGrid.ColWidths[0]:=DMMain.ScaleForFont(36);
  FieldNames.Clear;
  SetLength(FieldIsNumber, 0);
  CellMemo.Lines.Clear;
end;

procedure TMainForm.LoadData;
var Q: SQLDB.TSQLQuery;
  Trans: SQLDB.TSQLTransaction;
  stmt, s, OrderBy, ColTitle: string;
  c, r, Limit, w, MaxW: integer;
  F: TField;
  More: Boolean;
  t0: QWord;
  RefT: TEERTable;
  RefC: string;
begin
  if(Not(Connected))or(CurTableName='')then
    Exit;

  Limit:=LimitEd.Value;
  OrderBy:='';
  if(SortField<>'')then
    OrderBy:=BrowserName(SortField, DBType, DMEER.EncloseNames);

  //one row more shows that there are more
  if(Limit>0)then
    stmt:=BrowserSelect(SQLTableName, DBType, FilterEd.Text, OrderBy, SortDesc, Limit+1)
  else
    stmt:=BrowserSelect(SQLTableName, DBType, FilterEd.Text, OrderBy, SortDesc, 0);

  Trans:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
  if(Not(Trans.Active))then
    Trans.StartTransaction;

  Screen.Cursor:=crHourGlass;
  DataGrid.BeginUpdate;
  Q:=SQLDB.TSQLQuery.Create(nil);
  try
    Q.DataBase:=DMDB.SQLConn;
    Q.Transaction:=Trans;
    //a colon in the filter is no parameter
    Q.ParamCheck:=False;
    Q.ReadOnly:=True;
    Q.SQL.Text:=stmt;

    t0:=GetTickCount64;
    try
      Q.Open;
    except
      on E: Exception do
      begin
        try
          Trans.RollbackRetaining;
        except
        end;
        ClearGrid;
        StatusPnl.Caption:=' '+Tr('Error: ', 'Fehler: ')+
          StringReplace(StringReplace(E.Message, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
        CellMemo.Lines.Text:=E.Message+LineEnding+LineEnding+stmt;
        Exit;
      end;
    end;

    ClearGrid;

    //The columns. A foreign key is marked: a double click follows it
    SetLength(FieldIsNumber, Q.FieldCount);
    for c:=0 to Q.FieldCount-1 do
    begin
      F:=Q.Fields[c];
      FieldNames.Add(F.FieldName);
      FieldIsNumber[c]:=(F.DataType in [ftSmallint, ftInteger, ftWord, ftLargeint,
        ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftAutoInc]);

      ColTitle:=F.FieldName;
      if(ReferencedColumn(F.FieldName, RefT, RefC))then
        ColTitle:=ColTitle+' >';
      if(CompareText(F.FieldName, SortField)=0)then
      begin
        if(SortDesc)then
          ColTitle:=ColTitle+' (Z-A)'
        else
          ColTitle:=ColTitle+' (A-Z)';
      end;

      with DataGrid.Columns.Add do
      begin
        Title.Caption:=ColTitle;
        if(FieldIsNumber[c])then
          Alignment:=taRightJustify;
      end;
    end;

    //The rows
    r:=0;
    More:=False;
    while(Not(Q.EOF))do
    begin
      if(Limit>0)and(r>=Limit)then
      begin
        More:=True;
        break;
      end;

      inc(r);
      DataGrid.RowCount:=r+1;
      DataGrid.Cells[0, r]:=IntToStr(r);
      for c:=0 to Q.FieldCount-1 do
      begin
        F:=Q.Fields[c];
        if(F.IsNull)then
        begin
          DataGrid.Cells[c+1, r]:=NullText;
          DataGrid.Objects[c+1, r]:=TObject(PtrInt(NullMark));
        end
        else if(F.DataType in [ftBlob, ftGraphic, ftBytes, ftVarBytes, ftOraBlob])then
          DataGrid.Cells[c+1, r]:='(BLOB, '+IntToStr(Length(F.AsString))+' Bytes)'
        else
        begin
          s:=F.AsString;
          if(Length(s)>MaxCellText)then
            s:=Copy(s, 1, MaxCellText)+' ...';
          DataGrid.Cells[c+1, r]:=s;
        end;
      end;

      Q.Next;
    end;

    Q.Close;
    //nothing stays open on the database
    try
      Trans.CommitRetaining;
    except
    end;

    //Widths by the titles and the first rows
    MaxW:=DMMain.ScaleForFont(260);
    DataGrid.Canvas.Font:=DataGrid.Font;
    for c:=0 to FieldNames.Count-1 do
    begin
      w:=DataGrid.Canvas.TextWidth(DataGrid.Columns[c].Title.Caption);
      for r:=1 to DataGrid.RowCount-1 do
      begin
        if(r>60)then
          break;
        if(DataGrid.Canvas.TextWidth(DataGrid.Cells[c+1, r])>w)then
          w:=DataGrid.Canvas.TextWidth(DataGrid.Cells[c+1, r]);
      end;
      w:=w+DMMain.ScaleForFont(14);
      if(w>MaxW)then
        w:=MaxW;
      DataGrid.Columns[c].Width:=w;
    end;

    r:=DataGrid.RowCount-1;
    if(More)then
      s:=Format(Tr('%s: the first %d rows (there are more)', '%s: die ersten %d Zeilen (es gibt weitere)'),
        [CurTableName, r])
    else
      s:=Format(Tr('%s: %d rows', '%s: %d Zeilen'), [CurTableName, r]);
    s:=s+Format('   -   %d ms', [GetTickCount64-t0]);
    if(CurTable<>nil)and(CurTable.RelEnd.Count>0)then
      s:=s+'   -   '+Tr('double click on a column marked with > shows the referenced row',
        'Doppelklick auf eine mit > markierte Spalte zeigt die referenzierte Zeile');
    StatusPnl.Caption:=' '+s;

    if(DataGrid.RowCount>1)and(DataGrid.ColCount>1)then
    begin
      DataGrid.Row:=1;
      DataGrid.Col:=1;
      DataGridSelection(DataGrid, 1, 1);
    end;
  finally
    Q.Free;
    DataGrid.EndUpdate;
    Screen.Cursor:=crDefault;
  end;
end;

procedure TMainForm.RefreshBtnClick(Sender: TObject);
begin
  LoadData;
end;

procedure TMainForm.ClearBtnClick(Sender: TObject);
begin
  FilterEd.Text:='';
  LoadData;
end;

procedure TMainForm.FilterEdKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if(Key=VK_RETURN)then
  begin
    Key:=0;
    LoadData;
  end;
end;

procedure TMainForm.DataGridHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
var c: integer;
begin
  //A click on a title sorts by the column, another one turns the order
  c:=Index-DataGrid.FixedCols;
  if(Not(IsColumn))or(c<0)or(c>=FieldNames.Count)then
    Exit;

  if(CompareText(SortField, FieldNames[c])=0)then
    SortDesc:=Not(SortDesc)
  else
  begin
    SortField:=FieldNames[c];
    SortDesc:=False;
  end;

  LoadData;
end;

procedure TMainForm.DataGridSelection(Sender: TObject; aCol, aRow: Integer);
begin
  //The whole value of the cell
  if(aRow>=1)and(aCol>=1)and(aRow<DataGrid.RowCount)and(aCol<DataGrid.ColCount)then
    CellMemo.Lines.Text:=DataGrid.Cells[aCol, aRow]
  else
    CellMemo.Lines.Clear;
end;

procedure TMainForm.DataGridDblClick(Sender: TObject);
var c, r: integer;
  RefT: TEERTable;
  RefC, Filter: string;
begin
  //Follow a foreign key: the row of the referenced table
  c:=DataGrid.Col-DataGrid.FixedCols;
  r:=DataGrid.Row;
  if(r<1)or(c<0)or(c>=FieldNames.Count)then
    Exit;
  if(Not(ReferencedColumn(FieldNames[c], RefT, RefC)))then
    Exit;
  if(PtrInt(DataGrid.Objects[c+1, r])=NullMark)then
  begin
    StatusPnl.Caption:=' '+Tr('This foreign key is NULL.', 'Dieser Fremdschlüssel ist NULL.');
    Exit;
  end;

  Filter:=BrowserName(RefC, DBType, DMEER.EncloseNames)+' = '+
    BrowserLiteral(DataGrid.Cells[c+1, r], FieldIsNumber[c]);

  //the list may show the tables of the database
  ShowTable(RefT.ObjName, RefT, Filter);
end;

procedure TMainForm.DataGridPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
begin
  if(aRow>=1)and(aCol>=1)then
    if(PtrInt(DataGrid.Objects[aCol, aRow])=NullMark)and(Not(gdSelected in aState))then
      DataGrid.Canvas.Font.Color:=clGrayText;
end;

end.
