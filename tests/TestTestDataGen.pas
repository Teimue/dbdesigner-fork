program TestTestDataGen;

// The test data generator (Plugins/TestDataGenerator/TestDataGen.pas), run on
// bin/Examples/order.xml: the script for SQLite is executed in a fresh
// database that the synchronisation has created from the model. Checks the
// number of rows, the foreign keys, unique keys and that the same seed gives
// the same script.
//
// Needs the application infrastructure (data modules, LCL):
//   lazbuild tests/TestTestDataGen.lpi && bin/TestTestDataGen
// Run it from the project directory. Exit code = number of failed checks.

{$I DBDesigner4.inc}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, Forms, Controls, DB, SQLDB,
  MainDM, DBDM, EERDM, DBEERDM, EERModel, TestDataGen, TestDataExec;

var
  ParentForm: TForm;
  Model: TEERModel;
  Conn: TDBConn;
  Log, Script, Script2, Counts: TStringList;
  Tables, AllTables: TList;
  DBPath, s, ErrStmt: string;
  Failures: integer = 0;
  Opt: TTestDataOptions;
  i, n, Errors: integer;

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

//Execute the statements of a script, return the number of errors
function RunScript(Lines: TStrings): integer;
var k: integer;
  l: string;
begin
  Result:=0;
  for k:=0 to Lines.Count-1 do
  begin
    l:=Trim(Lines[k]);
    if(l='')or(Copy(l, 1, 2)='--')or(l='COMMIT;')then
      continue;
    try
      DMDB.ExecSQL(Copy(l, 1, Length(l)-1), True);
    except
      on E: Exception do
      begin
        inc(Result);
        if(Result<=5)then
          WriteLn('  SQL error: ', E.Message, #13#10'    ', l);
      end;
    end;
  end;
end;

begin
  Application.Initialize;

  DBPath:=GetTempDir+'dbdesigner_testdata_test.db';
  if(FileExists(DBPath))then
    DeleteFile(DBPath);

  //The main form: TDMDB.ConnectToDB posts an event to Application.MainForm
  Application.CreateForm(TForm, ParentForm);
  Log:=TStringList.Create;
  Script:=TStringList.Create;
  Script2:=TStringList.Create;
  Counts:=TStringList.Create;
  Tables:=TList.Create;
  Conn:=TDBConn.Create;
  try
  try
    DMMain:=TDMMain.Create(ParentForm);
    DMDB:=TDMDB.Create(ParentForm);
    DMEER:=TDMEER.Create(ParentForm);

    Model:=TEERModel.Create(ParentForm);
    Model.Parent:=ParentForm;
    Model.LoadFromFile('bin'+PathDelim+'Examples'+PathDelim+'order.xml');

    Conn.Name:='TestDataTest';
    Conn.DriverName:='SQLite';
    Conn.Params.Values['Database']:=DBPath;
    DMDB.ConnectToDB(Conn);

    //The tables of the model
    DMDBEER.EERMySQLSyncDB(Model, Conn, Log, True, True, False);
    DMDB.ExecSQL('PRAGMA foreign_keys = ON', True);

    Model.GetEERObjectList([EERTable], Tables);
    //not the tables of the linked models, the database does not have them
    for i:=Tables.Count-1 downto 0 do
      if(Not(TableHasSQL(Model, TEERTable(Tables[i]))))then
        Tables.Delete(i);
    Check(Tables.Count>5, IntToStr(Tables.Count)+' tables in the model');

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 1. 20 rows for every table');
    Opt:=DefaultTestDataOptions;
    Opt.TargetDB:='SQLite';
    Opt.DefaultRows:=20;
    Opt.DeleteFirst:=True;
    Opt.German:=True;
    Opt.Seed:=7;
    Counts.Values['product']:='50';

    n:=GenerateTestData(Model, Tables, Counts, Opt, Script);
    Script.SaveToFile(GetTempDir+'dbdesigner_testdata_test.sql');
    Check(n>100, IntToStr(n)+' INSERT statements');

    Errors:=RunScript(Script);
    Check(Errors=0, 'the script runs without errors');

    Check(SQLVal('SELECT count(*) FROM product')='50', '50 rows in product (own row count)');
    Check(SQLVal('SELECT count(*) FROM onlinecustomer')='20', '20 rows in onlinecustomer');
    Check(SQLVal('SELECT count(*) FROM onlineorder')='20', '20 rows in onlineorder');
    Check(StrToIntDef(SQLVal('SELECT count(*) FROM onlineorderhasproduct'), 0)>0,
      'rows in the n:m table onlineorderhasproduct');
    Check(SQLVal('SELECT count(*) FROM pragma_foreign_key_check')='0', 'no foreign key violations');
    Check(SQLVal('SELECT count(*) FROM onlineorder o WHERE NOT EXISTS '+
      '(SELECT 1 FROM onlinecustomer c WHERE c.idonlinecustomer=o.idonlinecustomer)')='0',
      'every order has an existing customer');
    Check(StrToIntDef(SQLVal('SELECT count(DISTINCT idonlinecustomer) FROM onlineorder'), 0)>1,
      'the orders belong to different customers');
    Check(SQLVal('SELECT count(*) FROM onlinecustomer WHERE length(zip)>6')='0',
      'no value longer than its column (zip VARCHAR(6))');
    s:=SQLVal('SELECT name FROM onlinecustomer LIMIT 3');
    WriteLn('    names: ', s);
    Check(Trim(s)<>'', 'names are filled');

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 2. the same seed, another seed');
    GenerateTestData(Model, Tables, Counts, Opt, Script2);
    Check(Script.Text=Script2.Text, 'the same seed gives the same script');
    Script2.Clear;
    Opt.Seed:=8;
    GenerateTestData(Model, Tables, Counts, Opt, Script2);
    Check(Script.Text<>Script2.Text, 'another seed gives other data');
    Errors:=RunScript(Script2);
    Check(Errors=0, 'the second script runs too (DELETE first)');
    Check(SQLVal('SELECT count(*) FROM pragma_foreign_key_check')='0', 'no foreign key violations');

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 2b. executed in one transaction (TestDataExec)');
    n:=ExecuteTestDataScript(Script, s, ErrStmt);
    Check(n>270, IntToStr(n)+' statements executed, the script of step 1 again');
    Check(SQLVal('SELECT count(*) FROM product')='50', '50 rows in product');
    Check(SQLVal('SELECT count(*) FROM pragma_foreign_key_check')='0', 'no foreign key violations');
    //a script that fails in the middle leaves nothing behind
    Script2.Clear;
    Script2.Add('DELETE FROM onlineorderhasproduct;');
    Script2.Add('INSERT INTO webserver (idwebserver, name) VALUES (9001, ''rollback test'');');
    Script2.Add('INSERT INTO no_such_table (a) VALUES (1);');
    n:=ExecuteTestDataScript(Script2, s, ErrStmt);
    Check(n=-1, 'a failing statement is reported');
    Check(Pos('no_such_table', ErrStmt)>0, 'with the statement');
    Check(s<>'', 'and the message of the database');
    Check(SQLVal('SELECT count(*) FROM webserver WHERE idwebserver=9001')='0', 'the insert before it is rolled back');
    Check(StrToIntDef(SQLVal('SELECT count(*) FROM onlineorderhasproduct'), 0)>0, 'the delete before it too');
    Check(TargetDBOfDriver('SQLite')='SQLite', 'target database of the SQLite driver');

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 3. only a table that references others');
    AllTables:=TList.Create;
    AllTables.Assign(Tables);
    Tables.Clear;
    for i:=0 to Model.ComponentCount-1 do
      if(Model.Components[i] is TEERTable)then
        if(CompareText(TEERTable(Model.Components[i]).ObjName, 'onlineorder')=0)then
          Tables.Add(Model.Components[i]);
    Script2.Clear;
    Opt.DeleteFirst:=False;
    n:=GenerateTestData(Model, Tables, nil, Opt, Script2);
    Check(n=20, '20 statements for the one table');
    Check(Pos('no rows of onlinecustomer', Script2.Text)>0, 'the script says that the customers are missing');

    //------------------------------------------------------------
    WriteLn;
    WriteLn('--- 4. the other databases');
    Tables.Assign(AllTables);
    AllTables.Free;
    Opt.TargetDB:='FireBird';
    Script2.Clear;
    GenerateTestData(Model, Tables, nil, Opt, Script2);
    Check(Pos('INSERT INTO ', Script2.Text)>0, 'FireBird script');
    Opt.TargetDB:='Oracle';
    Script2.Clear;
    GenerateTestData(Model, Tables, nil, Opt, Script2);
    Check((Pos('DATE ''', Script2.Text)>0)or(Pos('TIMESTAMP ''', Script2.Text)>0),
      'Oracle script with DATE / TIMESTAMP literals');
    Opt.TargetDB:='SQL Server';
    Script2.Clear;
    GenerateTestData(Model, Tables, nil, Opt, Script2);
    Check(Pos('SET IDENTITY_INSERT', Script2.Text)>0, 'SQL Server script with IDENTITY_INSERT');
    Opt.SkipAutoInc:=True;
    Script2.Clear;
    GenerateTestData(Model, Tables, nil, Opt, Script2);
    Check(Pos('SET IDENTITY_INSERT', Script2.Text)=0, 'not when the auto increment columns are left out');

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
    Log.Free;
    Script.Free;
    Script2.Free;
    Counts.Free;
    Tables.Free;
  end;

  WriteLn;
  if(Failures=0)then
    WriteLn('SUCCESS: the test data generator works')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
