program TestDataBrowser;

// The SQL of the Data Browser plugin (Plugins/DataBrowser/DataBrowserSQL.pas):
// the SELECT statements for the database types, and the ones for SQLite
// executed in a fresh database file (limit of rows, filter, sort order).
//
// Needs the application infrastructure (data modules, LCL):
//   lazbuild tests/TestDataBrowser.lpi && bin/TestDataBrowser
// Exit code = number of failed checks.

{$I DBDesigner4.inc}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, Forms, Controls, DB, SQLDB,
  MainDM, DBDM, EERDM, DataBrowserSQL;

var
  ParentForm: TForm;
  Conn: TDBConn;
  DBPath, s, tbl: string;
  Failures: integer = 0;
  i: integer;

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

procedure CheckEq(const Got, Expected, What: string);
begin
  Check(Got=Expected, What);
  if(Got<>Expected)then
  begin
    WriteLn('        got:      ', Got);
    WriteLn('        expected: ', Expected);
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

begin
  Application.Initialize;

  WriteLn('--- 1. the statements');
  CheckEq(BrowserSelect('t', dbtSQLite, '', '', False, 100),
    'SELECT * FROM t LIMIT 100', 'SQLite: LIMIT');
  CheckEq(BrowserSelect('t', dbtMySQL, 'a > 1', '`b`', True, 50),
    'SELECT * FROM t WHERE a > 1 ORDER BY `b` DESC LIMIT 50', 'MySQL: filter, order, limit');
  CheckEq(BrowserSelect('T', dbtFireBird, 'A = 1', 'B', False, 10),
    'SELECT FIRST 10 * FROM T WHERE A = 1 ORDER BY B', 'FireBird: FIRST');
  CheckEq(BrowserSelect('t', dbtSQLServer, '', 'b', False, 10),
    'SELECT TOP 10 * FROM t ORDER BY b', 'SQL Server: TOP');
  CheckEq(BrowserSelect('t', dbtOracle, 'a = 1', 'b', True, 10),
    'SELECT * FROM (SELECT * FROM t WHERE a = 1 ORDER BY b DESC) WHERE ROWNUM <= 10',
    'Oracle: ROWNUM around the sorted rows');
  CheckEq(BrowserSelect('t', dbtPostgreSQL, '', '', False, 0),
    'SELECT * FROM t', 'no limit');
  CheckEq(BrowserSelect('t', '', 'a = 1', '', False, 10),
    'SELECT * FROM t WHERE a = 1', 'unknown database type: no limit clause');
  CheckEq(BrowserSelect('t', dbtSQLite, ' where a = 1 ; ', '', False, 5),
    'SELECT * FROM t WHERE a = 1 LIMIT 5', 'the keyword WHERE and a semicolon of the user');

  CheckEq(BrowserName('order', dbtMySQL, True), '`order`', 'MySQL name in quotes');
  CheckEq(BrowserName('order', dbtSQLServer, True), '[order]', 'SQL Server name in brackets');
  CheckEq(BrowserName('name', dbtSQLite, False), 'name', 'plain name');
  CheckEq(BrowserName('CUSTOMER', dbtFireBird, False), 'CUSTOMER', 'FireBird: regular name');
  CheckEq(BrowserName('date', dbtFireBird, False), '"DATE"', 'FireBird: reserved word in quotes');
  CheckEq(BrowserLiteral('19', True), '19', 'number');
  CheckEq(BrowserLiteral('12,50', True), '12.50', 'number with a decimal comma of the display');
  CheckEq(BrowserLiteral('O''Brien', False), '''O''''Brien''', 'text with a quote');
  CheckEq(BrowserLiteral('abc', True), '''abc''', 'no number after all');
  CheckEq(BrowserDBType('SQLite'), dbtSQLite, 'driver SQLite');
  CheckEq(BrowserDBType('Firebird'), dbtFireBird, 'driver Firebird');
  CheckEq(BrowserDBType('MySQL'), dbtMySQL, 'driver MySQL');
  CheckEq(BrowserDBType('ODBC'), '', 'driver ODBC: unknown');

  //------------------------------------------------------------
  WriteLn;
  WriteLn('--- 2. executed in SQLite');
  DBPath:=GetTempDir+'dbdesigner_browser_test.db';
  if(FileExists(DBPath))then
    DeleteFile(DBPath);

  //The main form: TDMDB.ConnectToDB posts an event to Application.MainForm
  Application.CreateForm(TForm, ParentForm);
  Conn:=TDBConn.Create;
  try
  try
    DMMain:=TDMMain.Create(ParentForm);
    DMDB:=TDMDB.Create(ParentForm);
    DMEER:=TDMEER.Create(ParentForm);

    Conn.Name:='BrowserTest';
    Conn.DriverName:='SQLite';
    Conn.Params.Values['Database']:=DBPath;
    DMDB.ConnectToDB(Conn);

    DMDB.ExecSQL('CREATE TABLE "order" (id INTEGER PRIMARY KEY, name VARCHAR(40), amount NUMERIC(8,2))', True);
    for i:=1 to 30 do
      DMDB.ExecSQL('INSERT INTO "order" (id, name, amount) VALUES ('+IntToStr(i)+
        ', ''name '+Chr(Ord('a')+(i mod 7))+''', '+IntToStr(i*3 mod 11)+'.50)', True);

    tbl:=BrowserName('order', dbtSQLite, True);
    s:=SQLVal(BrowserSelect(tbl, dbtSQLite, '', '', False, 10));
    Check(Length(s)-Length(StringReplace(s, ',', '', [rfReplaceAll]))=9, '10 rows with the limit 10');
    s:=SQLVal(BrowserSelect(tbl, dbtSQLite, '', '', False, 0));
    Check(Length(s)-Length(StringReplace(s, ',', '', [rfReplaceAll]))=29, 'all 30 rows without a limit');
    CheckEq(SQLVal(BrowserSelect(tbl, dbtSQLite, '', BrowserName('id', dbtSQLite, True), True, 3)),
      '30,29,28', 'descending order with a limit');
    CheckEq(SQLVal(BrowserSelect(tbl, dbtSQLite,
      BrowserName('id', dbtSQLite, True)+' = '+BrowserLiteral('19', True), '', False, 500)),
      '19', 'the filter of a foreign key jump');
    CheckEq(SQLVal(BrowserSelect(tbl, dbtSQLite, 'name = '+BrowserLiteral('name a', False)+' AND id < 10',
      'id', False, 500)), '7', 'a text filter');

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
  end;

  WriteLn;
  if(Failures=0)then
    WriteLn('SUCCESS: the SQL of the data browser works')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
