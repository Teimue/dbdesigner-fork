program TestSQLiteSync;

// Database synchronisation against SQLite (src/DBEERSQLiteSync.pas), run on
// bin/Examples/order.xml and a fresh database file in the temp directory:
// create all tables, sync again without changes, column changes that ALTER
// TABLE can do, changes that rebuild the table, a renamed table, and the
// reverse engineering of the result with a foreign key from a table to
// itself into a new model, which has to sync without changes again.
// Then the example database bin/Examples/beispiel_sqlite.sql (needs SQLite
// 3.37 or newer, else the part is skipped): reverse engineering of generated
// columns, indices on an expression, descending and partial indices, CHECK
// constraints, STRICT, WITHOUT ROWID, text defaults and declared type
// names; the model saved and loaded, its SQL script run in an empty
// database, and the synchronisation, which rebuilds only the table with a
// column without type and keeps everything, then has no changes.
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
  MainDM, DBDM, EERDM, DBEERDM, EERModel, sqlite3dyn;

var
  ParentForm: TForm;
  Model, Model2, Model3, Model4, SyncModel: TEERModel;
  Conn: TDBConn;
  Log, theTables: TStringList;
  DBPath: string;
  Failures: integer = 0;
  Product, Kunde, Artikel, T: TEERTable;
  SelfRel: TEERRel;
  theColumn: TEERColumn;
  Idx: TEERIndex;
  Script: TStringList;
  s: string;
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

//Run a SQL script with sqlite3_exec in a new database file (the script has
//triggers with ; in their body); '' or the error message
function RunSQLiteScript(const DBFile, ScriptFile: string): string;
var db: psqlite3;
  err: PAnsiChar;
  Script: TStringList;
begin
  Result:='';
  if(FileExists(DBFile))then
    DeleteFile(DBFile);
  Script:=TStringList.Create;
  try
    Script.LoadFromFile(ScriptFile);
    db:=nil;
    if(sqlite3_open(PAnsiChar(UTF8String(DBFile)), @db)<>SQLITE_OK)then
    begin
      Result:='cannot open '+DBFile;
      Exit;
    end;
    try
      err:=nil;
      if(sqlite3_exec(db, PAnsiChar(UTF8String(Script.Text)), nil, nil, @err)<>SQLITE_OK)then
      begin
        Result:=StrPas(err);
        sqlite3_free(err);
      end;
    finally
      sqlite3_close(db);
    end;
  finally
    Script.Free;
  end;
end;

function FindTable(M: TEERModel; const tblname: string): TEERTable;
var k: integer;
begin
  Result:=nil;
  for k:=0 to M.ComponentCount-1 do
    if(M.Components[k] is TEERTable)then
      if(CompareText(TEERTable(M.Components[k]).ObjName, tblname)=0)then
        Result:=TEERTable(M.Components[k]);
end;

function FindIndex(T: TEERTable; const idxname: string): TEERIndex;
var k: integer;
begin
  Result:=nil;
  for k:=0 to T.Indices.Count-1 do
    if(CompareText(TEERIndex(T.Indices[k]).IndexName, idxname)=0)then
      Result:=TEERIndex(T.Indices[k]);
end;

function Col(T: TEERTable; const colname: string): TEERColumn;
begin
  Col:=TEERColumn(T.GetColumnByName(colname));
end;

//The datatype of a column as the model has it: name and parameters
function ColType(M: TEERModel; T: TEERTable; const colname: string): string;
begin
  ColType:=TEERDatatype(M.GetDataType(Col(T, colname).idDatatype)).TypeName+
    Col(T, colname).DatatypeParams;
end;

//All tables of a model saved and loaded: equal as XML (ObjIsEqualTo
//compares the lists of the relations as objects as well)
function ModelsEqual(A, B: TEERModel): Boolean;
var k: integer;
  T: TEERTable;
begin
  Result:=True;
  for k:=0 to A.ComponentCount-1 do
    if(A.Components[k] is TEERTable)then
    begin
      T:=FindTable(B, TEERTable(A.Components[k]).ObjName);
      if(T=nil)or(TEERTable(A.Components[k]).GetXML<>T.GetXML)then
      begin
        WriteLn('        differs: ', TEERTable(A.Components[k]).ObjName);
        Result:=False;
      end;
    end;
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

    //------------------------------------------------------------
    //The example database
    WriteLn;
    WriteLn('--- 10. example database beispiel_sqlite.sql: reverse engineering');
    InitializeSQLite;
    try
    if(sqlite3_libversion_number()<3037000)then
      WriteLn('  SKIPPED: SQLite ', sqlite3_libversion_number(),
        ' is older than 3.37 (STRICT)')
    else
    begin
      DBPath:=GetTempDir+'dbdesigner_beispiel_test.db';
      s:=RunSQLiteScript(DBPath, 'bin'+PathDelim+'Examples'+PathDelim+'beispiel_sqlite.sql');
      Check(s='', 'beispiel_sqlite.sql runs '+s);

      Conn.Params.Values['Database']:=DBPath;
      DMDB.ConnectToDB(Conn);

      Model3:=TEERModel.Create(ParentForm);
      Model3.Parent:=ParentForm;
      theTables.CommaText:=SQLVal('SELECT name FROM sqlite_master WHERE type=''table'' '+
        'AND name NOT LIKE ''sqlite_%'' ORDER BY name');
      Check(theTables.Count=12, '12 tables listed');
      //The relations of the foreign keys, no guesses by the primary key
      DMDBEER.EERSQLiteReverseEngineer(Model3, Conn, theTables, 5, True, False, nil);
      Check(Model3.GetEERObjectCount([EERRelation])=12, '12 relations');

      Artikel:=FindTable(Model3, 'artikel');
      Kunde:=FindTable(Model3, 'kunde');
      Check((Artikel<>nil)and(Kunde<>nil), 'tables artikel and kunde');
      if(Artikel<>nil)and(Kunde<>nil)then
      begin
        Check((Col(Artikel, 'brutto_preis')<>nil)and
          (Col(Artikel, 'brutto_preis').GeneratedExpr='round(netto_preis * (1 + mwst_satz / 100.0), 2)')and
          Not(Col(Artikel, 'brutto_preis').GeneratedStored), 'generated column, virtual');
        Check((Col(Artikel, 'versandklasse')<>nil)and
          (Pos('CASE WHEN gewicht_kg IS NULL', Col(Artikel, 'versandklasse').GeneratedExpr)=1)and
          Col(Artikel, 'versandklasse').GeneratedStored, 'generated column, stored');
        Check(Col(Artikel, 'geaendert_am').DefaultValue=
          'strftime(''%Y-%m-%d %H:%M:%f'', ''now'')', 'default with a function');
        Check(FindIndex(Artikel, 'idx_artikel_lower').Expression='lower(bezeichnung)',
          'index on an expression');
        Idx:=FindIndex(Artikel, 'idx_artikel_preis');
        Check((Idx.Columns.Count=2)and(Idx.DescColumns.Count=1)and
          (Idx.DescColumns[0]=IntToStr(Col(Artikel, 'netto_preis').Obj_id)),
          'descending column netto_preis, ascending bezeichnung');
        Check(FindIndex(Artikel, 'idx_artikel_schwer').Condition='gewicht_kg > 30',
          'partial index');
        Check((Artikel.CheckConstraints.Count=3)and(Artikel.CheckName(1)='ck_artikel_preis')and
          (Artikel.CheckExpression(1)='netto_preis >= 0'), 'CHECK constraints of artikel');

        Check(Kunde.TableOptions.Values['SQLiteStrict']='1', 'kunde is STRICT');
        Check(ColType(Model3, Kunde, 'zusatzdaten')='ANY', 'datatype ANY');
        Check(Kunde.CheckConstraints.Count=5, 'CHECK constraints of the columns of kunde');
        Check(FindTable(Model3, 'artikel_schlagwort').TableOptions.Values['SQLiteWithoutRowid']='1',
          'artikel_schlagwort is WITHOUT ROWID');
        Check(Col(FindTable(Model3, 'adresse'), 'land').DefaultValue='''DE''',
          'text default keeps its quotes');

        T:=FindTable(Model3, 'datentypen');
        Check((ColType(Model3, T, 't_clob')='CLOB')and(ColType(Model3, T, 't_boolean')='BOOLEAN')and
          (ColType(Model3, T, 't_nchar')='NCHAR(55)')and
          (ColType(Model3, T, 't_unsigned_bigint')='UNSIGNED BIG INT')and
          (ColType(Model3, T, 't_varying_char')='VARYING CHARACTER(255)')and
          (ColType(Model3, T, 't_decimal')='DECIMAL(10,5)'),
          'declared type names kept');
      end;

      //------------------------------------------------------------
      WriteLn;
      WriteLn('--- 11. the model saved and loaded');
      Model3.SaveToFile(GetTempDir+'dbdesigner_beispiel_test.xml');
      Model4:=TEERModel.Create(ParentForm);
      Model4.Parent:=ParentForm;
      Model4.LoadFromFile(GetTempDir+'dbdesigner_beispiel_test.xml');
      Check(ModelsEqual(Model3, Model4), 'all tables equal');

      //------------------------------------------------------------
      WriteLn;
      WriteLn('--- 12. the SQL script of the model in an empty database');
      Script:=TStringList.Create;
      try
        for i:=0 to Model3.ComponentCount-1 do
          if(Model3.Components[i] is TEERTable)then
            Script.Add(TEERTable(Model3.Components[i]).GetSQLCreateCode(True, True, True,
              False, False, False, True, True, False, False, False, False, False, 'SQLite'));
        Script.SaveToFile(GetTempDir+'dbdesigner_beispiel_script.sql');
      finally
        Script.Free;
      end;
      s:=RunSQLiteScript(GetTempDir+'dbdesigner_beispiel_script.db',
        GetTempDir+'dbdesigner_beispiel_script.sql');
      Check(s='', 'the script runs '+s);

      //------------------------------------------------------------
      SyncModel:=Model3;
      Sync('13. synchronisation of the reverse engineered model');
      Check(LogHas('Rebuild table datentypen'), 'datentypen rebuilt (column without type)');
      Check(Pos('Rebuild', StringReplace(Log.Text, 'Rebuild table datentypen', '', []))=0,
        'no other table rebuilt');
      Check(Not(LogHas('Create index')), 'no index created (UNIQUE constraints kept)');
      Check(SQLVal('SELECT count(*) FROM pragma_index_list(''kunde'')')='2',
        'kunde has its two UNIQUE constraints only');
      Check(SQLVal('SELECT count(*) FROM pragma_table_list WHERE name=''kunde'' AND strict=1')='1',
        'kunde still STRICT');
      Check(SQLVal('SELECT count(*) FROM pragma_table_xinfo(''artikel'') WHERE hidden IN (2, 3)')='2',
        'generated columns kept');
      Check(SQLVal('SELECT CAST(brutto_preis AS TEXT) FROM artikel WHERE artikel_id=4')='296.31',
        'generated column computes');
      Check(SQLVal('SELECT count(*) FROM sqlite_master WHERE name IN (''idx_artikel_lower'', '+
        '''idx_artikel_schwer'', ''idx_artikel_preis'', ''idx_bestellung_offen'')')='4',
        'indices on an expression, partial and descending indices kept');
      Check(Pos('WHERE', SQLVal('SELECT sql FROM sqlite_master WHERE name=''idx_artikel_schwer'''))>0,
        'condition of the partial index kept');
      Check(Pos('CHECK', SQLVal('SELECT sql FROM sqlite_master WHERE name=''kategorie'''))>0,
        'CHECK constraints of kategorie kept');
      Check(SQLVal('SELECT count(*) FROM artikel')+'/'+SQLVal('SELECT count(*) FROM kunde')+'/'+
        SQLVal('SELECT count(*) FROM datentypen')='4/3/1', 'rows kept');
      Check(SQLVal('SELECT t_clob FROM datentypen')='Ein langer Text', 'rows of the rebuilt table kept');

      Sync('14. no changes after the synchronisation');
      CheckNoChanges;

      DMDB.SQLConn.Close;
    end;
    finally
      ReleaseSQLite;
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
    WriteLn('SUCCESS: SQLite synchronisation works')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
