unit DBEERFirebird;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit DBEERFirebird.pas
// ----------------------
// Description
//   Reverse engineering and database synchronisation for Firebird (3.0 and
//   newer), both through the system tables (RDB$...).
//
//   The model keeps the MySQL datatypes; FirebirdSQL.FirebirdDatatype maps
//   them to Firebird types and the reverse engineering maps them back.
//
//   Synchronisation: the columns of a model table are created as a temporary
//   table and compared with the existing table through the system tables, so
//   both sides are seen the way Firebird sees them. Firebird has ALTER TABLE
//   for nearly everything, so the differences are applied statement by
//   statement, each one committed like isql does (a DDL statement only takes
//   effect at commit). A failing statement is logged and the sync goes on.
//   Foreign keys are dropped before and added after the table changes, so
//   the order of the tables does not matter. Firebird cannot rename a table:
//   a renamed table is created anew, the rows are copied and the old table
//   is dropped.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses SysUtils, Classes, StdCtrls, EERModel, DBEERSQLiteSync;

//The Firebird datatype of a model column, e.g. VARCHAR(45)
function FirebirdColumnType(theModel: TEERModel; theColumn: TEERColumn): string;

procedure FirebirdReverseEngineer(EERModel: TEERModel; theTables: TStringList;
  XCount: integer; BuildRelations, BuildRelUsingPrimKey: Boolean;
  DatatypeSubst: TStringList; StatusLbl: TLabel;
  CreateStdInserts: Boolean; limitStdIns: integer);

//The user tables of the connected database
procedure FirebirdGetTables(theList: TStrings);

//ModelTables: the tables to sync
//DbTables: the user tables of the database, kept up to date
//Failures are collected in SyncErrors ("what"+CRLF+"message") and logged
procedure FirebirdSyncTables(EERModel: TEERModel; ModelTables: TList;
  DbTables: TStringList; Log: TStrings; SyncErrors: TStrings;
  KeepExTbls, StdInsertsOnCreate: Boolean; var C: TSQLiteSyncCounters);

implementation

uses DB, SQLDB, Forms, Dialogs, Controls, MainDM, DBDM, EERDM, DBEERDM, FirebirdSQL;

const
  UserTablesSQL = 'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS '+
    'WHERE COALESCE(RDB$SYSTEM_FLAG, 0)=0 AND RDB$VIEW_BLR IS NULL '+
    'ORDER BY RDB$RELATION_NAME';

  //Foreign keys: one row per column pair. %s: the WHERE condition
  ForeignKeysSQL = 'SELECT TRIM(rc.RDB$CONSTRAINT_NAME) AS FKNAME, '+
    'TRIM(rc.RDB$RELATION_NAME) AS TBLNAME, TRIM(pk.RDB$RELATION_NAME) AS REFTABLE, '+
    'TRIM(ref.RDB$UPDATE_RULE) AS UPDRULE, TRIM(ref.RDB$DELETE_RULE) AS DELRULE, '+
    'TRIM(s.RDB$FIELD_NAME) AS COLNAME, TRIM(ps.RDB$FIELD_NAME) AS REFCOLNAME '+
    'FROM RDB$RELATION_CONSTRAINTS rc '+
    'JOIN RDB$REF_CONSTRAINTS ref ON ref.RDB$CONSTRAINT_NAME=rc.RDB$CONSTRAINT_NAME '+
    'JOIN RDB$RELATION_CONSTRAINTS pk ON pk.RDB$CONSTRAINT_NAME=ref.RDB$CONST_NAME_UQ '+
    'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME=rc.RDB$INDEX_NAME '+
    'JOIN RDB$INDEX_SEGMENTS ps ON ps.RDB$INDEX_NAME=pk.RDB$INDEX_NAME '+
    'AND ps.RDB$FIELD_POSITION=s.RDB$FIELD_POSITION '+
    'WHERE rc.RDB$CONSTRAINT_TYPE=''FOREIGN KEY'' AND %s '+
    'ORDER BY rc.RDB$RELATION_NAME, rc.RDB$CONSTRAINT_NAME, s.RDB$FIELD_POSITION';

  //The indices of a table with their columns, one row per column.
  //Expression indices have no columns and are left out
  IndicesSQL = 'SELECT TRIM(i.RDB$INDEX_NAME) AS IDXNAME, '+
    'COALESCE(i.RDB$UNIQUE_FLAG, 0) AS IDXUNIQUE, COALESCE(i.RDB$INDEX_TYPE, 0) AS IDXDESC, '+
    'TRIM(s.RDB$FIELD_NAME) AS COLNAME, TRIM(rc.RDB$CONSTRAINT_TYPE) AS CONSTRTYPE, '+
    'TRIM(rc.RDB$CONSTRAINT_NAME) AS CONSTRNAME '+
    'FROM RDB$INDICES i '+
    'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME=i.RDB$INDEX_NAME '+
    'LEFT JOIN RDB$RELATION_CONSTRAINTS rc ON rc.RDB$INDEX_NAME=i.RDB$INDEX_NAME '+
    'WHERE i.RDB$RELATION_NAME=%s AND COALESCE(i.RDB$SYSTEM_FLAG, 0)=0 '+
    'ORDER BY i.RDB$INDEX_NAME, s.RDB$FIELD_POSITION';

type
  TFBColInfo = record
    Name,
    Typ,           //Firebird type, e.g. NUMERIC(10,2)
    Dflt,          //default value without the DEFAULT keyword
    Comment: string;
    NotNull, Identity: Boolean;
  end;
  TFBColInfos = array of TFBColInfo;

// -----------------------------------------------------------------------------
// Shared helpers

//The name exactly as it is stored in the database
function QId(const s: string): string;
begin
  QId:=FirebirdQuote(s);
end;

//A name of the model in a statement that creates the object
function NewId(const s: string): string;
begin
  NewId:=FirebirdName(s, DMEER.EncloseNames);
end;

//The name the database stores for NewId(s)
function StoredName(const s: string): string;
begin
  StoredName:=FirebirdStoredName(s, DMEER.EncloseNames);
end;

function FirebirdColumnType(theModel: TEERModel; theColumn: TEERColumn): string;
begin
  Result:=FirebirdDatatype(
    TEERDatatype(theModel.GetDataType(theColumn.idDatatype)).GetPhysicalTypeName,
    theColumn.DatatypeParams);
end;

//The type of a column as SQL, from the values of RDB$FIELDS
function FirebirdTypeSQL(FType, SubType, Len, CharLen, Prec, Scale, CharSetId: integer): string;

  function Numeric(const IntName: string; DefPrec: integer): string;
  begin
    if(Prec=0)then
      Prec:=DefPrec;
    if(SubType=2)then
      Result:='DECIMAL('+IntToStr(Prec)+','+IntToStr(-Scale)+')'
    else if(SubType=1)or(Scale<0)then
      Result:='NUMERIC('+IntToStr(Prec)+','+IntToStr(-Scale)+')'
    else
      Result:=IntName;
  end;

begin
  if(CharLen=0)then
    CharLen:=Len;

  case FType of
    7: Result:=Numeric('SMALLINT', 4);
    8: Result:=Numeric('INTEGER', 9);
    16: Result:=Numeric('BIGINT', 18);
    26: Result:=Numeric('INT128', 38);
    10: Result:='FLOAT';
    27: Result:='DOUBLE PRECISION';
    12: Result:='DATE';
    13: Result:='TIME';
    35: Result:='TIMESTAMP';
    28: Result:='TIME WITH TIME ZONE';
    29: Result:='TIMESTAMP WITH TIME ZONE';
    14:
      //Character set OCTETS
      if(CharSetId=1)then
        Result:='BINARY('+IntToStr(Len)+')'
      else
        Result:='CHAR('+IntToStr(CharLen)+')';
    37:
      if(CharSetId=1)then
        Result:='VARBINARY('+IntToStr(Len)+')'
      else
        Result:='VARCHAR('+IntToStr(CharLen)+')';
    261:
      if(SubType=1)then
        Result:='BLOB SUB_TYPE TEXT'
      else
        Result:='BLOB SUB_TYPE BINARY';
    23: Result:='BOOLEAN';
    24: Result:='DECFLOAT(16)';
    25: Result:='DECFLOAT(34)';
  else
    Result:='UNKNOWN('+IntToStr(FType)+')';
  end;
end;

//The default as it is written in the DDL, without the keyword
function StripDefaultKeyword(const s: string): string;
begin
  Result:=Trim(s);
  if(CompareText(Copy(Result, 1, 7), 'DEFAULT')=0)then
    Result:=Trim(Copy(Result, 8, Length(Result)))
  else if(Copy(Result, 1, 1)='=')then
    Result:=Trim(Copy(Result, 2, Length(Result)));
end;

function NewQuery: SQLDB.TSQLQuery;
begin
  if(DMDB.SchemaSQLQuery.Active)then
    DMDB.SchemaSQLQuery.Close;

  Result:=SQLDB.TSQLQuery.Create(nil);
  Result.DataBase:=DMDB.SQLConn;
  Result.Transaction:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
  Result.ParamCheck:=False;

  if(Not(Result.Transaction.Active))then
    SQLDB.TSQLTransaction(Result.Transaction).StartTransaction
  else
    SQLDB.TSQLTransaction(Result.Transaction).CommitRetaining;
end;

//First field of the first row, '' when there is no row
function QueryStr(Q: SQLDB.TSQLQuery; const stmt: string): string;
begin
  Result:='';
  Q.SQL.Text:=stmt;
  Q.Open;
  try
    if(Not(Q.EOF))then
      Result:=Q.Fields[0].AsString;
  finally
    Q.Close;
  end;
end;

//Major version of the server
function EngineVersion(Q: SQLDB.TSQLQuery): integer;
var s: string;
begin
  Result:=0;
  try
    s:=QueryStr(Q, 'SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') FROM RDB$DATABASE');
    if(Pos('.', s)>0)then
      Result:=StrToIntDef(Copy(s, 1, Pos('.', s)-1), 0);
  except
    Result:=0;
  end;
end;

//The columns of a table in their order
procedure LoadColumns(Q: SQLDB.TSQLQuery; const tbl: string; EngineVer: integer;
  var Cols: TFBColInfos);
var n: integer;
  identCol: string;
begin
  //Identity columns came with Firebird 3
  if(EngineVer>=3)then
    identCol:='rf.RDB$IDENTITY_TYPE'
  else
    identCol:='CAST(NULL AS SMALLINT)';

  SetLength(Cols, 0);
  Q.SQL.Text:='SELECT TRIM(rf.RDB$FIELD_NAME) AS COLNAME, f.RDB$FIELD_TYPE AS FTYPE, '+
    'COALESCE(f.RDB$FIELD_SUB_TYPE, 0) AS FSUBTYPE, COALESCE(f.RDB$FIELD_LENGTH, 0) AS FLEN, '+
    'COALESCE(f.RDB$CHARACTER_LENGTH, 0) AS FCHARLEN, COALESCE(f.RDB$FIELD_PRECISION, 0) AS FPREC, '+
    'COALESCE(f.RDB$FIELD_SCALE, 0) AS FSCALE, COALESCE(f.RDB$CHARACTER_SET_ID, 0) AS FCHARSET, '+
    'COALESCE(rf.RDB$NULL_FLAG, f.RDB$NULL_FLAG, 0) AS NOTNULLFLAG, '+
    'COALESCE(rf.RDB$DEFAULT_SOURCE, f.RDB$DEFAULT_SOURCE) AS DEFSRC, '+
    identCol+' AS IDENTTYPE, rf.RDB$DESCRIPTION AS DESCR '+
    'FROM RDB$RELATION_FIELDS rf '+
    'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME=rf.RDB$FIELD_SOURCE '+
    'WHERE rf.RDB$RELATION_NAME='+QuotedStr(tbl)+' '+
    'ORDER BY rf.RDB$FIELD_POSITION';
  Q.Open;
  try
    while(Not(Q.EOF))do
    begin
      n:=Length(Cols);
      SetLength(Cols, n+1);
      Cols[n].Name:=Q.FieldByName('COLNAME').AsString;
      Cols[n].Typ:=FirebirdTypeSQL(Q.FieldByName('FTYPE').AsInteger,
        Q.FieldByName('FSUBTYPE').AsInteger, Q.FieldByName('FLEN').AsInteger,
        Q.FieldByName('FCHARLEN').AsInteger, Q.FieldByName('FPREC').AsInteger,
        Q.FieldByName('FSCALE').AsInteger, Q.FieldByName('FCHARSET').AsInteger);
      Cols[n].NotNull:=(Q.FieldByName('NOTNULLFLAG').AsInteger=1);
      Cols[n].Dflt:='';
      if(Not(Q.FieldByName('DEFSRC').IsNull))then
        Cols[n].Dflt:=StripDefaultKeyword(Q.FieldByName('DEFSRC').AsString);
      Cols[n].Identity:=Not(Q.FieldByName('IDENTTYPE').IsNull);
      Cols[n].Comment:='';
      if(Not(Q.FieldByName('DESCR').IsNull))then
        Cols[n].Comment:=Trim(Q.FieldByName('DESCR').AsString);
      Q.Next;
    end;
  finally
    Q.Close;
  end;
end;

//The columns of the primary key in their order, the name of the constraint
procedure LoadPrimaryKey(Q: SQLDB.TSQLQuery; const tbl: string;
  var ConstraintName: string; Cols: TStrings);
begin
  ConstraintName:='';
  Cols.Clear;
  Q.SQL.Text:='SELECT TRIM(rc.RDB$CONSTRAINT_NAME), TRIM(s.RDB$FIELD_NAME) '+
    'FROM RDB$RELATION_CONSTRAINTS rc '+
    'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME=rc.RDB$INDEX_NAME '+
    'WHERE rc.RDB$CONSTRAINT_TYPE=''PRIMARY KEY'' AND rc.RDB$RELATION_NAME='+QuotedStr(tbl)+' '+
    'ORDER BY s.RDB$FIELD_POSITION';
  Q.Open;
  try
    while(Not(Q.EOF))do
    begin
      ConstraintName:=Q.Fields[0].AsString;
      Cols.Add(Q.Fields[1].AsString);
      Q.Next;
    end;
  finally
    Q.Close;
  end;
end;

function FirebirdRefActionCode(const action: string): string;
begin
  //Codes as used by TEERRel.RefDef (see TEERTable.GetSQLCreateCode)
  if(action='CASCADE')then
    Result:='1'
  else if(action='SET NULL')then
    Result:='2'
  else if(action='SET DEFAULT')then
    Result:='4'
  else if(action='NO ACTION')then
    Result:='3'
  else
    Result:='0'; //RESTRICT
end;

procedure FirebirdGetTables(theList: TStrings);
var Q: SQLDB.TSQLQuery;
begin
  theList.Clear;
  Q:=NewQuery;
  try
    Q.SQL.Text:=UserTablesSQL;
    Q.Open;
    while(Not(Q.EOF))do
    begin
      theList.Add(Q.Fields[0].AsString);
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Reverse engineering

//The model datatype for a Firebird type like NUMERIC(10,2)
function ModelDatatype(EERModel: TEERModel; const FBType: string;
  DatatypeSubst: TStringList; var DatatypeParams: string): TEERDatatype;
var n, s: string;
begin
  n:=FBType;
  DatatypeParams:='';
  if(Pos('(', n)>0)then
  begin
    DatatypeParams:=Copy(n, Pos('(', n), Length(n));
    n:=Trim(Copy(n, 1, Pos('(', n)-1));
  end;

  if(n='NUMERIC')or(n='DECIMAL')then
    s:='DECIMAL'
  else if(n='INT128')then
  begin
    s:='DECIMAL';
    DatatypeParams:='(38,0)';
  end
  else if(n='DOUBLE PRECISION')or(Copy(n, 1, 8)='DECFLOAT')then
  begin
    s:='DOUBLE';
    DatatypeParams:='';
  end
  else if(Copy(n, 1, 9)='TIMESTAMP')then
    s:='DATETIME'
  else if(Copy(n, 1, 4)='TIME')then
    s:='TIME'
  else if(n='BINARY')then
    s:='CHAR'
  else if(n='VARBINARY')then
    s:='VARCHAR'
  else if(n='BLOB SUB_TYPE TEXT')then
    s:='TEXT'
  else if(n='BLOB SUB_TYPE BINARY')then
    s:='BLOB'
  else if(n='BOOLEAN')then
    s:='BOOL'
  else
    s:=n;

  //The user's substitution list goes first
  if(Assigned(DatatypeSubst))then
    if(DatatypeSubst.Values[n]<>'')then
      s:=DatatypeSubst.Values[n];

  Result:=TEERDatatype(EERModel.GetDataTypeByName(s));
  if(Result=nil)then
  begin
    Result:=TEERDatatype(EERModel.GetDataType(EERModel.DefaultDataType));
    DatatypeParams:='';
  end;
end;

procedure FirebirdReverseEngineer(EERModel: TEERModel; theTables: TStringList;
  XCount: integer; BuildRelations, BuildRelUsingPrimKey: Boolean;
  DatatypeSubst: TStringList; StatusLbl: TLabel;
  CreateStdInserts: Boolean; limitStdIns: integer);
var Q: SQLDB.TSQLQuery;
  DbTables: TList;
  AllTables, PKCols: TStringList;
  Cols: TFBColInfos;
  theTable, parentTbl: TEERTable;
  theColumn: TEERColumn;
  theIndex: TEERIndex;
  theDatatype: TEERDatatype;
  theRel: TEERRel;
  i, j, EngineVer: integer;
  s, DatatypeParams, DefVal, prevIndex, fkName, constrType: string;
  AllFKColsArePK: Boolean;

  procedure Status(const s: string);
  begin
    if(StatusLbl<>nil)then
    begin
      StatusLbl.Caption:=s;
      StatusLbl.Refresh;
      Application.ProcessMessages;
    end;
  end;

begin
  Status(DMMain.GetTranslatedMessage('Fetching Tables', 147));

  RevEngSkippedTables:=0;

  Q:=NewQuery;
  DbTables:=TList.Create;
  AllTables:=TStringList.Create;
  PKCols:=TStringList.Create;
  try
    EngineVer:=EngineVersion(Q);

    //Get Tables
    FirebirdGetTables(AllTables);
    for i:=0 to AllTables.Count-1 do
      //get only selected tables
      if(theTables.IndexOf(AllTables[i])<>-1)then
      begin
        //Skip tables that are already in the model
        if(EERModel.GetEERObjectByName(EERTable, AllTables[i])<>nil)then
          inc(RevEngSkippedTables)
        else
        begin
          theTable:=EERModel.NewTable(EERModel.EERModel_Width-250, 0, False);
          theTable.ObjName:=AllTables[i];

          DbTables.Add(theTable);
        end;
      end;

    //Get the columns and indices
    for i:=0 to DbTables.Count-1 do
    begin
      theTable:=TEERTable(DbTables[i]);

      Status(DMMain.GetTranslatedMessage('Fetching Table Columns/Indices (%s)', 148,
        theTable.ObjName));

      s:=QueryStr(Q, 'SELECT RDB$DESCRIPTION FROM RDB$RELATIONS '+
        'WHERE RDB$RELATION_NAME='+QuotedStr(theTable.ObjName));
      if(Trim(s)<>'')then
        theTable.Comments:=Trim(s);

      //Columns
      LoadPrimaryKey(Q, theTable.ObjName, s, PKCols);
      LoadColumns(Q, theTable.ObjName, EngineVer, Cols);
      for j:=0 to High(Cols) do
      begin
        theColumn:=TEERColumn.Create(theTable);
        theTable.Columns.Add(theColumn);

        theColumn.ColName:=Cols[j].Name;
        theColumn.Obj_id:=DMMain.GetNextGlobalID;
        theColumn.Pos:=theTable.Columns.Count;
        theColumn.PrimaryKey:=(PKCols.IndexOf(Cols[j].Name)<>-1);
        theColumn.NotNull:=(Cols[j].NotNull)or(theColumn.PrimaryKey);
        theColumn.AutoInc:=Cols[j].Identity;
        theColumn.IsForeignKey:=False;
        theColumn.Comments:=Cols[j].Comment;

        //Default value as written in the DDL, strip one pair of enclosing
        //quotes like MySQL's SHOW FIELDS does
        DefVal:=Cols[j].Dflt;
        if(Length(DefVal)>=2)and(DefVal[1]='''')and(DefVal[Length(DefVal)]='''')then
          DefVal:=Copy(DefVal, 2, Length(DefVal)-2);
        if(CompareText(DefVal, 'NULL')<>0)then
          theColumn.DefaultValue:=DefVal;

        //Datatype
        theDatatype:=ModelDatatype(EERModel, Cols[j].Typ, DatatypeSubst, DatatypeParams);
        theColumn.idDatatype:=theDatatype.id;
        theColumn.DatatypeParams:=DatatypeParams;
      end;

      //Build the PRIMARY index from the PK columns
      theTable.CheckPrimaryIndex;

      //Indices. The indices of the primary key and of the foreign keys
      //belong to their constraints; a UNIQUE constraint is a unique index
      prevIndex:='';
      theIndex:=nil;
      Q.SQL.Text:=Format(IndicesSQL, [QuotedStr(theTable.ObjName)]);
      Q.Open;
      while(Not(Q.EOF))do
      begin
        constrType:=Q.FieldByName('CONSTRTYPE').AsString;
        if(constrType<>'PRIMARY KEY')and(constrType<>'FOREIGN KEY')then
        begin
          if(prevIndex<>Q.FieldByName('IDXNAME').AsString)then
          begin
            theIndex:=TEERIndex.Create(theTable);
            theIndex.Obj_id:=DMMain.GetNextGlobalID;
            theIndex.IndexName:=Q.FieldByName('IDXNAME').AsString;
            if(Q.FieldByName('IDXUNIQUE').AsInteger=1)then
              theIndex.IndexKind:=ik_UNIQUE_INDEX
            else
              theIndex.IndexKind:=ik_INDEX;
            theTable.Indices.Add(theIndex);
            theIndex.Pos:=theTable.Indices.Count-1;
          end;

          theColumn:=TEERColumn(theTable.GetColumnByName(Q.FieldByName('COLNAME').AsString));
          if(theColumn<>nil)then
            theIndex.Columns.Add(IntToStr(theColumn.Obj_id));

          prevIndex:=Q.FieldByName('IDXNAME').AsString;
        end;
        Q.Next;
      end;
      Q.Close;

      theTable.RefreshObj;
    end;

    //Order table positions (only the new tables)
    DMDBEER.EERReverseEngineerPlaceTables(EERModel, DbTables, XCount);

    Status(DMMain.GetTranslatedMessage('Building Relations...', 149));
    if(BuildRelations)then
    begin
      //1. Native relations from the FOREIGN KEY constraints
      for i:=0 to DbTables.Count-1 do
      begin
        theTable:=TEERTable(DbTables[i]);

        Q.SQL.Text:=Format(ForeignKeysSQL,
          ['rc.RDB$RELATION_NAME='+QuotedStr(theTable.ObjName)]);
        Q.Open;
        while(Not(Q.EOF))do
        begin
          fkName:=Q.FieldByName('FKNAME').AsString;
          parentTbl:=TEERTable(EERModel.GetEERObjectByName(EERTable,
            Q.FieldByName('REFTABLE').AsString));

          //Referenced table not in the model: skip this FK. A self reference
          //(KUNDE.WERBER_ID -> KUNDE.ID) is an ordinary relation for the
          //model; without it the next sync would drop the constraint
          if(parentTbl=nil)then
          begin
            while(Not(Q.EOF))and(Q.FieldByName('FKNAME').AsString=fkName)do
              Q.Next;
            continue;
          end;

          theRel:=TEERRel(EERModel.NewRelation(rk_1nNonId, parentTbl, theTable, False));
          theRel.ObjName:=fkName;
          theRel.FKFields.Clear;
          theRel.FKFieldsComments.Clear;
          theRel.CreateRefDef:=True;
          theRel.RefDef.Values['OnDelete']:=
            FirebirdRefActionCode(Q.FieldByName('DELRULE').AsString);
          theRel.RefDef.Values['OnUpdate']:=
            FirebirdRefActionCode(Q.FieldByName('UPDRULE').AsString);

          //Build PK - FK Mapping
          AllFKColsArePK:=True;
          while(Not(Q.EOF))and(Q.FieldByName('FKNAME').AsString=fkName)do
          begin
            theRel.FKFields.Add(Q.FieldByName('REFCOLNAME').AsString+'='+
              Q.FieldByName('COLNAME').AsString);
            theRel.FKFieldsComments.Add('');

            theColumn:=TEERColumn(theTable.GetColumnByName(Q.FieldByName('COLNAME').AsString));
            if(theColumn<>nil)then
            begin
              theColumn.IsForeignKey:=True;
              if(Not(theColumn.PrimaryKey))then
                AllFKColsArePK:=False;
            end
            else
              AllFKColsArePK:=False;

            Q.Next;
          end;

          //FK columns that are all part of the child's PK: identifying relation.
          //The model has no identifying relation from a table to itself
          if(AllFKColsArePK)and(parentTbl<>theTable)then
            theRel.RelKind:=rk_1n;

          theRel.SrcTbl.RefreshRelations;
          theRel.DestTbl.RefreshRelations;
        end;
        Q.Close;
      end;

      //2. Guess the remaining ones by name / primary key like the other
      //   drivers do, without duplicating the native ones
      DMDBEER.EERReverseEngineerMakeRelations(EERModel, DbTables, BuildRelUsingPrimKey, True);
    end;

    SQLDB.TSQLTransaction(Q.Transaction).CommitRetaining;

    Status(DMMain.GetTranslatedMessage('Creating Standard Inserts...', 150));
    if(CreateStdInserts)then
      DMDBEER.EERReverseEngineerCreateStdInserts(EERModel, DbTables, limitStdIns);

    if(StatusLbl<>nil)then
    begin
      StatusLbl.Caption:=DMMain.GetTranslatedMessage('Finished.', 151);
      if(RevEngSkippedTables>0)then
        StatusLbl.Caption:=StatusLbl.Caption+' '+IntToStr(RevEngSkippedTables)+' existing table(s) skipped.';
    end;
  finally
    PKCols.Free;
    AllTables.Free;
    DbTables.Free;
    Q.Free;
  end;
end;

// -----------------------------------------------------------------------------
// Synchronisation

procedure FirebirdSyncTables(EERModel: TEERModel; ModelTables: TList;
  DbTables: TStringList; Log: TStrings; SyncErrors: TStrings;
  KeepExTbls, StdInsertsOnCreate: Boolean; var C: TSQLiteSyncCounters);
const
  TmpTbl = 'DBD4_SYNC_TMP';
var
  Q: SQLDB.TSQLQuery;
  Trans: SQLDB.TSQLTransaction;
  EngineVer: integer;
  theTable: TEERTable;
  DropTables: TStringList;
  DoDropTables: Boolean;
  i, j, position, ErrCount: integer;

  procedure LogError(const what, msg: string);
  begin
    SyncErrors.Add(what+#13#10+msg);
    Log.Add('  ERROR: '+msg);
  end;

  //Execute and commit one statement, an exception on failure
  procedure Exec(const stmt: string);
  begin
    try
      Q.SQL.Text:=stmt;
      Q.ExecSQL;
      Trans.CommitRetaining;
    except
      if(Q.Active)then
        Q.Close;
      Trans.RollbackRetaining;
      raise;
    end;
  end;

  //Execute and commit one statement; a failure is logged, the sync goes on
  function TryExec(const stmt: string): Boolean;
  begin
    Result:=True;
    try
      Exec(stmt);
    except
      on x: Exception do
      begin
        Result:=False;
        LogError(stmt, x.Message);
      end;
    end;
  end;

  function IndexOfText(theList: TStrings; const s: string): integer;
  var k: integer;
  begin
    IndexOfText:=-1;
    for k:=0 to theList.Count-1 do
      if(CompareText(theList[k], s)=0)then
      begin
        IndexOfText:=k;
        Exit;
      end;
  end;

  //The name of a table as it is written in the database, '' if it is not there
  function DbTableName(const tblname: string): string;
  var k: integer;
  begin
    k:=IndexOfText(DbTables, tblname);
    if(k=-1)then
      DbTableName:=''
    else
      DbTableName:=DbTables[k];
  end;

  function GetModelTable(const tblname: string): TEERTable;
  var k: integer;
  begin
    GetModelTable:=nil;
    for k:=0 to ModelTables.Count-1 do
      if(CompareText(TEERTable(ModelTables[k]).ObjName, tblname)=0)then
        GetModelTable:=TEERTable(ModelTables[k]);
  end;

  //The definition of a column for CREATE TABLE / ALTER TABLE ADD
  function ColumnDef(theColumn: TEERColumn): string;
  begin
    Result:=NewId(theColumn.ColName)+' '+FirebirdColumnType(EERModel, theColumn);

    if(theColumn.AutoInc)then
      Result:=Result+' GENERATED BY DEFAULT AS IDENTITY'
    else if(theColumn.DefaultValue<>'')then
    begin
      if(DMEER.AddQuotesToDefVals)then
        Result:=Result+' DEFAULT '+QuotedStr(theColumn.DefaultValue)
      else
        Result:=Result+' DEFAULT '+theColumn.DefaultValue;
    end;

    //The columns of a primary key have to be NOT NULL
    if(theColumn.NotNull)or(theColumn.PrimaryKey)then
      Result:=Result+' NOT NULL';
  end;

  function ColumnDefs(aTable: TEERTable): string;
  var k: integer;
  begin
    Result:='';
    for k:=0 to aTable.Columns.Count-1 do
    begin
      if(k>0)then
        Result:=Result+', ';
      Result:=Result+ColumnDef(TEERColumn(aTable.Columns[k]));
    end;

    if(Result='')then
      raise Exception.Create('Table '+aTable.ObjName+' has no columns.');
  end;

  //The names of the primary key columns of the model table, in key order
  procedure ModelPrimaryKey(aTable: TEERTable; Cols: TStrings);
  var k, m: integer;
    theColumn: TEERColumn;
  begin
    Cols.Clear;
    for k:=0 to aTable.Indices.Count-1 do
      if(TEERIndex(aTable.Indices[k]).IndexKind=ik_PRIMARY)then
        for m:=0 to TEERIndex(aTable.Indices[k]).Columns.Count-1 do
        begin
          theColumn:=TEERColumn(aTable.GetColumnByID(
            StrToIntDef(TEERIndex(aTable.Indices[k]).Columns[m], -1)));
          if(theColumn<>nil)then
            Cols.Add(theColumn.ColName);
        end;

    if(Cols.Count=0)then
      for k:=0 to aTable.Columns.Count-1 do
        if(TEERColumn(aTable.Columns[k]).PrimaryKey)then
          Cols.Add(TEERColumn(aTable.Columns[k]).ColName);
  end;

  //'a, b' for a statement that creates an object
  function NewIdList(Cols: TStrings): string;
  var k: integer;
  begin
    Result:='';
    for k:=0 to Cols.Count-1 do
    begin
      if(k>0)then
        Result:=Result+', ';
      Result:=Result+NewId(Cols[k]);
    end;
  end;

  //The indices of the model table that Firebird has to create: Names[k] with
  //its definition Defs[k] ("U|COL,COL" or "I|COL,COL") and statement Stmts[k].
  //The index of a foreign key belongs to the constraint in Firebird
  procedure ModelIndices(aTable: TEERTable; const tbl: string;
    Names, Defs, Stmts: TStrings);
  var k, m: integer;
    theIndex: TEERIndex;
    theColumn: TEERColumn;
    Cols: TStringList;
    def, stmt: string;
  begin
    Names.Clear;
    Defs.Clear;
    Stmts.Clear;
    Cols:=TStringList.Create;
    try
      for k:=0 to aTable.Indices.Count-1 do
      begin
        theIndex:=TEERIndex(aTable.Indices[k]);
        if(theIndex.IndexKind=ik_PRIMARY)or(theIndex.FKRefDef_Obj_id>-1)then
          continue;

        Cols.Clear;
        for m:=0 to theIndex.Columns.Count-1 do
        begin
          theColumn:=TEERColumn(aTable.GetColumnByID(StrToIntDef(theIndex.Columns[m], -1)));
          if(theColumn<>nil)then
            Cols.Add(theColumn.ColName);
        end;
        if(Cols.Count=0)then
          continue;

        if(theIndex.IndexKind=ik_UNIQUE_INDEX)then
        begin
          def:='U|';
          stmt:='CREATE UNIQUE INDEX ';
        end
        else
        begin
          def:='I|';
          stmt:='CREATE INDEX ';
        end;

        Names.Add(theIndex.IndexName);
        Defs.Add(def+UpperCase(Cols.CommaText));
        Stmts.Add(stmt+NewId(theIndex.IndexName)+' ON '+tbl+' ('+NewIdList(Cols)+')');
      end;
    finally
      Cols.Free;
    end;
  end;

  //The indices of a table without those of the primary and foreign keys.
  //Constraints[k]: the name of the UNIQUE constraint the index belongs to.
  //ColMap (old=new) translates the names of columns that are being renamed
  procedure LoadIndices(const tbl: string; Names, Defs, Constraints: TStrings;
    ColMap: TStrings);
  var prev, def, col, constrType: string;
  begin
    Names.Clear;
    Defs.Clear;
    Constraints.Clear;
    prev:='';
    def:='';
    Q.SQL.Text:=Format(IndicesSQL, [QuotedStr(tbl)]);
    Q.Open;
    try
      while(Not(Q.EOF))do
      begin
        constrType:=Q.FieldByName('CONSTRTYPE').AsString;
        if(constrType<>'PRIMARY KEY')and(constrType<>'FOREIGN KEY')then
        begin
          if(prev<>Q.FieldByName('IDXNAME').AsString)then
          begin
            if(prev<>'')then
              Defs.Add(def);
            prev:=Q.FieldByName('IDXNAME').AsString;
            Names.Add(prev);
            Constraints.Add(Q.FieldByName('CONSTRNAME').AsString);
            if(Q.FieldByName('IDXUNIQUE').AsInteger=1)then
              def:='U|'
            else
              def:='I|';
            //The model has ascending indices only
            if(Q.FieldByName('IDXDESC').AsInteger=1)then
              def:='DESC '+def;
          end
          else
            def:=def+',';

          col:=Q.FieldByName('COLNAME').AsString;
          if(ColMap<>nil)then
            if(ColMap.IndexOfName(col)>=0)then
              col:=ColMap.Values[col];
          def:=def+UpperCase(col);
        end;
        Q.Next;
      end;
      if(prev<>'')then
        Defs.Add(def);
    finally
      Q.Close;
    end;
  end;

  function RuleOfCode(const code: string): string;
  begin
    case StrToIntDef(code, 0) of
      1: Result:='CASCADE';
      2: Result:='SET NULL';
      4: Result:='SET DEFAULT';
    else
      //RESTRICT and NO ACTION are the same in Firebird
      Result:='RESTRICT';
    end;
  end;

  function NormRule(const rule: string): string;
  begin
    if(rule='NO ACTION')or(rule='')then
      Result:='RESTRICT'
    else
      Result:=rule;
  end;

  //The foreign keys of the model table: the signature Sigs[k]
  //("REFTABLE|UPDRULE|DELRULE|COL>REFCOL,") and the constraint clause
  //Clauses[k] for ALTER TABLE ADD
  procedure ModelForeignKeys(aTable: TEERTable; Sigs, Clauses: TStrings);
  var k, m: integer;
    theRel: TEERRel;
    sig, cols, refcols, clause, upd, del: string;
  begin
    Sigs.Clear;
    Clauses.Clear;
    for k:=0 to aTable.RelEnd.Count-1 do
    begin
      theRel:=TEERRel(aTable.RelEnd[k]);
      if(Not(theRel.CreateRefDef))or(theRel.FKFields.Count=0)then
        continue;
      //The referenced table is not synchronised (a linked table)
      if(ModelTables.IndexOf(theRel.SrcTbl)=-1)then
        continue;

      upd:=RuleOfCode(theRel.RefDef.Values['OnUpdate']);
      del:=RuleOfCode(theRel.RefDef.Values['OnDelete']);

      sig:=UpperCase(TEERTable(theRel.SrcTbl).ObjName)+'|'+upd+'|'+del+'|';
      cols:='';
      refcols:='';
      for m:=0 to theRel.FKFields.Count-1 do
      begin
        sig:=sig+UpperCase(theRel.FKFields.ValueFromIndex[m])+'>'+
          UpperCase(theRel.FKFields.Names[m])+',';
        if(m>0)then
        begin
          cols:=cols+', ';
          refcols:=refcols+', ';
        end;
        cols:=cols+NewId(theRel.FKFields.ValueFromIndex[m]);
        refcols:=refcols+NewId(theRel.FKFields.Names[m]);
      end;

      clause:='';
      if(Not(DMEER.DoNotUseRelNameInRefDef))and(Trim(theRel.ObjName)<>'')then
        clause:='CONSTRAINT '+NewId(theRel.ObjName)+' ';
      clause:=clause+'FOREIGN KEY ('+cols+') REFERENCES '+
        NewId(TEERTable(theRel.SrcTbl).ObjName)+' ('+refcols+')';
      //RESTRICT is the default and has no keyword in Firebird
      if(del<>'RESTRICT')then
        clause:=clause+' ON DELETE '+del;
      if(upd<>'RESTRICT')then
        clause:=clause+' ON UPDATE '+upd;

      Sigs.Add(sig);
      Clauses.Add(clause);
    end;
  end;

  //old=new for the columns of a model table that are being renamed
  procedure RenameMap(aTable: TEERTable; ColMap: TStrings);
  var k: integer;
    theColumn: TEERColumn;
  begin
    ColMap.Clear;
    if(aTable=nil)then
      Exit;
    for k:=0 to aTable.Columns.Count-1 do
    begin
      theColumn:=TEERColumn(aTable.Columns[k]);
      if(theColumn.PrevColName<>'')and
        (CompareText(theColumn.PrevColName, theColumn.ColName)<>0)then
        ColMap.Add(UpperCase(theColumn.PrevColName)+'='+UpperCase(theColumn.ColName));
    end;
  end;

  //The foreign keys the query returns: the constraint Names[k], its table
  //Tables[k] and its signature Sigs[k] as ModelForeignKeys builds it, with
  //the names of the columns that are being renamed translated
  procedure LoadForeignKeys(const where: string; Names, Tables, Sigs: TStrings);
  var prev, sig, col, refcol: string;
    ColMap, RefColMap: TStringList;
  begin
    Names.Clear;
    Tables.Clear;
    Sigs.Clear;
    prev:='';
    sig:='';
    ColMap:=TStringList.Create;
    RefColMap:=TStringList.Create;
    try
      Q.SQL.Text:=Format(ForeignKeysSQL, [where]);
      Q.Open;
      try
        while(Not(Q.EOF))do
        begin
          if(prev<>Q.FieldByName('TBLNAME').AsString+'.'+Q.FieldByName('FKNAME').AsString)then
          begin
            if(prev<>'')then
              Sigs.Add(sig);
            prev:=Q.FieldByName('TBLNAME').AsString+'.'+Q.FieldByName('FKNAME').AsString;
            Names.Add(Q.FieldByName('FKNAME').AsString);
            Tables.Add(Q.FieldByName('TBLNAME').AsString);
            sig:=UpperCase(Q.FieldByName('REFTABLE').AsString)+'|'+
              NormRule(Q.FieldByName('UPDRULE').AsString)+'|'+
              NormRule(Q.FieldByName('DELRULE').AsString)+'|';

            RenameMap(GetModelTable(Q.FieldByName('TBLNAME').AsString), ColMap);
            RenameMap(GetModelTable(Q.FieldByName('REFTABLE').AsString), RefColMap);
          end;

          col:=UpperCase(Q.FieldByName('COLNAME').AsString);
          if(ColMap.IndexOfName(col)>=0)then
            col:=ColMap.Values[col];
          refcol:=UpperCase(Q.FieldByName('REFCOLNAME').AsString);
          if(RefColMap.IndexOfName(refcol)>=0)then
            refcol:=RefColMap.Values[refcol];
          sig:=sig+col+'>'+refcol+',';

          Q.Next;
        end;
        if(prev<>'')then
          Sigs.Add(sig);
      finally
        Q.Close;
      end;
    finally
      RefColMap.Free;
      ColMap.Free;
    end;
  end;

  //Drop the foreign keys of other tables that reference the table.
  //WithSelfRefs: and those of the table itself; they go with the table when
  //it is dropped, but they block the drop of its primary key
  procedure DropReferencingForeignKeys(const tbl: string; WithSelfRefs: Boolean = False);
  var Names, Tables, Sigs: TStringList;
    where: string;
    k: integer;
  begin
    Names:=TStringList.Create;
    Tables:=TStringList.Create;
    Sigs:=TStringList.Create;
    try
      where:='pk.RDB$RELATION_NAME='+QuotedStr(tbl);
      if(Not(WithSelfRefs))then
        where:=where+' AND rc.RDB$RELATION_NAME<>'+QuotedStr(tbl);
      LoadForeignKeys(where, Names, Tables, Sigs);
      for k:=0 to Names.Count-1 do
      begin
        Log.Add('Drop foreign key '+Names[k]+' on table '+Tables[k]);
        Exec('ALTER TABLE '+QId(Tables[k])+' DROP CONSTRAINT '+QId(Names[k]));
      end;
    finally
      Sigs.Free;
      Tables.Free;
      Names.Free;
    end;
  end;

  procedure DropTmpTable;
  begin
    if(QueryStr(Q, 'SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME='+
      QuotedStr(TmpTbl))<>'0')then
      Exec('DROP TABLE '+QId(TmpTbl));
  end;

  //Create the table with its primary key and indices; the foreign keys are
  //added when all tables exist
  procedure CreateTable(aTable: TEERTable);
  var PKCols, IdxNames, IdxDefs, IdxStmts: TStringList;
    stmt: string;
    k: integer;
  begin
    PKCols:=TStringList.Create;
    IdxNames:=TStringList.Create;
    IdxDefs:=TStringList.Create;
    IdxStmts:=TStringList.Create;
    try
      stmt:='CREATE TABLE '+NewId(aTable.ObjName)+' ('+ColumnDefs(aTable);
      ModelPrimaryKey(aTable, PKCols);
      if(PKCols.Count>0)then
        stmt:=stmt+', PRIMARY KEY ('+NewIdList(PKCols)+')';
      Exec(stmt+')');

      ModelIndices(aTable, NewId(aTable.ObjName), IdxNames, IdxDefs, IdxStmts);
      for k:=0 to IdxStmts.Count-1 do
        TryExec(IdxStmts[k]);
    finally
      IdxStmts.Free;
      IdxDefs.Free;
      IdxNames.Free;
      PKCols.Free;
    end;
  end;

  //Firebird has no RENAME TABLE: create the table under its new name, copy
  //the rows and drop the old table
  procedure RenameTable(aTable: TEERTable; const OldName: string);
  var OldCols: TFBColInfos;
    theColumn: TEERColumn;
    colList, selList, src, maxval: string;
    k, m: integer;
  begin
    CreateTable(aTable);
    try
      LoadColumns(Q, OldName, EngineVer, OldCols);

      colList:='';
      selList:='';
      for k:=0 to aTable.Columns.Count-1 do
      begin
        theColumn:=TEERColumn(aTable.Columns[k]);
        src:='';
        for m:=0 to High(OldCols) do
          if(CompareText(OldCols[m].Name, theColumn.ColName)=0)then
            src:=OldCols[m].Name;
        if(src='')and(theColumn.PrevColName<>'')then
          for m:=0 to High(OldCols) do
            if(CompareText(OldCols[m].Name, theColumn.PrevColName)=0)then
              src:=OldCols[m].Name;

        if(src<>'')then
        begin
          if(colList<>'')then
          begin
            colList:=colList+', ';
            selList:=selList+', ';
          end;
          colList:=colList+NewId(theColumn.ColName);
          selList:=selList+QId(src);
        end;
      end;

      if(colList<>'')then
        Exec('INSERT INTO '+NewId(aTable.ObjName)+' ('+colList+') SELECT '+selList+
          ' FROM '+QId(OldName));

      //The copied values did not move the generator of an identity column
      for k:=0 to aTable.Columns.Count-1 do
        if(TEERColumn(aTable.Columns[k]).AutoInc)then
        begin
          maxval:=QueryStr(Q, 'SELECT MAX('+NewId(TEERColumn(aTable.Columns[k]).ColName)+
            ') FROM '+NewId(aTable.ObjName));
          if(maxval<>'')then
            Exec('ALTER TABLE '+NewId(aTable.ObjName)+' ALTER COLUMN '+
              NewId(TEERColumn(aTable.Columns[k]).ColName)+' RESTART WITH '+
              IntToStr(StrToInt64Def(maxval, 0)+1));
        end;

      //The foreign keys that referenced the old table are added to the new
      //one when the foreign keys are compared
      DropReferencingForeignKeys(OldName);
      Exec('DROP TABLE '+QId(OldName));
    except
      //Leave the old table as the only one
      try
        Exec('DROP TABLE '+NewId(aTable.ObjName));
      except
      end;
      raise;
    end;
  end;

  //Drop the foreign keys of a table that are not in the model (any more)
  procedure DropObsoleteForeignKeys(aTable: TEERTable);
  var X: string;
    Names, Tables, Sigs, ModelSigs, ModelClauses: TStringList;
    k: integer;
  begin
    X:=DbTableName(aTable.ObjName);

    Names:=TStringList.Create;
    Tables:=TStringList.Create;
    Sigs:=TStringList.Create;
    ModelSigs:=TStringList.Create;
    ModelClauses:=TStringList.Create;
    try
      ModelForeignKeys(aTable, ModelSigs, ModelClauses);
      LoadForeignKeys('rc.RDB$RELATION_NAME='+QuotedStr(X), Names, Tables, Sigs);

      for k:=0 to Names.Count-1 do
        if(ModelSigs.IndexOf(Sigs[k])=-1)then
        begin
          Log.Add('Drop foreign key '+Names[k]+' on table '+X);
          TryExec('ALTER TABLE '+QId(X)+' DROP CONSTRAINT '+QId(Names[k]));
        end;
    finally
      ModelClauses.Free;
      ModelSigs.Free;
      Sigs.Free;
      Tables.Free;
      Names.Free;
    end;
  end;

  //Add the foreign keys of the model the table does not have
  procedure AddMissingForeignKeys(aTable: TEERTable);
  var X: string;
    Names, Tables, Sigs, ModelSigs, ModelClauses: TStringList;
    k: integer;
  begin
    X:=DbTableName(aTable.ObjName);

    Names:=TStringList.Create;
    Tables:=TStringList.Create;
    Sigs:=TStringList.Create;
    ModelSigs:=TStringList.Create;
    ModelClauses:=TStringList.Create;
    try
      ModelForeignKeys(aTable, ModelSigs, ModelClauses);
      LoadForeignKeys('rc.RDB$RELATION_NAME='+QuotedStr(X), Names, Tables, Sigs);

      for k:=0 to ModelSigs.Count-1 do
        if(Sigs.IndexOf(ModelSigs[k])=-1)then
        begin
          Log.Add('Add foreign key to table '+X+': '+ModelClauses[k]);
          TryExec('ALTER TABLE '+QId(X)+' ADD '+ModelClauses[k]);
        end;
    finally
      ModelClauses.Free;
      ModelSigs.Free;
      Sigs.Free;
      Tables.Free;
      Names.Free;
    end;
  end;

  procedure SyncExistingTable(aTable: TEERTable);
  var X, s, PKName: string;
    NewCols, OldCols: TFBColInfos;
    Src: array of integer;
    Used: array of Boolean;
    theColumn: TEERColumn;
    ColMap, PKCols, SortedPKCols, OldPKCols, IdxNames, IdxDefs, IdxStmts,
    OldIdxNames, OldIdxDefs, OldIdxConstraints: TStringList;
    IdxCreate: array of Boolean;
    k, m, p: integer;
    PKChanged, ColChanged, ok: Boolean;
  begin
    //The name as it is written in the database
    X:=DbTableName(aTable.ObjName);

    ColMap:=TStringList.Create;
    PKCols:=TStringList.Create;
    SortedPKCols:=TStringList.Create;
    OldPKCols:=TStringList.Create;
    IdxNames:=TStringList.Create;
    IdxDefs:=TStringList.Create;
    IdxStmts:=TStringList.Create;
    OldIdxNames:=TStringList.Create;
    OldIdxDefs:=TStringList.Create;
    OldIdxConstraints:=TStringList.Create;
    try
      //---------------------
      //The columns of the model as Firebird sees them
      DropTmpTable;
      Exec('CREATE TABLE '+QId(TmpTbl)+' ('+ColumnDefs(aTable)+')');
      try
        LoadColumns(Q, TmpTbl, EngineVer, NewCols);
      finally
        DropTmpTable;
      end;
      //NewCols[k] is the column aTable.Columns[k]
      if(Length(NewCols)<>aTable.Columns.Count)then
        raise Exception.Create('The columns of table '+aTable.ObjName+' could not be read back.');
      LoadColumns(Q, X, EngineVer, OldCols);
      inc(C.ColumnComp, Length(OldCols));

      //---------------------
      //Find the database column of every model column
      SetLength(Src, Length(NewCols));
      SetLength(Used, Length(OldCols));
      for k:=0 to High(Used) do
        Used[k]:=False;

      for k:=0 to High(NewCols) do
      begin
        Src[k]:=-1;
        for m:=0 to High(OldCols) do
          if(CompareText(NewCols[k].Name, OldCols[m].Name)=0)then
            Src[k]:=m;

        //Renamed column
        if(Src[k]=-1)then
        begin
          theColumn:=TEERColumn(aTable.Columns[k]);
          if(theColumn<>nil)then
            if(theColumn.PrevColName<>'')then
              for m:=0 to High(OldCols) do
                if(CompareText(theColumn.PrevColName, OldCols[m].Name)=0)and
                  (Not(Used[m]))then
                begin
                  Src[k]:=m;
                  ColMap.Add(OldCols[m].Name+'='+UpperCase(NewCols[k].Name));
                end;
        end;

        if(Src[k]>=0)then
          Used[Src[k]]:=True;
      end;

      //---------------------
      //Primary key
      ModelPrimaryKey(aTable, PKCols);
      LoadPrimaryKey(Q, X, PKName, OldPKCols);
      for k:=0 to OldPKCols.Count-1 do
        if(ColMap.IndexOfName(OldPKCols[k])>=0)then
          OldPKCols[k]:=ColMap.Values[OldPKCols[k]];
      //The model keeps the columns of the primary key in the order of the
      //table (TEERTable.CheckPrimaryIndex), so another order in the database
      //is no difference
      OldPKCols.Sort;
      SortedPKCols.Assign(PKCols);
      SortedPKCols.Sort;
      PKChanged:=(CompareText(SortedPKCols.CommaText, OldPKCols.CommaText)<>0);

      //---------------------
      //Indices: drop those that are not in the model or differ, before the
      //columns they use are changed
      ModelIndices(aTable, QId(X), IdxNames, IdxDefs, IdxStmts);
      LoadIndices(X, OldIdxNames, OldIdxDefs, OldIdxConstraints, ColMap);
      SetLength(IdxCreate, IdxNames.Count);
      for k:=0 to IdxNames.Count-1 do
        IdxCreate[k]:=(IndexOfText(OldIdxNames, IdxNames[k])=-1);

      for k:=0 to OldIdxNames.Count-1 do
      begin
        p:=IndexOfText(IdxNames, OldIdxNames[k]);
        if(p>=0)then
          if(IdxDefs[p]=OldIdxDefs[k])then
            continue;

        if(p=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Drop obsolete index %s on table %s', 161,
            OldIdxNames[k], X));
          inc(C.IndexDrop);
        end
        else
        begin
          Log.Add(DMMain.GetTranslatedMessage('Update index %s on table %s', 162,
            OldIdxNames[k], X));
          inc(C.IndexUpdate);
        end;

        if(OldIdxConstraints[k]<>'')then
          ok:=TryExec('ALTER TABLE '+QId(X)+' DROP CONSTRAINT '+QId(OldIdxConstraints[k]))
        else
          ok:=TryExec('DROP INDEX '+QId(OldIdxNames[k]));
        if(p>=0)then
          IdxCreate[p]:=ok;
      end;

      if(PKChanged)then
      begin
        Log.Add(DMMain.GetTranslatedMessage('Change primary key on table %s', 160, X));
        inc(C.PKChanged);

        if(PKName<>'')then
        begin
          //The foreign keys that reference the key are added again when the
          //foreign keys are compared
          DropReferencingForeignKeys(X, True);
          Exec('ALTER TABLE '+QId(X)+' DROP CONSTRAINT '+QId(PKName));
        end;
      end;

      //---------------------
      //Renamed columns
      for k:=0 to High(NewCols) do
        if(Src[k]>=0)then
          if(CompareText(NewCols[k].Name, OldCols[Src[k]].Name)<>0)then
          begin
            Log.Add(DMMain.GetTranslatedMessage('Modifying column %s from table %s', 158,
              OldCols[Src[k]].Name, X));
            inc(C.ColumnMod);

            theColumn:=TEERColumn(aTable.Columns[k]);
            if(TryExec('ALTER TABLE '+QId(X)+' ALTER COLUMN '+QId(OldCols[Src[k]].Name)+
              ' TO '+NewId(theColumn.ColName)))then
              OldCols[Src[k]].Name:=NewCols[k].Name
            else
              //Leave the column alone
              Src[k]:=-2;
          end;

      //---------------------
      //Columns that are not in the model
      for m:=0 to High(OldCols) do
        if(Not(Used[m]))then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Dropping column %s from table %s', 157,
            OldCols[m].Name, X));
          inc(C.ColumnDel);
          TryExec('ALTER TABLE '+QId(X)+' DROP '+QId(OldCols[m].Name));
        end;

      //---------------------
      //New and changed columns
      for k:=0 to High(NewCols) do
      begin
        theColumn:=TEERColumn(aTable.Columns[k]);

        if(Src[k]=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Add Column %s to table %s', 159,
            NewCols[k].Name, X));
          inc(C.ColumnAdd);
          TryExec('ALTER TABLE '+QId(X)+' ADD '+ColumnDef(theColumn));
        end
        else if(Src[k]>=0)then
        begin
          m:=Src[k];
          s:='ALTER TABLE '+QId(X)+' ALTER COLUMN '+QId(OldCols[m].Name)+' ';
          ColChanged:=False;

          if(NewCols[k].Typ<>OldCols[m].Typ)then
          begin
            ColChanged:=True;
            TryExec(s+'TYPE '+FirebirdColumnType(EERModel, theColumn));
          end;

          if(NewCols[k].Identity<>OldCols[m].Identity)then
          begin
            ColChanged:=True;
            if(NewCols[k].Identity)then
              LogError('Column '+X+'.'+OldCols[m].Name,
                'Firebird cannot turn an existing column into an identity (auto increment) column.')
            else
              TryExec(s+'DROP IDENTITY');
          end;

          if(NewCols[k].Dflt<>OldCols[m].Dflt)then
          begin
            ColChanged:=True;
            if(NewCols[k].Dflt='')then
              TryExec(s+'DROP DEFAULT')
            else
              TryExec(s+'SET DEFAULT '+NewCols[k].Dflt);
          end;

          if(NewCols[k].NotNull<>OldCols[m].NotNull)then
          begin
            ColChanged:=True;
            if(NewCols[k].NotNull)then
              TryExec(s+'SET NOT NULL')
            else
              TryExec(s+'DROP NOT NULL');
          end;

          if(ColChanged)then
          begin
            Log.Add(DMMain.GetTranslatedMessage('Modifying column %s from table %s', 158,
              OldCols[m].Name, X));
            inc(C.ColumnMod);
          end;
        end;
      end;

      //---------------------
      //Primary key and indices
      if(PKChanged)and(PKCols.Count>0)then
        TryExec('ALTER TABLE '+QId(X)+' ADD PRIMARY KEY ('+NewIdList(PKCols)+')');

      for k:=0 to IdxNames.Count-1 do
        if(IdxCreate[k])then
        begin
          if(IndexOfText(OldIdxNames, IdxNames[k])=-1)then
          begin
            Log.Add(DMMain.GetTranslatedMessage('Create index %s on table %s', 163,
              IdxNames[k], X));
            inc(C.IndexCreate);
          end;
          TryExec(IdxStmts[k]);
        end;

      //Clear previous colname for DB-Sync
      for k:=0 to aTable.Columns.Count-1 do
        TEERColumn(aTable.Columns[k]).PrevColName:='';
    finally
      OldIdxConstraints.Free;
      OldIdxDefs.Free;
      OldIdxNames.Free;
      IdxStmts.Free;
      IdxDefs.Free;
      IdxNames.Free;
      OldPKCols.Free;
      SortedPKCols.Free;
      PKCols.Free;
      ColMap.Free;
    end;
  end;

begin
  Q:=NewQuery;
  Trans:=SQLDB.TSQLTransaction(Q.Transaction);
  DropTables:=TStringList.Create;
  try
    EngineVer:=EngineVersion(Q);

    //---------------------------------------------------------------
    //Compare Tables

    Log.Add(DMMain.GetTranslatedMessage('Compare tables', 153));

    //---------------------
    //Create non existing
    for i:=0 to ModelTables.Count-1 do
    begin
      theTable:=TEERTable(ModelTables[i]);

      if(DbTableName(theTable.ObjName)<>'')then
        continue;

      //Check if table was renamed
      if(theTable.PrevTableName='')or
        (DbTableName(theTable.PrevTableName)='')then
      begin
        Log.Add('Create non existing table '+theTable.ObjName);

        try
          CreateTable(theTable);

          inc(C.TableCreate);
          DbTables.Add(StoredName(theTable.ObjName));

          //Execute Standard Inserts also if user whishes
          if(StdInsertsOnCreate)and(Trim(theTable.StandardInserts.Text)<>'')then
          begin
            ErrCount:=SyncErrors.Count;
            DMDB.ExecuteSQLCmdScript(theTable.StandardInserts.Text, SyncErrors);
            for j:=ErrCount to SyncErrors.Count-1 do
              Log.Add('  ERROR: '+Copy(SyncErrors[j], Pos(#13#10, SyncErrors[j])+2, Length(SyncErrors[j])));
            Trans.CommitRetaining;
          end;
        except
          on x: Exception do
          begin
            LogError('Create table '+theTable.ObjName, x.Message);
            Log.Add('  FAILED to create table '+theTable.ObjName);
          end;
        end;

        //Clear previous colname for DB-Sync when table has just been created
        for j:=0 to theTable.Columns.Count-1 do
          TEERColumn(theTable.Columns[j]).PrevColName:='';
      end
      else
      begin
        //Table was renamed
        Log.Add(DMMain.GetTranslatedMessage('Rename existing table %s to %s', 154,
          theTable.PrevTableName, theTable.ObjName));

        try
          RenameTable(theTable, DbTableName(theTable.PrevTableName));

          inc(C.TableRename);
          DbTables[IndexOfText(DbTables, theTable.PrevTableName)]:=StoredName(theTable.ObjName);
          theTable.PrevTableName:='';
          for j:=0 to theTable.Columns.Count-1 do
            TEERColumn(theTable.Columns[j]).PrevColName:='';
        except
          on x: Exception do
            LogError('Rename table '+theTable.PrevTableName, x.Message);
        end;
      end;
    end;

    //---------------------
    //Drop tables not longer in model. Ask once before the first DROP;
    //"No" skips the drops, the sync goes on
    if(Not(KeepExTbls))then
      for i:=0 to DbTables.Count-1 do
      begin
        position:=-1;
        for j:=0 to ModelTables.Count-1 do
          if(CompareText(DbTables[i], TEERTable(ModelTables[j]).ObjName)=0)or
            //the old table of a rename that failed
            (CompareText(DbTables[i], TEERTable(ModelTables[j]).PrevTableName)=0)then
            position:=j;

        if(position=-1)then
          DropTables.Add(DbTables[i]);
      end;

    DoDropTables:=(DropTables.Count>0);
    if(DoDropTables)then
      DoDropTables:=(MessageDlg(
        DMMain.GetTranslatedMessage('The following %s table(s) are not in the model '+
          'and will be DROPPED from the database (all their data is lost):'+#13#10#13#10+
          '%s'+#13#10#13#10+'Drop these tables?', 279,
          IntToStr(DropTables.Count), DropTables.CommaText),
        mtConfirmation, [mbYes, mbNo], 0)=mrYes);

    if(DoDropTables)then
    begin
      //The foreign keys between them would block the drops
      for i:=0 to DropTables.Count-1 do
        try
          DropReferencingForeignKeys(DropTables[i]);
        except
          on x: Exception do
            LogError('Drop foreign keys to table '+DropTables[i], x.Message);
        end;

      for i:=0 to DropTables.Count-1 do
      begin
        Log.Add(DMMain.GetTranslatedMessage('Drop table %s', 155,
          DropTables[i]));

        if(TryExec('DROP TABLE '+QId(DropTables[i])))then
        begin
          inc(C.TableDrop);
          DbTables.Delete(DbTables.IndexOf(DropTables[i]));
        end;
      end;
    end
    else if(DropTables.Count>0)then
      Log.Add('Dropping of '+IntToStr(DropTables.Count)+
        ' table(s) skipped by user: '+DropTables.CommaText);

    //---------------------
    //Drop the foreign keys that are not in the model, they could block the
    //changes of the columns
    for i:=0 to ModelTables.Count-1 do
      if(DbTableName(TEERTable(ModelTables[i]).ObjName)<>'')then
        try
          DropObsoleteForeignKeys(TEERTable(ModelTables[i]));
        except
          on x: Exception do
          begin
            if(Q.Active)then
              Q.Close;
            LogError('Foreign keys of table '+TEERTable(ModelTables[i]).ObjName, x.Message);
          end;
        end;

    //---------------------
    //Compare columns, primary key and indices

    for i:=0 to ModelTables.Count-1 do
    begin
      theTable:=TEERTable(ModelTables[i]);

      //A table whose creation failed above is not in the DB, nothing to compare
      if(DbTableName(theTable.ObjName)='')then
      begin
        Log.Add('Skip table '+theTable.ObjName+' (not in database)');
        continue;
      end;

      Log.Add(DMMain.GetTranslatedMessage('Compare columns from table %s', 156,
        theTable.ObjName));

      try
        SyncExistingTable(theTable);
      except
        on x: Exception do
        begin
          if(Q.Active)then
            Q.Close;
          LogError('Table '+theTable.ObjName, x.Message);
        end;
      end;
    end;

    //---------------------
    //Add the foreign keys of the model
    for i:=0 to ModelTables.Count-1 do
      if(DbTableName(TEERTable(ModelTables[i]).ObjName)<>'')then
        try
          AddMissingForeignKeys(TEERTable(ModelTables[i]));
        except
          on x: Exception do
          begin
            if(Q.Active)then
              Q.Close;
            LogError('Foreign keys of table '+TEERTable(ModelTables[i]).ObjName, x.Message);
          end;
        end;

    try
      DropTmpTable;
    except
    end;
  finally
    DropTables.Free;
    Q.Free;
  end;
end;

end.
