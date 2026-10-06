unit FirebirdSQL;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit FirebirdSQL.pas
// --------------------
// Description
//   How Firebird writes names and datatypes. Used by the SQL export for the
//   FireBird target (EERModel) and by the database synchronisation
//   (DBEERFirebird). No dependencies, so that EERModel can use it.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

//The name in double quotes, i.e. exactly as written
function FirebirdQuote(const s: string): string;

//The reserved words of Firebird 5: not usable as a name without quotes
function FirebirdIsReservedWord(const s: string): Boolean;

//The name the database stores for an object of the model. Firebird folds
//names that are not quoted to upper case; quoted names are case sensitive.
//EncloseNames: the "enclose names" option, all names are quoted as written
function FirebirdStoredName(const s: string; EncloseNames: Boolean): string;

//A name of the model in a statement. Without EncloseNames a name is written
//as it is; a reserved word is quoted in upper case, i.e. the way every
//other name is stored
function FirebirdName(const s: string; EncloseNames: Boolean): string;

//The Firebird datatype for a datatype of the model (the MySQL types) with
//its parameters, e.g. ('DATETIME', '') -> 'TIMESTAMP',
//('Varchar', '(45)') -> 'VARCHAR(45)'
function FirebirdDatatype(const TypeName, Params: string): string;

implementation

uses SysUtils;

function FirebirdQuote(const s: string): string;
begin
  FirebirdQuote:='"'+StringReplace(s, '"', '""', [rfReplaceAll])+'"';
end;

function IsRegularIdentifier(const s: string): Boolean;
var i: integer;
begin
  Result:=(s<>'')and(s[1] in ['A'..'Z', 'a'..'z']);
  for i:=2 to Length(s) do
    if(Not(s[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']))then
      Result:=False;
end;

function FirebirdIsReservedWord(const s: string): Boolean;
const
  Words = ',ADD,ADMIN,ALL,ALTER,AND,ANY,AS,AT,AVG,BEGIN,BETWEEN,BIGINT,BINARY,'+
    'BIT_LENGTH,BLOB,BOOLEAN,BOTH,BY,CASE,CAST,CHAR,CHAR_LENGTH,CHARACTER,'+
    'CHARACTER_LENGTH,CHECK,CLOSE,COLLATE,COLUMN,COMMENT,COMMIT,CONNECT,'+
    'CONSTRAINT,CORR,COUNT,COVAR_POP,COVAR_SAMP,CREATE,CROSS,CURRENT,'+
    'CURRENT_CONNECTION,CURRENT_DATE,CURRENT_ROLE,CURRENT_TIME,'+
    'CURRENT_TIMESTAMP,CURRENT_TRANSACTION,CURRENT_USER,CURSOR,DATE,DAY,DEC,'+
    'DECFLOAT,DECIMAL,DECLARE,DEFAULT,DELETE,DELETING,DETERMINISTIC,'+
    'DISCONNECT,DISTINCT,DOUBLE,DROP,ELSE,END,ESCAPE,EXECUTE,EXISTS,EXTERNAL,'+
    'EXTRACT,FALSE,FETCH,FILTER,FLOAT,FOR,FOREIGN,FROM,FULL,FUNCTION,GDSCODE,'+
    'GLOBAL,GRANT,GROUP,HAVING,HOUR,IN,INDEX,INNER,INSENSITIVE,INSERT,'+
    'INSERTING,INT,INT128,INTEGER,INTO,IS,JOIN,LATERAL,LEADING,LEFT,LIKE,'+
    'LOCAL,LOCALTIME,LOCALTIMESTAMP,LONG,LOWER,MAX,MERGE,MIN,MINUTE,MONTH,'+
    'NATIONAL,NATURAL,NCHAR,NO,NOT,NULL,NUMERIC,OCTET_LENGTH,OF,OFFSET,ON,'+
    'ONLY,OPEN,OR,ORDER,OUTER,OVER,PARAMETER,PLAN,POSITION,POST_EVENT,'+
    'PRECISION,PRIMARY,PROCEDURE,PUBLICATION,REAL,RECORD_VERSION,RECREATE,'+
    'RECURSIVE,REFERENCES,REGR_AVGX,REGR_AVGY,REGR_COUNT,REGR_INTERCEPT,'+
    'REGR_R2,REGR_SLOPE,REGR_SXX,REGR_SXY,REGR_SYY,RELEASE,RESETTING,RETURN,'+
    'RETURNING_VALUES,RETURNS,REVOKE,RIGHT,ROLLBACK,ROW,ROW_COUNT,ROWS,'+
    'SAVEPOINT,SCROLL,SECOND,SELECT,SENSITIVE,SET,SIMILAR,SMALLINT,SOME,'+
    'SQLCODE,SQLSTATE,START,STDDEV_POP,STDDEV_SAMP,SUM,TABLE,THEN,TIME,'+
    'TIMESTAMP,TIMEZONE_HOUR,TIMEZONE_MINUTE,TO,TRAILING,TRIGGER,TRIM,TRUE,'+
    'UNBOUNDED,UNION,UNIQUE,UNKNOWN,UPDATE,UPDATING,UPPER,USER,USING,VALUE,'+
    'VALUES,VAR_POP,VAR_SAMP,VARBINARY,VARCHAR,VARIABLE,VARYING,VIEW,WHEN,'+
    'WHERE,WHILE,WINDOW,WITH,WITHOUT,YEAR,';
begin
  Result:=(Pos(','+UpperCase(s)+',', Words)>0)or(Copy(UpperCase(s), 1, 4)='RDB$');
end;

function FirebirdStoredName(const s: string; EncloseNames: Boolean): string;
begin
  if(EncloseNames)or(Not(IsRegularIdentifier(s)))then
    FirebirdStoredName:=s
  else
    FirebirdStoredName:=UpperCase(s);
end;

function FirebirdName(const s: string; EncloseNames: Boolean): string;
begin
  if(EncloseNames)or(Not(IsRegularIdentifier(s)))or(FirebirdIsReservedWord(s))then
    FirebirdName:=FirebirdQuote(FirebirdStoredName(s, EncloseNames))
  else
    FirebirdName:=s;
end;

function FirebirdDatatype(const TypeName, Params: string): string;
var n, p: string;
begin
  n:=UpperCase(Trim(TypeName));
  //'(10, 2)' -> '(10,2)'
  p:=StringReplace(Trim(Params), ' ', '', [rfReplaceAll]);

  if(n='TINYINT')or(n='SMALLINT')or(n='YEAR')or(n='BIT')then
    Result:='SMALLINT'
  else if(n='MEDIUMINT')or(n='INT')or(n='INTEGER')then
    Result:='INTEGER'
  else if(n='BIGINT')then
    Result:='BIGINT'
  else if(n='FLOAT')then
    Result:='FLOAT'
  else if(n='DOUBLE')or(n='DOUBLE_PRECISION')or(n='DOUBLE PRECISION')or(n='REAL')then
    Result:='DOUBLE PRECISION'
  else if(n='DECIMAL')or(n='NUMERIC')then
    Result:=n+p
  else if(n='DATETIME')or(n='TIMESTAMP')then
    Result:='TIMESTAMP'
  else if(n='DATE')or(n='TIME')then
    Result:=n
  else if(n='CHAR')then
  begin
    if(p='')then
      p:='(1)';
    Result:='CHAR'+p;
  end
  else if(n='VARCHAR')then
  begin
    if(p='')then
      p:='(255)';
    Result:='VARCHAR'+p;
  end
  else if(n='TINYTEXT')or(n='TEXT')or(n='MEDIUMTEXT')or(n='LONGTEXT')then
    Result:='BLOB SUB_TYPE TEXT'
  else if(n='TINYBLOB')or(n='BLOB')or(n='MEDIUMBLOB')or(n='LONGBLOB')then
    Result:='BLOB SUB_TYPE BINARY'
  else if(n='BOOL')or(n='BOOLEAN')then
    Result:='BOOLEAN'
  else if(n='ENUM')or(n='SET')then
    Result:='VARCHAR(255)'
  else
    //Not a MySQL type: take it as it is (a Firebird type or a domain)
    Result:=n+p;
end;

end.
