program TestFirebirdSync;

// Firebird support (src/DBEERFirebird.pas), run on bin/Examples/order.xml and
// a fresh database file in the temp directory, opened with the embedded
// engine: create all tables, sync again without changes, column changes,
// a changed primary key and foreign key, a renamed table, and the reverse
// engineering of the result into a new model, which has to sync without
// changes again, also with a foreign key from a table to itself.
// At the end the SQL create script for the FireBird target
// (identity columns, then generator and triggers) is loaded into a fresh
// database with isql, if isql lies next to the client library.
//
// Needs the application infrastructure (data modules, LCL) and the Firebird
// client library with the embedded engine (the zip kit of Firebird 3 or
// newer). Its fbclient library is taken from the environment variable
// DBD_FBCLIENT or from ../Firebird-5.0.4-x64 next to the project directory:
//   lazbuild tests/TestFirebirdSync.lpi && bin/TestFirebirdSync
// Run it from the project directory. Exit code = number of failed checks.
//
// With the environment variable DBD_FB_HOST the test connects to a server
// instead (DBD_FB_PORT, DBD_FB_USER, DBD_FB_PASSWORD; DBD_FB_DATABASE names
// an existing empty database on the server).

{$I DBDesigner4.inc}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, Forms, Controls, DB, SQLDB, Process,
  MainDM, DBDM, EERDM, DBEERDM, DBEERFirebird, EERModel;

var
  ParentForm: TForm;
  Model, Model2, Model3, Model4: TEERModel;
  Conn: TDBConn;
  Log, theTables: TStringList;
  DBPath, FBClient, FBHost, RowCount, Isql, IsqlOut: string;
  Failures: integer = 0;
  Product, Cart, Kunde: TEERTable;
  SelfRel: TEERRel;
  theList: TList;
  theColumn: TEERColumn;
  i, j: integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if(Cond)then
    WriteLn('  ok    ', What)
  else
  begin
    WriteLn('  FAIL  ', What);
    inc(Failures);
  end;
end;

//All values of the first column, comma separated
function SQLVal(const stmt: string): string;
var Q: SQLDB.TSQLQuery;
begin
  Result:='';
  Q:=SQLDB.TSQLQuery.Create(nil);
  try
    Q.DataBase:=DMDB.SQLConn;
    Q.Transaction:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
    Q.ParamCheck:=False;
    Q.SQL.Text:=stmt;
    Q.Open;
    while(Not(Q.EOF))do
    begin
      if(Result<>'')then
        Result:=Result+',';
      Result:=Result+Trim(Q.Fields[0].AsString);
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
  end;
  SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction).CommitRetaining;
end;

//The columns of a table in their order
function ColumnsOf(const tbl: string): string;
begin
  ColumnsOf:=SQLVal('SELECT TRIM(RDB$FIELD_NAME) FROM RDB$RELATION_FIELDS '+
    'WHERE RDB$RELATION_NAME='''+tbl+''' ORDER BY RDB$FIELD_POSITION');
end;

//The tables the foreign keys of a table reference
function RefTablesOf(const tbl: string): string;
begin
  RefTablesOf:=SQLVal('SELECT TRIM(pk.RDB$RELATION_NAME) '+
    'FROM RDB$RELATION_CONSTRAINTS rc '+
    'JOIN RDB$REF_CONSTRAINTS ref ON ref.RDB$CONSTRAINT_NAME=rc.RDB$CONSTRAINT_NAME '+
    'JOIN RDB$RELATION_CONSTRAINTS pk ON pk.RDB$CONSTRAINT_NAME=ref.RDB$CONST_NAME_UQ '+
    'WHERE rc.RDB$CONSTRAINT_TYPE=''FOREIGN KEY'' AND rc.RDB$RELATION_NAME='''+tbl+''' '+
    'ORDER BY 1');
end;

//The columns of the primary key of a table
function PrimaryKeyOf(const tbl: string): string;
begin
  PrimaryKeyOf:=SQLVal('SELECT TRIM(s.RDB$FIELD_NAME) '+
    'FROM RDB$RELATION_CONSTRAINTS rc '+
    'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME=rc.RDB$INDEX_NAME '+
    'WHERE rc.RDB$CONSTRAINT_TYPE=''PRIMARY KEY'' AND rc.RDB$RELATION_NAME='''+tbl+''' '+
    'ORDER BY s.RDB$FIELD_POSITION');
end;

function GetTable(aModel: TEERModel; const tblname: string): TEERTable;
var k: integer;
begin
  Result:=nil;
  for k:=0 to aModel.ComponentCount-1 do
    if(aModel.Components[k] is TEERTable)then
      if(CompareText(TEERTable(aModel.Components[k]).ObjName, tblname)=0)then
        Result:=TEERTable(aModel.Components[k]);
end;

function LogHas(const s: string): Boolean;
begin
  LogHas:=(Pos(UpperCase(s), UpperCase(Log.Text))>0);
end;

//The index on info: Firebird has no index on a BLOB column (info is TEXT).
//The standard inserts of onlineorder: date is a reserved word in Firebird
procedure PrepareOrderModel(aModel: TEERModel);
var aTable: TEERTable;
  aColumn: TEERColumn;
  k, m: integer;
begin
  aTable:=GetTable(aModel, 'product');
  aColumn:=TEERColumn(aTable.GetColumnByName('info'));
  for k:=0 to aTable.Indices.Count-1 do
  begin
    m:=TEERIndex(aTable.Indices[k]).Columns.IndexOf(IntToStr(aColumn.Obj_id));
    if(m>=0)then
      TEERIndex(aTable.Indices[k]).Columns.Delete(m);
  end;

  aTable:=GetTable(aModel, 'onlineorder');
  aTable.StandardInserts.Text:=StringReplace(
    aTable.StandardInserts.Text, ', date,', ', "DATE",', [rfReplaceAll]);
end;

//The SQL create script as the export dialog builds it for the FireBird
//target. Triggers: auto increment by generator and trigger, last change and
//last delete triggers; otherwise identity columns
function ExportScript(aModel: TEERModel; Triggers: Boolean): string;
var Tables: TList;
  k: integer;
begin
  Result:='';
  Tables:=TList.Create;
  try
    aModel.GetEERObjectList([EERTable], Tables);
    aModel.SortEERObjectListByObjName(Tables);
    aModel.SortEERTableListByForeignKeyReferences(Tables);

    if(Triggers)then
      Result:='CREATE GENERATOR GlobalSequence;'#13#10#13#10+
        'CREATE TABLE DT_EXCLUSION (EX_DATE VARCHAR(15), TABLE_NAME VARCHAR(64) NOT NULL, '+
        'PRIMARY KEY (TABLE_NAME));'#13#10#13#10;

    for k:=0 to Tables.Count-1 do
      if(Not(TEERTable(Tables[k]).IsLinkedObject))then
        Result:=Result+TEERTable(Tables[k]).GetSQLCreateCode(
          True, //DefinePK
          True, //CreateIndices
          True, //DefineFK
          False, //TblOptions
          True, //StdInserts
          True, //OutputComments
          True, //HideNullField
          True, //PortableIndices
          False, //HideOnDeleteUpdateNoAction
          False, //GOStatement
          True, //CommitStatement
          False, //FKIndex
          True, //DefaultBeforeNotNull
          'FireBird', 'GlobalSequence', 'AINC_', Triggers,
          Triggers, 'LAST_CHANGE_DATE', 'USERID', 'UPDT_',
          Triggers, 'DT_EXCLUSION', 'EX_DATE', 'EXCDT_')+#13#10;
  finally
    Tables.Free;
  end;
end;

//Run a script on a new database with isql, the output of isql
function RunIsql(const Isql, Script, DBFile: string): string;
var theLines: TStringList;
  ScriptFile: string;
begin
  Result:='';
  if(FileExists(DBFile))then
    DeleteFile(DBFile);
  ScriptFile:=ChangeFileExt(DBFile, '.sql');

  theLines:=TStringList.Create;
  try
    theLines.Text:='CREATE DATABASE '''+DBFile+''' USER ''SYSDBA'' DEFAULT CHARACTER SET UTF8;'#13#10#13#10+
      Script;
    theLines.SaveToFile(ScriptFile);
  finally
    theLines.Free;
  end;

  //-m: errors go to the standard output as well
  if(Not(RunCommand(Isql, ['-q', '-m', '-i', ScriptFile], Result)))then
    Result:=Result+#13#10'Statement failed: isql could not be run';
end;

procedure CheckIsql(const Output, Title: string);
begin
  WriteLn(Output);
  Check((Pos('Statement failed', Output)=0)and(Pos('SQL error', Output)=0)and
    (Pos('Token unknown', Output)=0), Title+': no errors');
end;

procedure Sync(aModel: TEERModel; const Title: string);
begin
  WriteLn;
  WriteLn('--- ', Title);
  Log.Clear;
  DMDBEER.EERMySQLSyncDB(aModel, Conn, Log, True, True, False);
  WriteLn(Log.Text);
  Check(Not(LogHas('ERROR'))and(Not(LogHas('FAILED'))), 'no errors');
  Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME=''DBD4_SYNC_TMP''')='0',
    'no temporary table left');
end;

procedure CheckNoChanges;
begin
  Check(Not(LogHas('Modifying'))and
    (Not(LogHas('Add Column')))and(Not(LogHas('Dropping')))and
    (Not(LogHas('index')))and(Not(LogHas('Create non existing')))and
    (Not(LogHas('foreign key')))and(Not(LogHas('primary key'))),
    'nothing changed');
end;

begin
  Application.Initialize;

  FBClient:=GetEnvironmentVariable('DBD_FBCLIENT');
  if(FBClient='')then
    FBClient:=ExpandFileName('..'+PathDelim+'Firebird-5.0.4-x64'+PathDelim+
      {$IFDEF MSWINDOWS}'fbclient.dll'{$ELSE}'lib'+PathDelim+'libfbclient.so'{$ENDIF});

  FBHost:=GetEnvironmentVariable('DBD_FB_HOST');
  if(FBHost<>'')then
    DBPath:=GetEnvironmentVariable('DBD_FB_DATABASE')
  else
  begin
    DBPath:=GetTempDir+'dbdesigner_sync_test.fdb';
    if(FileExists(DBPath))then
      DeleteFile(DBPath);
  end;

  //The main form: TDMDB.ConnectToDB posts an event to Application.MainForm
  Application.CreateForm(TForm, ParentForm);
  Log:=TStringList.Create;
  theTables:=TStringList.Create;
  Conn:=TDBConn.Create;
  try
  try
    DMMain:=TDMMain.Create(ParentForm);
    DMDB:=TDMDB.Create(ParentForm);
    DMEER:=TDMEER.Create(ParentForm);

    Model:=TEERModel.Create(ParentForm);
    Model.Parent:=ParentForm;
    Model.LoadFromFile('bin'+PathDelim+'Examples'+PathDelim+'order.xml');

    PrepareOrderModel(Model);
    Product:=GetTable(Model, 'product');

    //No host name: the embedded engine. The database file is created
    Conn.Name:='SyncTest';
    Conn.DriverName:='Firebird';
    Conn.VendorLib:=FBClient;
    Conn.Params.Values['Database']:=DBPath;
    Conn.Params.Values['User_Name']:='SYSDBA';
    if(FBHost<>'')then
    begin
      Conn.Params.Values['HostName']:=FBHost;
      Conn.Params.Values['Port']:=GetEnvironmentVariable('DBD_FB_PORT');
      if(GetEnvironmentVariable('DBD_FB_USER')<>'')then
        Conn.Params.Values['User_Name']:=GetEnvironmentVariable('DBD_FB_USER');
      Conn.Params.Values['Password']:=GetEnvironmentVariable('DBD_FB_PASSWORD');
    end;
    DMDB.ConnectToDB(Conn);
    if(FBHost<>'')then
      WriteLn('  connected to server ', FBHost, ', protocol ',
        SQLVal('SELECT RDB$GET_CONTEXT(''SYSTEM'', ''NETWORK_PROTOCOL'') FROM RDB$DATABASE'))
    else
      Check(FileExists(DBPath), 'database file created');
    WriteLn('  Firebird ', SQLVal('SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') FROM RDB$DATABASE'));

    //------------------------------------------------------------
    Sync(Model, '1. empty database: create everything');
    Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0)=0')='12',
      '12 tables created');
    Check(SQLVal('SELECT COUNT(*) FROM product')='3', 'standard inserts of product executed');
    Check(RefTablesOf('ONLINEORDERHASPRODUCT')='ONLINEORDER',
      'foreign key of onlineorderhasproduct created');
    Check(SQLVal('SELECT COUNT(*) FROM RDB$INDICES WHERE RDB$INDEX_NAME=''PRODUCT_EAN'' AND RDB$UNIQUE_FLAG=1')='1',
      'unique index product_ean created');
    Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME=''PRODUCT'' '+
      'AND RDB$FIELD_NAME=''IDPRODUCT'' AND RDB$IDENTITY_TYPE IS NOT NULL')='1',
      'idproduct is an identity column');

    DMDB.ExecSQL('CREATE VIEW product_v AS SELECT idproduct, name FROM product', True);

    //------------------------------------------------------------
    Sync(Model, '2. no changes');
    CheckNoChanges;

    //------------------------------------------------------------
    //rename price, drop pic, add stock
    theColumn:=TEERColumn(Product.GetColumnByName('price'));
    theColumn.PrevColName:='price';
    theColumn.ColName:='netprice';

    Product.Columns.Delete(Product.Columns.IndexOf(Product.GetColumnByName('pic')));

    theColumn:=TEERColumn.Create(Product);
    theColumn.ColName:='stock';
    theColumn.Obj_id:=DMMain.GetNextGlobalID;
    theColumn.idDatatype:=TEERDatatype(Model.GetDataTypeByName('DECIMAL')).id;
    theColumn.DatatypeParams:='(8,0)';
    theColumn.PrimaryKey:=False;
    theColumn.NotNull:=False;
    theColumn.AutoInc:=False;
    theColumn.IsForeignKey:=False;
    theColumn.DefaultValue:='0';
    Product.Columns.Add(theColumn);

    Sync(Model, '3. rename / drop / add column');
    Check(ColumnsOf('PRODUCT')='IDPRODUCT,IDPRODUCTGROUP,NAME,EAN,NETPRICE,INFO,STOCK',
      'columns of product');
    Check(SQLVal('SELECT ean FROM product ORDER BY idproduct')=
      '154365423,437634323,34631764345', 'data kept');
    Check(SQLVal('SELECT COUNT(*) FROM product WHERE netprice>14')='3', 'data of the renamed column kept');
    Check(SQLVal('SELECT RDB$DEFAULT_SOURCE FROM RDB$RELATION_FIELDS '+
      'WHERE RDB$RELATION_NAME=''PRODUCT'' AND RDB$FIELD_NAME=''STOCK''')='DEFAULT 0',
      'default of the new column');

    //------------------------------------------------------------
    //NOT NULL, datatype parameters, a changed default, a dropped indexed
    //column and a changed index
    Product.Columns.Delete(Product.Columns.IndexOf(Product.GetColumnByName('info')));

    TEERColumn(Product.GetColumnByName('name')).NotNull:=True;
    TEERColumn(Product.GetColumnByName('stock')).DatatypeParams:='(12,4)';
    TEERColumn(Product.GetColumnByName('stock')).DefaultValue:='1';

    theColumn:=TEERColumn(Product.GetColumnByName('ean'));
    for i:=0 to Product.Indices.Count-1 do
      if(CompareText(TEERIndex(Product.Indices[i]).IndexName, 'product_name')=0)then
        TEERIndex(Product.Indices[i]).Columns.Add(IntToStr(theColumn.Obj_id));

    Sync(Model, '4. NOT NULL / datatype / default / index change');
    Check(SQLVal('SELECT COUNT(*) FROM product')='3', 'rows kept');
    Check(ColumnsOf('PRODUCT')='IDPRODUCT,IDPRODUCTGROUP,NAME,EAN,NETPRICE,STOCK',
      'columns of product');
    Check(SQLVal('SELECT TRIM(RDB$FIELD_NAME) FROM RDB$INDEX_SEGMENTS '+
      'WHERE RDB$INDEX_NAME=''PRODUCT_NAME'' ORDER BY RDB$FIELD_POSITION')='NAME,EAN',
      'index product_name with its new columns');
    Check(SQLVal('SELECT name FROM product WHERE idproduct=3')='Alice in Wonderland', 'data kept');
    Check(SQLVal('SELECT RDB$NULL_FLAG FROM RDB$RELATION_FIELDS '+
      'WHERE RDB$RELATION_NAME=''PRODUCT'' AND RDB$FIELD_NAME=''NAME''')='1', 'name is NOT NULL');
    Check(SQLVal('SELECT f.RDB$FIELD_PRECISION FROM RDB$RELATION_FIELDS rf '+
      'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME=rf.RDB$FIELD_SOURCE '+
      'WHERE rf.RDB$RELATION_NAME=''PRODUCT'' AND rf.RDB$FIELD_NAME=''STOCK''')='12',
      'stock has the new parameters');
    Check(SQLVal('SELECT RDB$DEFAULT_SOURCE FROM RDB$RELATION_FIELDS '+
      'WHERE RDB$RELATION_NAME=''PRODUCT'' AND RDB$FIELD_NAME=''STOCK''')='DEFAULT 1',
      'stock has the new default');
    Check(SQLVal('SELECT COUNT(*) FROM product_v')='3', 'view still works');

    //------------------------------------------------------------
    Sync(Model, '5. no changes');
    CheckNoChanges;

    //------------------------------------------------------------
    //Primary key of a referenced table, a new and a dropped foreign key
    for i:=0 to Model.ComponentCount-1 do
      if(Model.Components[i] is TEERRel)then
      begin
        if(TEERRel(Model.Components[i]).ObjName='ProductInCartRel')then
        begin
          TEERRel(Model.Components[i]).CreateRefDef:=True;
          TEERRel(Model.Components[i]).RefDef.Values['OnDelete']:='1';
        end;
        if(TEERRel(Model.Components[i]).ObjName='OnlineorderRel')then
          TEERRel(Model.Components[i]).CreateRefDef:=False;
      end;

    Sync(Model, '6. foreign keys added and dropped');
    Check(RefTablesOf('CARTHASPRODUCT')='ONLINECUSTOMER,PRODUCT', 'foreign key to product added');
    Check(RefTablesOf('ONLINEORDERHASPRODUCT')='', 'foreign key of onlineorderhasproduct dropped');
    Check(SQLVal('SELECT TRIM(ref.RDB$DELETE_RULE) FROM RDB$REF_CONSTRAINTS ref '+
      'JOIN RDB$RELATION_CONSTRAINTS pk ON pk.RDB$CONSTRAINT_NAME=ref.RDB$CONST_NAME_UQ '+
      'WHERE pk.RDB$RELATION_NAME=''PRODUCT''')='CASCADE', 'ON DELETE CASCADE');

    //idonlineorder leaves the primary key of onlineorderhasproduct
    Cart:=GetTable(Model, 'onlineorderhasproduct');
    Check(PrimaryKeyOf('ONLINEORDERHASPRODUCT')='IDONLINEORDER,IDPRODUCT',
      'primary key of onlineorderhasproduct');
    theColumn:=TEERColumn(Cart.GetColumnByName('idonlineorder'));
    theColumn.PrimaryKey:=False;
    Cart.CheckPrimaryIndex;

    Sync(Model, '7. changed primary key');
    Check(LogHas('primary key'), 'primary key change logged');
    Check(PrimaryKeyOf('ONLINEORDERHASPRODUCT')='IDPRODUCT', 'new primary key of onlineorderhasproduct');
    Check(SQLVal('SELECT COUNT(*) FROM onlineorderhasproduct')='2', 'rows kept');

    //------------------------------------------------------------
    //onlinecustomer is referenced by a foreign key of carthasproduct
    RowCount:=SQLVal('SELECT COUNT(*) FROM onlinecustomer');
    GetTable(Model, 'onlinecustomer').PrevTableName:='onlinecustomer';
    GetTable(Model, 'onlinecustomer').ObjName:='shopcustomer';

    Sync(Model, '8. renamed table');
    Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME=''SHOPCUSTOMER''')='1',
      'new table exists');
    Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME=''ONLINECUSTOMER''')='0',
      'old table dropped');
    Check((RowCount<>'0')and(SQLVal('SELECT COUNT(*) FROM shopcustomer')=RowCount),
      RowCount+' rows copied');
    Check(RefTablesOf('CARTHASPRODUCT')='PRODUCT,SHOPCUSTOMER', 'carthasproduct references shopcustomer');

    //------------------------------------------------------------
    Sync(Model, '9. no changes after the rename');
    CheckNoChanges;

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 10. reverse engineering');
    Model2:=TEERModel.Create(ParentForm);
    Model2.Parent:=ParentForm;
    FirebirdGetTables(theTables);
    Check(theTables.Count=12, '12 tables listed');
    FirebirdReverseEngineer(Model2, theTables, 5, True, True, nil, nil, False, 0);

    Product:=GetTable(Model2, 'PRODUCT');
    Check(Product<>nil, 'table PRODUCT in the model');
    if(Product<>nil)then
    begin
      Check(Product.Columns.Count=6, '6 columns');
      theColumn:=TEERColumn(Product.GetColumnByName('STOCK'));
      Check((theColumn<>nil)and(theColumn.DatatypeParams='(12,4)')and
        (CompareText(TEERDatatype(Model2.GetDataType(theColumn.idDatatype)).TypeName, 'DECIMAL')=0),
        'STOCK is DECIMAL(12,4)');
      theColumn:=TEERColumn(Product.GetColumnByName('NAME'));
      Check((theColumn<>nil)and(theColumn.DatatypeParams='(45)')and(theColumn.NotNull)and
        (CompareText(TEERDatatype(Model2.GetDataType(theColumn.idDatatype)).TypeName, 'VARCHAR')=0),
        'NAME is VARCHAR(45) NOT NULL');
      theColumn:=TEERColumn(Product.GetColumnByName('IDPRODUCT'));
      Check((theColumn<>nil)and(theColumn.PrimaryKey)and(theColumn.AutoInc)and(theColumn.NotNull),
        'IDPRODUCT is the auto increment primary key');
      theColumn:=TEERColumn(Product.GetColumnByName('STOCK'));
      Check((theColumn<>nil)and(theColumn.DefaultValue='1'), 'default of STOCK');
      j:=0;
      for i:=0 to Product.Indices.Count-1 do
        if(TEERIndex(Product.Indices[i]).IndexKind=ik_UNIQUE_INDEX)and
          (TEERIndex(Product.Indices[i]).IndexName='PRODUCT_EAN')then
          inc(j);
      Check((Product.Indices.Count=3)and(j=1), 'indices PRIMARY, PRODUCT_NAME, unique PRODUCT_EAN');
    end;

    j:=0;
    for i:=0 to Model2.ComponentCount-1 do
      if(Model2.Components[i] is TEERRel)then
        if(TEERRel(Model2.Components[i]).CreateRefDef)then
          inc(j);
    Check(j=2, '2 relations from the foreign keys');

    Sync(Model2, '11. the reverse engineered model has no changes');
    CheckNoChanges;

    //------------------------------------------------------------
    //A foreign key that references its own table
    WriteLn;
    WriteLn('--- 12. reverse engineering of a self-referencing foreign key');
    DMDB.ExecSQL('CREATE TABLE KUNDE (ID INTEGER NOT NULL PRIMARY KEY, NAME VARCHAR(40), '+
      'WERBER_ID INTEGER, CONSTRAINT KUNDE_WERBER FOREIGN KEY (WERBER_ID) REFERENCES KUNDE (ID) '+
      'ON DELETE SET NULL)', True);
    DMDB.ExecSQL('INSERT INTO KUNDE (ID, NAME, WERBER_ID) VALUES (1, ''first'', NULL)', True);
    DMDB.ExecSQL('INSERT INTO KUNDE (ID, NAME, WERBER_ID) VALUES (2, ''second'', 1)', True);

    Model4:=TEERModel.Create(ParentForm);
    Model4.Parent:=ParentForm;
    FirebirdGetTables(theTables);
    Check(theTables.Count=13, '13 tables listed');
    FirebirdReverseEngineer(Model4, theTables, 5, True, True, nil, nil, False, 0);

    Kunde:=GetTable(Model4, 'KUNDE');
    Check(Kunde<>nil, 'table KUNDE in the model');
    if(Kunde<>nil)then
    begin
      Check(Kunde.Columns.Count=3, '3 columns');
      SelfRel:=nil;
      j:=0;
      for i:=0 to Kunde.RelEnd.Count-1 do
        if(TEERRel(Kunde.RelEnd[i]).SrcTbl=Kunde)then
        begin
          SelfRel:=TEERRel(Kunde.RelEnd[i]);
          inc(j);
        end;
      Check(j=1, 'one relation from KUNDE to itself');
      if(SelfRel<>nil)then
      begin
        Check(SelfRel.RelKind=rk_1nNonId, 'the relation is non-identifying');
        Check(SelfRel.ObjName='KUNDE_WERBER', 'the relation has the name of the constraint');
        Check(Trim(SelfRel.FKFields.Text)='ID=WERBER_ID', 'mapping ID=WERBER_ID');
        //The codes of TEERRel.RefDef: 0 = RESTRICT, 2 = SET NULL
        Check((SelfRel.CreateRefDef)and
          (SelfRel.RefDef.Values['OnDelete']='2')and
          (SelfRel.RefDef.Values['OnUpdate']='0'),
          'ON DELETE SET NULL, ON UPDATE RESTRICT');
      end;
      theColumn:=TEERColumn(Kunde.GetColumnByName('WERBER_ID'));
      Check((theColumn<>nil)and(theColumn.IsForeignKey)and(Not(theColumn.PrimaryKey)),
        'WERBER_ID is a foreign key column');
    end;

    //The table order of the sync and of the SQL export
    theList:=TList.Create;
    try
      Model4.GetEERObjectList([EERTable], theList);
      Model4.SortEERTableListByForeignKeyReferences(theList);
      Check(theList.Count=13, 'tables sorted by their foreign key references');
    finally
      theList.Free;
    end;

    Sync(Model4, '13. the model with the self reference has no changes');
    CheckNoChanges;
    Check(RefTablesOf('KUNDE')='KUNDE', 'foreign key of KUNDE still there');
    Check(SQLVal('SELECT TRIM(RDB$CONSTRAINT_NAME) FROM RDB$RELATION_CONSTRAINTS '+
      'WHERE RDB$CONSTRAINT_TYPE=''FOREIGN KEY'' AND RDB$RELATION_NAME=''KUNDE''')='KUNDE_WERBER',
      'the constraint was not created again');

    //The renamed table gets the foreign key to itself again
    if(Kunde<>nil)then
    begin
      Kunde.PrevTableName:='KUNDE';
      Kunde.ObjName:='WERBEKUNDE';

      Sync(Model4, '14. renamed table with a self reference');
      Check(SQLVal('SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME=''KUNDE''')='0',
        'old table dropped');
      Check(RefTablesOf('WERBEKUNDE')='WERBEKUNDE', 'WERBEKUNDE references itself');
      Check(SQLVal('SELECT WERBER_ID FROM WERBEKUNDE WHERE ID=2')='1', 'rows copied');

      Sync(Model4, '15. no changes after the rename');
      CheckNoChanges;
    end;

    DMDB.SQLConn.Close;

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 16. SQL create script for the FireBird target');
    Isql:=ExtractFilePath(FBClient)+{$IFDEF MSWINDOWS}'isql.exe'{$ELSE}'..'+PathDelim+'bin'+PathDelim+'isql'{$ENDIF};
    if(Not(FileExists(Isql)))then
      WriteLn('  skipped, no isql at ', Isql)
    else
    begin
      Model3:=TEERModel.Create(ParentForm);
      Model3.Parent:=ParentForm;
      Model3.LoadFromFile('bin'+PathDelim+'Examples'+PathDelim+'order.xml');
      PrepareOrderModel(Model3);

      //COMMIT: the queries have to see the last table isql created
      IsqlOut:=RunIsql(Isql, ExportScript(Model3, False)+'COMMIT;'#13#10+
        'SELECT ''TABLES='' || COUNT(*) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0)=0;'#13#10+
        'SELECT ''PRODUCTS='' || COUNT(*) FROM product;'#13#10+
        'SELECT ''FKS='' || COUNT(*) FROM RDB$REF_CONSTRAINTS;'#13#10+
        'SELECT ''IDENTITIES='' || COUNT(*) FROM RDB$RELATION_FIELDS WHERE RDB$IDENTITY_TYPE IS NOT NULL;'#13#10+
        'SELECT ''INDEX='' || COUNT(*) FROM RDB$INDICES WHERE RDB$INDEX_NAME=''PRODUCT_EAN'' AND RDB$UNIQUE_FLAG=1;'#13#10+
        'SELECT ''DATECOL='' || f.RDB$FIELD_TYPE FROM RDB$RELATION_FIELDS rf '+
        'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME=rf.RDB$FIELD_SOURCE '+
        'WHERE rf.RDB$RELATION_NAME=''ONLINEORDER'' AND rf.RDB$FIELD_NAME=''DATE'';'#13#10,
        GetTempDir+'dbdesigner_export_test.fdb');
      CheckIsql(IsqlOut, 'identity columns');
      Check(Pos('TABLES=12', IsqlOut)>0, '12 tables');
      Check(Pos('PRODUCTS=3', IsqlOut)>0, 'standard inserts executed');
      Check(Pos('FKS=2', IsqlOut)>0, '2 foreign keys');
      Check(Pos('IDENTITIES=', IsqlOut)>0, 'identity columns');
      Check(Pos('INDEX=1', IsqlOut)>0, 'unique index product_ean');
      Check(Pos('DATECOL=35', IsqlOut)>0, 'DATETIME column "DATE" is a TIMESTAMP');

      IsqlOut:=RunIsql(Isql, ExportScript(Model3, True)+'COMMIT;'#13#10+
        'SELECT ''TABLES='' || COUNT(*) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0)=0;'#13#10+
        'SELECT ''TRIGGERS='' || COUNT(*) FROM RDB$TRIGGERS WHERE COALESCE(RDB$SYSTEM_FLAG, 0)=0;'#13#10+
        'UPDATE product SET name=name WHERE idproduct=1;'#13#10+
        'SELECT ''STAMP='' || CHAR_LENGTH(LAST_CHANGE_DATE) FROM product WHERE idproduct=1;'#13#10+
        //The standard inserts used the first numbers already
        'SET GENERATOR GlobalSequence TO 1000;'#13#10+
        'INSERT INTO productgroup (groupname) VALUES (''generated'');'#13#10+
        'SELECT ''GENERATED='' || COUNT(*) FROM productgroup WHERE groupname=''generated'' AND idproductgroup IS NOT NULL;'#13#10+
        'DELETE FROM product WHERE idproduct=3;'#13#10+
        'SELECT ''EXCLUSION='' || TRIM(TABLE_NAME) || ''/'' || CHAR_LENGTH(EX_DATE) FROM DT_EXCLUSION;'#13#10,
        GetTempDir+'dbdesigner_export_test2.fdb');
      CheckIsql(IsqlOut, 'generator and triggers');
      Check(Pos('TABLES=13', IsqlOut)>0, '13 tables');
      Check(Pos('TRIGGERS=', IsqlOut)>0, 'triggers created');
      Check(Pos('STAMP=15', IsqlOut)>0, 'last change trigger writes the time stamp');
      Check(Pos('GENERATED=1', IsqlOut)>0, 'auto increment trigger');
      Check(Pos('EXCLUSION=product/15', IsqlOut)>0, 'last delete trigger');
    end;
  except
    on E: Exception do
    begin
      WriteLn('EXCEPTION ', E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(Output);
      inc(Failures);
    end;
  end;
  finally
    Conn.Free;
    theTables.Free;
    Log.Free;
  end;

  WriteLn;
  if(Failures=0)then
    WriteLn('SUCCESS: Firebird reverse engineering and synchronisation work')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
