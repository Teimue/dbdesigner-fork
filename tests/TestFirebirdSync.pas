program TestFirebirdSync;

// Firebird support (src/DBEERFirebird.pas), run on bin/Examples/order.xml and
// a fresh database file in the temp directory, opened with the embedded
// engine: create all tables, sync again without changes, column changes,
// a changed primary key and foreign key, a renamed table, and the reverse
// engineering of the result into a new model, which has to sync without
// changes again.
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
  Classes, SysUtils, Forms, Controls, DB, SQLDB,
  MainDM, DBDM, EERDM, DBEERDM, DBEERFirebird, EERModel;

var
  ParentForm: TForm;
  Model, Model2: TEERModel;
  Conn: TDBConn;
  Log, theTables: TStringList;
  DBPath, FBClient, FBHost, RowCount: string;
  Failures: integer = 0;
  Product, Cart: TEERTable;
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

    //Firebird has no index on a BLOB column (info is a TEXT column)
    Product:=GetTable(Model, 'product');
    theColumn:=TEERColumn(Product.GetColumnByName('info'));
    for i:=0 to Product.Indices.Count-1 do
    begin
      j:=TEERIndex(Product.Indices[i]).Columns.IndexOf(IntToStr(theColumn.Obj_id));
      if(j>=0)then
        TEERIndex(Product.Indices[i]).Columns.Delete(j);
    end;

    //date is a reserved word in Firebird
    GetTable(Model, 'onlineorder').StandardInserts.Text:=StringReplace(
      GetTable(Model, 'onlineorder').StandardInserts.Text, ', date,', ', "DATE",', [rfReplaceAll]);

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

    DMDB.SQLConn.Close;
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
