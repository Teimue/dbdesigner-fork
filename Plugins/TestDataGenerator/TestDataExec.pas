unit TestDataExec;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit TestDataExec.pas
// ---------------------
// Description
//   Executes a script of the test data generator (TestDataGen.pas) in the
//   database DMDB is connected to: all statements in one transaction, which
//   is rolled back when a statement fails.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils;

//The entry of TestDataTargets for the driver of a database connection, ''
//when the driver does not tell (ODBC)
function TargetDBOfDriver(const DriverName: string): string;

//Returns the number of executed statements, or -1 when a statement has
//failed: ErrorMsg is the message of the database and ErrorStmt the statement,
//and nothing of the script is left in the database (as far as the database
//keeps transactions - not for the MyISAM tables of MySQL)
function ExecuteTestDataScript(Script: TStrings; out ErrorMsg, ErrorStmt: string): integer;

implementation

uses DB, SQLDB, DBDM;

function TargetDBOfDriver(const DriverName: string): string;
var s: string;
begin
  s:=UpperCase(DriverName);
  if(Pos('FIREBIRD', s)>0)or(Pos('INTERBASE', s)>0)then
    Result:='FireBird'
  else if(Pos('SQLITE', s)>0)then
    Result:='SQLite'
  else if(Pos('MYSQL', s)>0)then
    Result:='My SQL'
  else if(Pos('ORACLE', s)>0)then
    Result:='Oracle'
  else if(Pos('MSSQL', s)>0)then
    Result:='SQL Server'
  else if(Pos('POSTGRE', s)>0)then
    Result:='PostgreSQL'
  else
    Result:='';
end;

function ExecuteTestDataScript(Script: TStrings; out ErrorMsg, ErrorStmt: string): integer;
var Q: SQLDB.TSQLQuery;
  Trans: SQLDB.TSQLTransaction;
  i: integer;
  stmt: string;
begin
  Result:=0;
  ErrorMsg:='';
  ErrorStmt:='';

  Trans:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
  //what was done before belongs to the database, a rollback must not
  //take it back
  if(Trans.Active)then
    Trans.CommitRetaining
  else
    Trans.StartTransaction;

  Q:=SQLDB.TSQLQuery.Create(nil);
  try
    Q.DataBase:=DMDB.SQLConn;
    Q.Transaction:=Trans;
    //a colon in a value (a time, a URL) is no parameter
    Q.ParamCheck:=False;

    try
      for i:=0 to Script.Count-1 do
      begin
        stmt:=Trim(Script[i]);
        if(stmt='')or(Copy(stmt, 1, 2)='--')then
          continue;
        if(Copy(stmt, Length(stmt), 1)=';')then
          Delete(stmt, Length(stmt), 1);
        //the transaction is committed below
        if(CompareText(Trim(stmt), 'COMMIT')=0)then
          continue;

        ErrorStmt:=stmt;
        Q.SQL.Text:=stmt;
        Q.ExecSQL;
        inc(Result);
      end;

      ErrorStmt:='';
      Trans.CommitRetaining;
    except
      on E: Exception do
      begin
        ErrorMsg:=E.Message;
        try
          Trans.RollbackRetaining;
        except
        end;
        Result:=-1;
      end;
    end;
  finally
    Q.Free;
  end;
end;

end.
