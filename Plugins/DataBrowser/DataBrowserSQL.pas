unit DataBrowserSQL;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit DataBrowserSQL.pas
// -----------------------
// Description
//   The SQL of the Data Browser plugin: the SELECT statement that reads the
//   rows of a table for the database type of the connection (limit of rows,
//   filter, sort order), names and values in the notation of the database.
//
//   The unit has no user interface, see Main.pas of the plugin and
//   tests/TestDataBrowser.pas.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils;

const
  //Database types (the names the SQL export uses)
  dbtFireBird = 'FireBird';
  dbtMySQL = 'My SQL';
  dbtOracle = 'Oracle';
  dbtPostgreSQL = 'PostgreSQL';
  dbtSQLServer = 'SQL Server';
  dbtSQLite = 'SQLite';

//The database type for the driver of a database connection. An unknown
//driver (ODBC) is treated as standard SQL without a limit of rows
function BrowserDBType(const DriverName: string): string;

//A name of a table or column. EncloseNames: always in quotes; without it
//only where the database needs them (Firebird: mixed case, reserved words)
function BrowserName(const AName, DBType: string; EncloseNames: Boolean): string;

//A value for a comparison in a filter
function BrowserLiteral(const Value: string; IsNumber: Boolean): string;

//SELECT * for the rows of a table. TableName and OrderBy as BrowserName gives
//them, Where is the condition the user has typed (may be empty). Limit: the
//highest number of rows, 0 = all
function BrowserSelect(const TableName, DBType, Where, OrderBy: string;
  Descending: Boolean; Limit: integer): string;

implementation

uses FirebirdSQL;

function BrowserDBType(const DriverName: string): string;
var s: string;
begin
  s:=UpperCase(DriverName);
  if(Pos('FIREBIRD', s)>0)or(Pos('INTERBASE', s)>0)then
    Result:=dbtFireBird
  else if(Pos('SQLITE', s)>0)then
    Result:=dbtSQLite
  else if(Pos('MYSQL', s)>0)then
    Result:=dbtMySQL
  else if(Pos('ORACLE', s)>0)then
    Result:=dbtOracle
  else if(Pos('MSSQL', s)>0)then
    Result:=dbtSQLServer
  else if(Pos('POSTGRE', s)>0)then
    Result:=dbtPostgreSQL
  else
    Result:='';
end;

function BrowserName(const AName, DBType: string; EncloseNames: Boolean): string;
begin
  if(DBType=dbtFireBird)then
    Result:=FirebirdName(AName, EncloseNames)
  else if(Not(EncloseNames))then
    Result:=AName
  else if(DBType=dbtMySQL)then
    Result:='`'+AName+'`'
  else if(DBType=dbtSQLServer)then
    Result:='['+AName+']'
  else
    Result:='"'+AName+'"';
end;

function BrowserLiteral(const Value: string; IsNumber: Boolean): string;
var s: string;
  d: Double;
  fs: TFormatSettings;
begin
  if(IsNumber)then
  begin
    //a number in the notation of SQL, whatever the display has made of it
    s:=StringReplace(Trim(Value), ',', '.', [rfReplaceAll]);
    fs:=DefaultFormatSettings;
    fs.DecimalSeparator:='.';
    fs.ThousandSeparator:=#0;
    if(TryStrToFloat(s, d, fs))then
    begin
      Result:=s;
      Exit;
    end;
  end;

  Result:=''''+StringReplace(Value, '''', '''''', [rfReplaceAll])+'''';
end;

function BrowserSelect(const TableName, DBType, Where, OrderBy: string;
  Descending: Boolean; Limit: integer): string;
var Cond, Order: string;
begin
  Cond:=Trim(Where);
  //the user may have typed the keyword
  if(CompareText(Copy(Cond, 1, 6), 'WHERE ')=0)then
    Cond:=Trim(Copy(Cond, 7, Length(Cond)));
  //one statement only
  while(Cond<>'')and(Cond[Length(Cond)]=';')do
    Cond:=Trim(Copy(Cond, 1, Length(Cond)-1));

  Order:='';
  if(OrderBy<>'')then
  begin
    Order:=' ORDER BY '+OrderBy;
    if(Descending)then
      Order:=Order+' DESC';
  end;

  if(Limit<=0)or(DBType='')then
  begin
    Result:='SELECT * FROM '+TableName;
    if(Cond<>'')then
      Result:=Result+' WHERE '+Cond;
    Result:=Result+Order;
  end
  else if(DBType=dbtFireBird)then
  begin
    Result:='SELECT FIRST '+IntToStr(Limit)+' * FROM '+TableName;
    if(Cond<>'')then
      Result:=Result+' WHERE '+Cond;
    Result:=Result+Order;
  end
  else if(DBType=dbtSQLServer)then
  begin
    Result:='SELECT TOP '+IntToStr(Limit)+' * FROM '+TableName;
    if(Cond<>'')then
      Result:=Result+' WHERE '+Cond;
    Result:=Result+Order;
  end
  else if(DBType=dbtOracle)then
  begin
    //ROWNUM is counted before the sort: sort inside, limit outside
    Result:='SELECT * FROM '+TableName;
    if(Cond<>'')then
      Result:=Result+' WHERE '+Cond;
    Result:='SELECT * FROM ('+Result+Order+') WHERE ROWNUM <= '+IntToStr(Limit);
  end
  else
  begin
    //MySQL, SQLite, PostgreSQL
    Result:='SELECT * FROM '+TableName;
    if(Cond<>'')then
      Result:=Result+' WHERE '+Cond;
    Result:=Result+Order+' LIMIT '+IntToStr(Limit);
  end;
end;

end.
