unit DBEERSQLiteSync;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit DBEERSQLiteSync.pas
// ------------------------
// Description
//   Database synchronisation against SQLite (the table part of
//   TDMDBEER.EERMySQLSyncDB, which is MySQL DDL only).
//
//   SQLite has no ALTER COLUMN. The model table is therefore created under a
//   temporary name and compared with the existing table through SQLite's own
//   metadata (pragma_table_info, pragma_foreign_key_list), so both sides are
//   seen the way SQLite sees them. Renamed, appended and plainly dropped
//   columns are done with ALTER TABLE; every other change (datatype, NOT NULL,
//   default, primary key, AUTOINCREMENT, foreign keys) rebuilds the table:
//   copy the rows into the temporary table, drop the old one, rename, recreate
//   indices and triggers. Each table is one transaction, a failure rolls it
//   back and the sync goes on with the next table.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses SysUtils, Classes, EERModel;

type
  TSQLiteSyncCounters = record
    ColumnComp, ColumnMod, ColumnDel, ColumnAdd,
    TableCreate, TableRename, TableDrop, PKChanged,
    IndexDrop, IndexCreate, IndexUpdate: integer;
  end;

//ModelTables: the tables to sync, sorted in FK order
//DbTables: the user tables of the database, kept up to date
//Failures are collected in SyncErrors ("what"+CRLF+"message") and logged
procedure SQLiteSyncTables(EERModel: TEERModel; ModelTables: TList;
  DbTables: TStringList; Log: TStrings; SyncErrors: TStrings;
  KeepExTbls, StdInsertsOnCreate: Boolean; var C: TSQLiteSyncCounters);

implementation

uses DB, SQLDB, Dialogs, Controls, MainDM, DBDM;

procedure SQLiteSyncTables(EERModel: TEERModel; ModelTables: TList;
  DbTables: TStringList; Log: TStrings; SyncErrors: TStrings;
  KeepExTbls, StdInsertsOnCreate: Boolean; var C: TSQLiteSyncCounters);
const
  TmpTbl = 'dbd4_sync_tmp';
type
  TColInfo = record
    Name, Typ, Dflt: string;
    NotNull: Boolean;
    PK: integer;
  end;
  TColInfos = array of TColInfo;
var
  Q: SQLDB.TSQLQuery;
  Trans: SQLDB.TSQLTransaction;
  FKEnforced, DoDropTables: Boolean;
  theTable: TEERTable;
  DropTables: TStringList;
  i, j, position, ErrCount: integer;

  function QId(const s: string): string;
  begin
    QId:='"'+StringReplace(s, '"', '""', [rfReplaceAll])+'"';
  end;

  procedure Exec(const stmt: string);
  begin
    Q.SQL.Text:=stmt;
    Q.ExecSQL;
  end;

  //First field of the first row, '' when there is no row
  function QueryStr(const stmt: string): string;
  begin
    QueryStr:='';
    Q.SQL.Text:=stmt;
    Q.Open;
    try
      if(Not(Q.EOF))then
        QueryStr:=Q.Fields[0].AsString;
    finally
      Q.Close;
    end;
  end;

  procedure QueryList(const stmt: string; theList: TStrings);
  begin
    theList.Clear;
    Q.SQL.Text:=stmt;
    Q.Open;
    try
      while(Not(Q.EOF))do
      begin
        theList.Add(Q.Fields[0].AsString);
        Q.Next;
      end;
    finally
      Q.Close;
    end;
  end;

  //Upper case, no whitespace, no quote characters
  function NormSQL(const s: string): string;
  var k: integer;
  begin
    Result:='';
    for k:=1 to Length(s) do
      if(Not(s[k] in [#9, #10, #13, ' ', '"', '`', '[', ']']))then
        Result:=Result+UpCase(s[k]);
  end;

  //Name of the index a CREATE [UNIQUE] INDEX statement creates
  function IndexNameOf(const stmt: string): string;
  var p: integer;
    s: string;
  begin
    IndexNameOf:='';
    p:=Pos('INDEX ', UpperCase(stmt));
    if(p=0)then
      Exit;
    s:=Trim(Copy(stmt, p+6, Length(stmt)));
    p:=Pos(' ON ', UpperCase(s));
    if(p=0)then
      Exit;
    s:=Trim(Copy(s, 1, p-1));
    s:=StringReplace(s, '"', '', [rfReplaceAll]);
    s:=StringReplace(s, '`', '', [rfReplaceAll]);
    IndexNameOf:=s;
  end;

  //The model's CREATE TABLE statement and its CREATE INDEX statements, as
  //the SQL create script for the SQLite target writes them
  procedure GetCreateStmts(aTable: TEERTable; var CreateStmt: string;
    IdxStmts: TStrings);
  var script, cmd: string;
  begin
    script:=aTable.GetSQLCreateCode(True, //Define PKs
      True, //CreateIndices
      True, //DefineFK
      False, //TblOptions
      False, //StdInserts
      False, //OutputComments
      True, //HideNullField
      True, //PortableIndices: CREATE INDEX statements
      False, False, False, False, False,
      'SQLite');

    CreateStmt:='';
    IdxStmts.Clear;
    while(Trim(script)<>'')do
    begin
      cmd:=Trim(DMDB.GetFirstSQLCmdFromScript(script));
      if(cmd='')then
        continue;

      if(CreateStmt='')then
        CreateStmt:=cmd
      else if(IndexNameOf(cmd)<>'')then
        IdxStmts.Add(cmd);
    end;

    if(CreateStmt='')then
      raise Exception.Create('Table '+aTable.ObjName+' has no columns.');
  end;

  //Create the model table under the temporary name
  procedure CreateTmpTable(aTable: TEERTable; const CreateStmt: string);
  var prefix: string;
  begin
    prefix:='CREATE TABLE '+aTable.GetSQLTableName+' ';
    if(Copy(CreateStmt, 1, Length(prefix))<>prefix)then
      raise Exception.Create('Unexpected CREATE statement for table '+
        aTable.ObjName+': '+Copy(CreateStmt, 1, 60));

    Exec('DROP TABLE IF EXISTS '+QId(TmpTbl));
    Exec('CREATE TABLE '+QId(TmpTbl)+' '+
      Copy(CreateStmt, Length(prefix)+1, Length(CreateStmt)));
  end;

  procedure LoadCols(const tbl: string; var Cols: TColInfos);
  var n: integer;
  begin
    SetLength(Cols, 0);
    Q.SQL.Text:='SELECT name, type, "notnull", dflt_value, pk '+
      'FROM pragma_table_info('+QuotedStr(tbl)+') ORDER BY cid';
    Q.Open;
    try
      while(Not(Q.EOF))do
      begin
        n:=Length(Cols);
        SetLength(Cols, n+1);
        Cols[n].Name:=Q.Fields[0].AsString;
        Cols[n].Typ:=NormSQL(Q.Fields[1].AsString);
        Cols[n].NotNull:=(StrToIntDef(Q.Fields[2].AsString, 0)<>0);
        Cols[n].Dflt:=Trim(Q.Fields[3].AsString);
        Cols[n].PK:=StrToIntDef(Q.Fields[4].AsString, 0);
        Q.Next;
      end;
    finally
      Q.Close;
    end;
  end;

  //One sorted line per foreign key. ColMap (old=new) translates the
  //referencing column names of a table whose columns are being renamed
  procedure LoadFKs(const tbl: string; FKs: TStringList; ColMap: TStrings);
  var prevId, id, line, cols, fromCol: string;
  begin
    FKs.Clear;
    FKs.Sorted:=False;
    prevId:='';
    line:='';
    cols:='';
    Q.SQL.Text:='SELECT id, "table", "from", "to", on_update, on_delete '+
      'FROM pragma_foreign_key_list('+QuotedStr(tbl)+') ORDER BY id, seq';
    Q.Open;
    try
      while(Not(Q.EOF))do
      begin
        id:=Q.Fields[0].AsString;
        if(id<>prevId)then
        begin
          if(prevId<>'')then
            FKs.Add(line+cols);
          //A self reference of the temporary table names the real table
          line:=UpperCase(Q.Fields[1].AsString)+'|'+
            UpperCase(Q.Fields[4].AsString)+'|'+
            UpperCase(Q.Fields[5].AsString)+'|';
          cols:='';
          prevId:=id;
        end;

        fromCol:=Q.Fields[2].AsString;
        if(ColMap<>nil)then
          if(ColMap.IndexOfName(fromCol)>=0)then
            fromCol:=ColMap.Values[fromCol];
        cols:=cols+UpperCase(fromCol)+'>'+UpperCase(Q.Fields[3].AsString)+',';

        Q.Next;
      end;
      if(prevId<>'')then
        FKs.Add(line+cols);
    finally
      Q.Close;
    end;
    FKs.Sort;
  end;

  //The explicitly created indices of a table (not the automatic ones of
  //PRIMARY KEY / UNIQUE constraints): Names[i] with its normalised Defs[i]
  procedure LoadIndices(const tbl: string; Names, Defs: TStrings);
  begin
    Names.Clear;
    Defs.Clear;
    Q.SQL.Text:='SELECT name, sql FROM sqlite_master WHERE type=''index'' '+
      'AND lower(tbl_name)=lower('+QuotedStr(tbl)+') AND sql IS NOT NULL '+
      'ORDER BY name';
    Q.Open;
    try
      while(Not(Q.EOF))do
      begin
        Names.Add(Q.Fields[0].AsString);
        Defs.Add(NormSQL(Q.Fields[1].AsString));
        Q.Next;
      end;
    finally
      Q.Close;
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

  function HasAutoInc(const tbl: string): Boolean;
  begin
    HasAutoInc:=(Pos('AUTOINCREMENT', UpperCase(QueryStr(
      'SELECT sql FROM sqlite_master WHERE type=''table'' '+
      'AND lower(name)=lower('+QuotedStr(tbl)+')')))>0);
  end;

  procedure LogError(const what, msg: string);
  begin
    SyncErrors.Add(what+#13#10+msg);
    Log.Add('  ERROR: '+msg);
  end;

  procedure CreateTable(aTable: TEERTable);
  var CreateStmt: string;
    IdxStmts: TStringList;
    k: integer;
  begin
    IdxStmts:=TStringList.Create;
    try
      GetCreateStmts(aTable, CreateStmt, IdxStmts);
      Exec(CreateStmt);
      for k:=0 to IdxStmts.Count-1 do
        Exec(IdxStmts[k]);
      Trans.CommitRetaining;
    finally
      IdxStmts.Free;
    end;
  end;

  procedure SyncExistingTable(aTable: TEERTable);
  var X, CreateStmt, s, colList, selList: string;
    NewCols, OldCols: TColInfos;
    Src: array of integer;
    Used: array of Boolean;
    IdxStmts, OldIdxNames, OldIdxDefs, Renames, Drops, Triggers,
    NewFKs, OldFKs: TStringList;
    Adds: TList;
    theColumn: TEERColumn;
    k, m: integer;
    NeedRebuild, PKChanged, ColChanged, Rebuilt: Boolean;
    dummy: string;

    //Copy the rows into the temporary table and let it take the place of
    //the old one. The temporary table must exist.
    procedure RebuildTable;
    var n, m, p: integer;
    begin
      //DROP TABLE runs an implicit DELETE, which would fire ON DELETE
      //actions in the referencing tables; foreign_keys cannot be switched
      //inside a transaction
      if(FKEnforced)then
        raise Exception.Create('Table '+X+' has to be rebuilt, but foreign key '+
          'enforcement is switched on for this connection (PRAGMA foreign_keys).');

      Log.Add('Rebuild table '+X);

      colList:='';
      selList:='';
      for n:=0 to High(NewCols) do
        if(Src[n]>=0)then
        begin
          if(colList<>'')then
          begin
            colList:=colList+', ';
            selList:=selList+', ';
          end;
          colList:=colList+QId(NewCols[n].Name);
          selList:=selList+QId(OldCols[Src[n]].Name);
        end;

      if(colList<>'')then
        Exec('INSERT INTO '+QId(TmpTbl)+' ('+colList+') SELECT '+selList+
          ' FROM '+QId(X));

      //DROP TABLE removes the triggers and indices of the table
      QueryList('SELECT sql FROM sqlite_master WHERE type=''trigger'' '+
        'AND lower(tbl_name)=lower('+QuotedStr(X)+') AND sql IS NOT NULL', Triggers);
      LoadIndices(X, OldIdxNames, OldIdxDefs);

      //Legacy mode: the rename must not look at views and triggers that
      //refer to the table while it does not exist
      Exec('PRAGMA legacy_alter_table=ON');
      try
        Exec('DROP TABLE '+QId(X));
        Exec('ALTER TABLE '+QId(TmpTbl)+' RENAME TO '+QId(X));
      finally
        try
          Exec('PRAGMA legacy_alter_table=OFF');
        except
        end;
      end;

      for n:=0 to IdxStmts.Count-1 do
      begin
        if(IndexOfText(OldIdxNames, IndexNameOf(IdxStmts[n]))=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Create index %s on table %s', 163,
            IndexNameOf(IdxStmts[n]), X));
          inc(C.IndexCreate);
        end;
        Exec(IdxStmts[n]);
      end;

      for n:=0 to OldIdxNames.Count-1 do
      begin
        p:=-1;
        for m:=0 to IdxStmts.Count-1 do
          if(CompareText(IndexNameOf(IdxStmts[m]), OldIdxNames[n])=0)then
            p:=m;
        if(p=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Drop obsolete index %s on table %s', 161,
            OldIdxNames[n], X));
          inc(C.IndexDrop);
        end;
      end;

      for n:=0 to Triggers.Count-1 do
        Exec(Triggers[n]);

      Rebuilt:=True;
    end;

    //Bring the indices of a table that was not rebuilt in line
    procedure SyncIndices;
    var n, m, p: integer;
      idxName: string;
    begin
      LoadIndices(X, OldIdxNames, OldIdxDefs);

      //Drop the indices that are not in the model
      for n:=0 to OldIdxNames.Count-1 do
      begin
        p:=-1;
        for m:=0 to IdxStmts.Count-1 do
          if(CompareText(IndexNameOf(IdxStmts[m]), OldIdxNames[n])=0)then
            p:=m;
        if(p=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Drop obsolete index %s on table %s', 161,
            OldIdxNames[n], X));
          inc(C.IndexDrop);
          Exec('DROP INDEX '+QId(OldIdxNames[n]));
        end;
      end;

      for n:=0 to IdxStmts.Count-1 do
      begin
        idxName:=IndexNameOf(IdxStmts[n]);
        p:=IndexOfText(OldIdxNames, idxName);
        if(p=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Create index %s on table %s', 163,
            idxName, X));
          inc(C.IndexCreate);
          Exec(IdxStmts[n]);
        end
        //The table name in the statement may be written differently
        else if(OldIdxDefs[p]<>NormSQL(IdxStmts[n]))and
          (OldIdxDefs[p]<>NormSQL(StringReplace(IdxStmts[n],
            ' ON '+aTable.GetSQLTableName+' ', ' ON '+X+' ', [])))then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Update index %s on table %s', 162,
            idxName, X));
          inc(C.IndexUpdate);
          Exec('DROP INDEX '+QId(OldIdxNames[p]));
          Exec(IdxStmts[n]);
        end;
      end;
    end;

  begin
    //The name as it is written in the database
    X:=DbTables[DbTables.IndexOf(aTable.ObjName)];
    Rebuilt:=False;

    IdxStmts:=TStringList.Create;
    OldIdxNames:=TStringList.Create;
    OldIdxDefs:=TStringList.Create;
    Renames:=TStringList.Create;
    Drops:=TStringList.Create;
    Triggers:=TStringList.Create;
    NewFKs:=TStringList.Create;
    OldFKs:=TStringList.Create;
    Adds:=TList.Create;
    try
      GetCreateStmts(aTable, CreateStmt, IdxStmts);
      CreateTmpTable(aTable, CreateStmt);

      LoadCols(TmpTbl, NewCols);
      LoadCols(X, OldCols);
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
          theColumn:=TEERColumn(aTable.GetColumnByName(NewCols[k].Name));
          if(theColumn<>nil)then
            if(theColumn.PrevColName<>'')then
              for m:=0 to High(OldCols) do
                if(CompareText(theColumn.PrevColName, OldCols[m].Name)=0)and
                  (Not(Used[m]))then
                  Src[k]:=m;
        end;

        if(Src[k]>=0)then
          Used[Src[k]]:=True;
      end;

      //---------------------
      //Compare
      NeedRebuild:=False;
      PKChanged:=False;

      for k:=0 to High(NewCols) do
        if(Src[k]=-1)then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Add Column %s to table %s', 159,
            NewCols[k].Name, X));
          inc(C.ColumnAdd);
          Adds.Add(Pointer(PtrUInt(k)));

          if(NewCols[k].PK>0)then
            PKChanged:=True;
          //ADD COLUMN takes no NOT NULL column without a default
          if(NewCols[k].NotNull)and(NewCols[k].Dflt='')then
            NeedRebuild:=True;
        end
        else
        begin
          ColChanged:=False;

          if(CompareText(NewCols[k].Name, OldCols[Src[k]].Name)<>0)then
          begin
            Renames.Add(OldCols[Src[k]].Name+'='+NewCols[k].Name);
            ColChanged:=True;
          end;

          if(NewCols[k].Typ<>OldCols[Src[k]].Typ)or
            (NewCols[k].NotNull<>OldCols[Src[k]].NotNull)or
            (NewCols[k].Dflt<>OldCols[Src[k]].Dflt)then
          begin
            ColChanged:=True;
            NeedRebuild:=True;
          end;

          if(NewCols[k].PK<>OldCols[Src[k]].PK)then
            PKChanged:=True;

          if(ColChanged)then
          begin
            Log.Add(DMMain.GetTranslatedMessage('Modifying column %s from table %s', 158,
              OldCols[Src[k]].Name, X));
            inc(C.ColumnMod);
          end;
        end;

      for m:=0 to High(OldCols) do
        if(Not(Used[m]))then
        begin
          Log.Add(DMMain.GetTranslatedMessage('Dropping column %s from table %s', 157,
            OldCols[m].Name, X));
          inc(C.ColumnDel);
          Drops.Add(OldCols[m].Name);

          if(OldCols[m].PK>0)then
            PKChanged:=True;
          //DROP COLUMN refuses a column that is part of an index
          if(QueryStr('SELECT count(*) FROM pragma_index_list('+QuotedStr(X)+') il '+
            'JOIN pragma_index_info(il.name) ii WHERE lower(ii.name)=lower('+
            QuotedStr(OldCols[m].Name)+')')<>'0')then
            NeedRebuild:=True;
        end;

      if(PKChanged)then
      begin
        Log.Add(DMMain.GetTranslatedMessage('Change primary key on table %s', 160, X));
        inc(C.PKChanged);
        NeedRebuild:=True;
      end;

      if(HasAutoInc(TmpTbl)<>HasAutoInc(X))then
      begin
        Log.Add('Change AUTOINCREMENT on table '+X);
        NeedRebuild:=True;
      end;

      LoadFKs(TmpTbl, NewFKs, nil);
      LoadFKs(X, OldFKs, Renames);
      if(NewFKs.Text<>OldFKs.Text)then
      begin
        Log.Add('Change foreign keys on table '+X);
        NeedRebuild:=True;
      end;

      //---------------------
      //Apply
      if(NeedRebuild)then
        RebuildTable
      else
      begin
        //Nothing of the temporary table is kept
        Trans.RollbackRetaining;

        if(Renames.Count>0)or(Drops.Count>0)or(Adds.Count>0)then
          try
            for k:=0 to Renames.Count-1 do
              Exec('ALTER TABLE '+QId(X)+' RENAME COLUMN '+QId(Renames.Names[k])+
                ' TO '+QId(Renames.ValueFromIndex[k]));

            for k:=0 to Drops.Count-1 do
              Exec('ALTER TABLE '+QId(X)+' DROP COLUMN '+QId(Drops[k]));

            for k:=0 to Adds.Count-1 do
            begin
              s:=NewCols[PtrUInt(Adds[k])].Name;
              Exec('ALTER TABLE '+QId(X)+' ADD COLUMN '+
                aTable.GetSQLColumnCreateDefCode(
                  aTable.Columns.IndexOf(aTable.GetColumnByName(s)),
                  dummy, True, False, 'SQLite', False));
            end;
          except
            //e.g. a SQLite library without RENAME / DROP COLUMN
            on E: Exception do
            begin
              Trans.RollbackRetaining;
              Log.Add('  '+E.Message);
              Log.Add('  Rebuilding table '+X+' instead');
              CreateTmpTable(aTable, CreateStmt);
              RebuildTable;
            end;
          end;
      end;

      if(Not(Rebuilt))then
        SyncIndices;

      Trans.CommitRetaining;

      //Clear previous colname for DB-Sync
      for k:=0 to aTable.Columns.Count-1 do
        TEERColumn(aTable.Columns[k]).PrevColName:='';
    finally
      Adds.Free;
      OldFKs.Free;
      NewFKs.Free;
      Triggers.Free;
      Drops.Free;
      Renames.Free;
      OldIdxDefs.Free;
      OldIdxNames.Free;
      IdxStmts.Free;
    end;
  end;

begin
  if(DMDB.SchemaSQLQuery.Active)then
    DMDB.SchemaSQLQuery.Close;

  //A plain SQLDB query: the statements of one table stay in one transaction
  //(the dbExpress shim commits after every statement and every Close)
  Trans:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
  Q:=SQLDB.TSQLQuery.Create(nil);
  DropTables:=TStringList.Create;
  try
    Q.DataBase:=DMDB.SQLConn;
    Q.Transaction:=Trans;
    Q.ParamCheck:=False;

    if(Not(Trans.Active))then
      Trans.StartTransaction
    else
      Trans.CommitRetaining;

    FKEnforced:=False;
    try
      FKEnforced:=(QueryStr('SELECT foreign_keys FROM pragma_foreign_keys')='1');
    except
    end;

    //---------------------------------------------------------------
    //Compare Tables

    Log.Add(DMMain.GetTranslatedMessage('Compare tables', 153));

    //---------------------
    //Create non existing
    for i:=0 to ModelTables.Count-1 do
    begin
      theTable:=TEERTable(ModelTables[i]);

      if(DbTables.IndexOf(theTable.ObjName)<>-1)then
        continue;

      //Check if table was renamed
      if(theTable.PrevTableName='')or
        (DbTables.IndexOf(theTable.PrevTableName)=-1)then
      begin
        Log.Add('Create non existing table '+theTable.ObjName);

        try
          CreateTable(theTable);

          inc(C.TableCreate);
          DbTables.Add(theTable.ObjName);

          //Execute Standard Inserts also if user whishes
          if(StdInsertsOnCreate)and(Trim(theTable.StandardInserts.Text)<>'')then
          begin
            ErrCount:=SyncErrors.Count;
            DMDB.ExecuteSQLCmdScript(theTable.StandardInserts.Text, SyncErrors);
            for j:=ErrCount to SyncErrors.Count-1 do
              Log.Add('  ERROR: '+Copy(SyncErrors[j], Pos(#13#10, SyncErrors[j])+2, Length(SyncErrors[j])));
          end;
        except
          on x: Exception do
          begin
            Trans.RollbackRetaining;
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
          Exec('ALTER TABLE '+QId(theTable.PrevTableName)+
            ' RENAME TO '+QId(theTable.ObjName));
          Trans.CommitRetaining;

          inc(C.TableRename);
          DbTables[DbTables.IndexOf(theTable.PrevTableName)]:=theTable.ObjName;
          theTable.PrevTableName:='';
        except
          on x: Exception do
          begin
            Trans.RollbackRetaining;
            LogError('Rename table '+theTable.PrevTableName, x.Message);
          end;
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
          if(CompareText(DbTables[i], TEERTable(ModelTables[j]).ObjName)=0)then
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
      for i:=0 to DropTables.Count-1 do
      begin
        Log.Add(DMMain.GetTranslatedMessage('Drop table %s', 155,
          DropTables[i]));

        try
          if(FKEnforced)then
            raise Exception.Create('Foreign key enforcement is switched on for '+
              'this connection (PRAGMA foreign_keys).');

          Exec('DROP TABLE '+QId(DropTables[i]));
          Trans.CommitRetaining;

          inc(C.TableDrop);
          DbTables.Delete(DbTables.IndexOf(DropTables[i]));
        except
          on x: Exception do
          begin
            Trans.RollbackRetaining;
            LogError('Drop table '+DropTables[i], x.Message);
          end;
        end;
      end
    else if(DropTables.Count>0)then
      Log.Add('Dropping of '+IntToStr(DropTables.Count)+
        ' table(s) skipped by user: '+DropTables.CommaText);

    //---------------------
    //Compare columns, indices and foreign keys

    for i:=0 to ModelTables.Count-1 do
    begin
      theTable:=TEERTable(ModelTables[i]);

      //A table whose creation failed above is not in the DB, nothing to compare
      if(DbTables.IndexOf(theTable.ObjName)=-1)then
      begin
        Log.Add('Skip table '+theTable.ObjName+' (not in database)');
        continue;
      end;

      Log.Add(DMMain.GetTranslatedMessage('Compare columns from table %s', 156,
        theTable.ObjName));

      //Any error rolls this table back and the sync goes on with the next
      try
        SyncExistingTable(theTable);
      except
        on x: Exception do
        begin
          if(Q.Active)then
            Q.Close;
          Trans.RollbackRetaining;
          LogError('Table '+theTable.ObjName, x.Message);
        end;
      end;
    end;
  finally
    DropTables.Free;
    Q.Free;
  end;
end;

end.
