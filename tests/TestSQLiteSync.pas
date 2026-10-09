program TestSQLiteSync;

// Database synchronisation against SQLite (src/DBEERSQLiteSync.pas), run on
// bin/Examples/order.xml and a fresh database file in the temp directory:
// create all tables, sync again without changes, column changes that ALTER
// TABLE can do, changes that rebuild the table, a renamed table, and the
// reverse engineering of the result with a foreign key from a table to
// itself into a new model, which has to sync without changes again.
//
// Needs the application infrastructure (data modules, LCL):
//   lazbuild tests/TestSQLiteSync.lpi && bin/TestSQLiteSync
// Run it from the project directory. Exit code = number of failed checks.

{$I DBDesigner4.inc}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, Forms, Controls, DB, SQLDB,
  MainDM, DBDM, EERDM, DBEERDM, EERModel;

var
  ParentForm: TForm;
  Model, Model2, SyncModel: TEERModel;
  Conn: TDBConn;
  Log, theTables: TStringList;
  DBPath: string;
  Failures: integer = 0;
  Product, Kunde: TEERTable;
  SelfRel: TEERRel;
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
      Result:=Result+Q.Fields[0].AsString;
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
  end;
  SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction).CommitRetaining;
end;

function GetTable(const tblname: string): TEERTable;
var k: integer;
begin
  Result:=nil;
  for k:=0 to Model.ComponentCount-1 do
    if(Model.Components[k] is TEERTable)then
      if(CompareText(TEERTable(Model.Components[k]).ObjName, tblname)=0)then
        Result:=TEERTable(Model.Components[k]);
end;

function LogHas(const s: string): Boolean;
begin
  LogHas:=(Pos(UpperCase(s), UpperCase(Log.Text))>0);
end;

procedure Sync(const Title: string);
begin
  WriteLn;
  WriteLn('--- ', Title);
  Log.Clear;
  DMDBEER.EERMySQLSyncDB(SyncModel, Conn, Log, True, True, False);
  WriteLn(Log.Text);
  Check(Not(LogHas('ERROR'))and(Not(LogHas('FAILED'))), 'no errors');
  Check(SQLVal('SELECT integrity_check FROM pragma_integrity_check')='ok', 'integrity_check');
  Check(SQLVal('SELECT count(*) FROM pragma_foreign_key_check')='0', 'foreign_key_check');
  Check(SQLVal('SELECT count(*) FROM sqlite_master WHERE name=''dbd4_sync_tmp''')='0',
    'no temporary table left');
end;

procedure CheckNoChanges;
begin
  Check(Not(LogHas('Rebuild'))and(Not(LogHas('Modifying')))and
    (Not(LogHas('Add Column')))and(Not(LogHas('Dropping')))and
    (Not(LogHas('index')))and(Not(LogHas('Create non existing')))and
    (Not(LogHas('foreign keys')))and(Not(LogHas('primary key'))),
    'nothing changed');
end;

begin
  Application.Initialize;

  DBPath:=GetTempDir+'dbdesigner_sync_test.db';
  if(FileExists(DBPath))then
    DeleteFile(DBPath);

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
    SyncModel:=Model;

    Conn.Name:='SyncTest';
    Conn.DriverName:='SQLite';
    Conn.Params.Values['Database']:=DBPath;
    DMDB.ConnectToDB(Conn);

    //------------------------------------------------------------
    Sync('1. empty database: create everything');
    Check(SQLVal('SELECT count(*) FROM product')='3', 'standard inserts of product executed');
    Check(SQLVal('SELECT "table" FROM pragma_foreign_key_list(''onlineorderhasproduct'')')='onlineorder',
      'foreign key of onlineorderhasproduct created');

    DMDB.ExecSQL('CREATE TRIGGER product_trg AFTER UPDATE ON product BEGIN '+
      'UPDATE product SET ean=ean WHERE 1=0; END', True);
    DMDB.ExecSQL('CREATE VIEW product_v AS SELECT idproduct, name FROM product', True);

    //------------------------------------------------------------
    Sync('2. no changes');
    CheckNoChanges;

    //------------------------------------------------------------
    //rename price, drop pic (not indexed), add stock
    Product:=GetTable('product');
    theColumn:=TEERColumn(Product.GetColumnByName('price'));
    theColumn.PrevColName:='price';
    theColumn.ColName:='netprice';

    Product.Columns.Delete(Product.Columns.IndexOf(Product.GetColumnByName('pic')));

    theColumn:=TEERColumn.Create(Product);
    theColumn.ColName:='stock';
    theColumn.Obj_id:=DMMain.GetNextGlobalID;
    theColumn.idDatatype:=TEERColumn(Product.GetColumnByName('netprice')).idDatatype;
    theColumn.DatatypeParams:='(8,0)';
    theColumn.PrimaryKey:=False;
    theColumn.NotNull:=False;
    theColumn.AutoInc:=False;
    theColumn.IsForeignKey:=False;
    theColumn.DefaultValue:='0';
    Product.Columns.Add(theColumn);

    Sync('3. rename / drop / add column (ALTER TABLE)');
    Check(Not(LogHas('Rebuild')), 'table not rebuilt');
    Check(SQLVal('SELECT name FROM pragma_table_info(''product'') ORDER BY cid')=
      'idproduct,idproductgroup,name,ean,netprice,info,stock', 'columns of product');
    Check(SQLVal('SELECT ean FROM product ORDER BY idproduct')=
      '154365423,437634323,34631764345', 'data kept');
    Check(SQLVal('SELECT count(*) FROM product WHERE netprice>14')='3', 'data of the renamed column kept');
    Check(SQLVal('SELECT stock FROM product WHERE idproduct=1')='0', 'default of the new column');

    //------------------------------------------------------------
    //NOT NULL, datatype parameters and an indexed column dropped: needs a rebuild
    theColumn:=TEERColumn(Product.GetColumnByName('info'));
    for i:=0 to Product.Indices.Count-1 do
      if(TEERIndex(Product.Indices[i]).Columns.IndexOf(IntToStr(theColumn.Obj_id))>=0)then
        TEERIndex(Product.Indices[i]).Columns.Delete(
          TEERIndex(Product.Indices[i]).Columns.IndexOf(IntToStr(theColumn.Obj_id)));
    Product.Columns.Delete(Product.Columns.IndexOf(theColumn));

    TEERColumn(Product.GetColumnByName('name')).NotNull:=True;
    TEERColumn(Product.GetColumnByName('netprice')).DatatypeParams:='(12,4)';

    //onlineorder is referenced by a foreign key of onlineorderhasproduct
    TEERColumn(GetTable('onlineorder').GetColumnByName('shippingaddress')).NotNull:=True;

    Sync('4. NOT NULL / datatype change (rebuild)');
    Check(LogHas('Rebuild table product'), 'table rebuilt');
    Check(SQLVal('SELECT count(*) FROM product')='3', 'rows kept');
    Check(SQLVal('SELECT name FROM pragma_table_info(''product'') ORDER BY cid')=
      'idproduct,idproductgroup,name,ean,netprice,stock', 'columns of product');
    Check(SQLVal('SELECT name FROM pragma_index_info(''product_name'')')='name',
      'index product_name without the dropped column');
    Check(SQLVal('SELECT count(*) FROM pragma_index_list(''product'') WHERE name=''product_ean'' AND "unique"=1')='1',
      'unique index product_ean recreated');
    Check(SQLVal('SELECT name FROM product WHERE idproduct=3')='Alice in Wonderland', 'data kept');
    Check(SQLVal('SELECT "notnull" FROM pragma_table_info(''product'') WHERE name=''name''')='1',
      'name is NOT NULL');
    Check(Pos('12,4', SQLVal('SELECT type FROM pragma_table_info(''product'') WHERE name=''netprice'''))>0,
      'netprice has the new parameters');
    Check(SQLVal('SELECT count(*) FROM sqlite_master WHERE type=''trigger'' AND name=''product_trg''')='1',
      'trigger kept');
    Check(SQLVal('SELECT count(*) FROM product_v')='3', 'view still works');
    Check(Pos('AUTOINCREMENT', UpperCase(SQLVal('SELECT sql FROM sqlite_master WHERE name=''product''')))>0,
      'AUTOINCREMENT kept');
    Check(LogHas('Rebuild table onlineorder'), 'referenced table onlineorder rebuilt');
    Check(Not(LogHas('Rebuild table onlineorderhasproduct')), 'referencing table not rebuilt');
    Check(SQLVal('SELECT "table" FROM pragma_foreign_key_list(''onlineorderhasproduct'')')='onlineorder',
      'onlineorderhasproduct still references onlineorder');
    Check(SQLVal('SELECT count(*) FROM onlineorder')='1', 'rows of onlineorder kept');
    Check(SQLVal('SELECT count(*) FROM onlineorderhasproduct')='2', 'rows of onlineorderhasproduct kept');

    //------------------------------------------------------------
    Sync('5. no changes after the rebuild');
    CheckNoChanges;

    //------------------------------------------------------------
    GetTable('onlineorder').PrevTableName:='onlineorder';
    GetTable('onlineorder').ObjName:='shoporder';

    Sync('6. renamed table');
    Check(SQLVal('SELECT count(*) FROM sqlite_master WHERE type=''table'' AND name=''shoporder''')='1',
      'table renamed');
    Check(Not(LogHas('Rebuild')), 'referencing table not rebuilt');
    Check(SQLVal('SELECT "table" FROM pragma_foreign_key_list(''onlineorderhasproduct'')')='shoporder',
      'onlineorderhasproduct references shoporder');

    //------------------------------------------------------------
    Sync('7. no changes after the rename');
    CheckNoChanges;

    //------------------------------------------------------------
    //A foreign key that references its own table
    WriteLn;
    WriteLn('--- 8. reverse engineering with a self-referencing foreign key');
    DMDB.ExecSQL('CREATE TABLE kunde (id INTEGER NOT NULL PRIMARY KEY, name VARCHAR(40), '+
      'werber_id INTEGER, FOREIGN KEY (werber_id) REFERENCES kunde (id) ON DELETE SET NULL)', True);
    DMDB.ExecSQL('INSERT INTO kunde (id, name, werber_id) VALUES (1, ''first'', NULL)', True);
    DMDB.ExecSQL('INSERT INTO kunde (id, name, werber_id) VALUES (2, ''second'', 1)', True);

    Model2:=TEERModel.Create(ParentForm);
    Model2.Parent:=ParentForm;
    theTables.CommaText:=SQLVal('SELECT name FROM sqlite_master WHERE type=''table'' '+
      'AND name NOT LIKE ''sqlite_%'' ORDER BY name');
    Check(theTables.Count=13, '13 tables listed');
    DMDBEER.EERSQLiteReverseEngineer(Model2, Conn, theTables, 5, True, True, nil);

    SyncModel:=Model2;
    Kunde:=nil;
    for i:=0 to Model2.ComponentCount-1 do
      if(Model2.Components[i] is TEERTable)then
        if(CompareText(TEERTable(Model2.Components[i]).ObjName, 'kunde')=0)then
          Kunde:=TEERTable(Model2.Components[i]);
    Check(Kunde<>nil, 'table kunde in the model');
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
      Check(j=1, 'one relation from kunde to itself');
      if(SelfRel<>nil)then
      begin
        Check(SelfRel.RelKind=rk_1nNonId, 'the relation is non-identifying');
        Check(Trim(SelfRel.FKFields.Text)='id=werber_id', 'mapping id=werber_id');
        //The codes of TEERRel.RefDef: 2 = SET NULL, 3 = NO ACTION
        Check((SelfRel.CreateRefDef)and
          (SelfRel.RefDef.Values['OnDelete']='2')and
          (SelfRel.RefDef.Values['OnUpdate']='3'),
          'ON DELETE SET NULL, ON UPDATE NO ACTION');
      end;
    end;

    Sync('9. the reverse engineered model has no changes');
    CheckNoChanges;
    Check(SQLVal('SELECT "table" || ''.'' || "to" || ''/'' || on_delete '+
      'FROM pragma_foreign_key_list(''kunde'')')='kunde.id/SET NULL',
      'foreign key of kunde still there');
    Check(SQLVal('SELECT werber_id FROM kunde WHERE id=2')='1', 'rows kept');

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
    WriteLn('SUCCESS: SQLite synchronisation works')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
