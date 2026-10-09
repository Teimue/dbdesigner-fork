unit EERSQLScript;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// DBDesigner Fork is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// DBDesigner Fork is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with DBDesigner Fork; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//----------------------------------------------------------------------------------------------------------------------
//
// Unit EERSQLScript.pas
// ---------------------
// Description
//   Builds the SQL script of a list of tables (create, drop, optimize,
//   repair). It was a method of the SQL Script Export form
//   (EERExportSQLScript.pas) that read its options from the controls; here
//   the options are a record, so the script can be built without the form
//   (mcp/DBDesignerMCP.pas).
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses
  SysUtils, Classes, EERModel;

const
  //ScriptMode
  ssmCreate = 0;
  ssmDrop = 1;
  ssmOptimize = 2;
  ssmRepair = 3;

type
  TSQLScriptOptions = record
    ScriptMode: integer;
    //FireBird, My SQL, Oracle, PostgreSQL, SQL Server or SQLite
    TargetDatabase: string;

    //Order the tables by their foreign keys
    SortByForeignKeys: Boolean;
    //DROP TABLE statements in front of the creates
    DropTables: Boolean;

    //The parameters of TEERTable.GetSQLCreateCode
    DefinePK,
    CreateIndices,
    DefineFK,
    TblOptions,
    StdInserts,
    OutputComments,
    HideNullField,
    PortableIndices,
    HideOnDeleteUpdateNoAction,
    GOStatement,
    CommitStatement,
    FKIndex,
    DefaultBeforeNotNull: Boolean;

    //Auto increment by sequence / generator and triggers
    AutoIncrement: Boolean;
    AutoIncrementSeqName,
    AutoIncrementPrefix: string;

    //Triggers that store the last change of a record
    LastChange: Boolean;
    LastChangeDateColName,
    LastChangeUserColName,
    LastChangeTriggerPrefix: string;

    //Table and triggers that store the last delete in a table
    LastDelete: Boolean;
    LastDeleteTbName,
    LastDeleteColName,
    LastDeleteTriggerPrefix: string;
  end;

//The options a script for the target database has when nothing else is
//chosen: the values that are fixed per target in the SQL Script Export
//form, its default for the index on foreign keys and the defaults of its
//names; no triggers
procedure InitSQLScriptOptions(out Options: TSQLScriptOptions;
  const TargetDatabase: string; ScriptMode: integer = ssmCreate);

function GetSqlGeneratorOrSequence(const DataBaseType, SeqName: string): string;
function GetDtExclusionSqlTableDef(const DbType, TbName, ColName: string): string;

//The script for the tables in Tables. The list is changed: linked tables
//are removed if the model does not create SQL for them, and it is sorted
function BuildSQLScript(EERModel: TEERModel; Tables: TList;
  const Options: TSQLScriptOptions): string;

implementation

uses MainDM, EERDM, StrUtils;

procedure InitSQLScriptOptions(out Options: TSQLScriptOptions;
  const TargetDatabase: string; ScriptMode: integer = ssmCreate);
var OraPgMs, OraPgFb: Boolean;
begin
  OraPgMs:=(TargetDatabase='Oracle')or(TargetDatabase='PostgreSQL')or(TargetDatabase='SQL Server');
  OraPgFb:=(TargetDatabase='Oracle')or(TargetDatabase='PostgreSQL')or(TargetDatabase='FireBird');

  Options.ScriptMode:=ScriptMode;
  Options.TargetDatabase:=TargetDatabase;

  Options.SortByForeignKeys:=True;
  Options.DropTables:=False;

  Options.DefinePK:=True;
  Options.CreateIndices:=True;
  Options.DefineFK:=True;
  Options.TblOptions:=True;
  Options.StdInserts:=False;
  Options.OutputComments:=False;
  Options.HideNullField:=(TargetDatabase<>'My SQL');
  Options.PortableIndices:=(TargetDatabase<>'My SQL');
  Options.HideOnDeleteUpdateNoAction:=OraPgMs;
  Options.GOStatement:=(TargetDatabase='SQL Server');
  Options.CommitStatement:=OraPgFb;
  Options.FKIndex:=OraPgMs;
  Options.DefaultBeforeNotNull:=OraPgFb;

  Options.AutoIncrement:=False;
  Options.AutoIncrementSeqName:='GlobalSequence';
  Options.AutoIncrementPrefix:='AINC_';

  Options.LastChange:=False;
  Options.LastChangeDateColName:='UPDATE_DATE';
  Options.LastChangeUserColName:='USER';
  Options.LastChangeTriggerPrefix:='UPDT_';

  Options.LastDelete:=False;
  Options.LastDeleteTbName:='DELETE_DATE';
  Options.LastDeleteColName:='DELETE_DATE';
  Options.LastDeleteTriggerPrefix:='EXCDT_';
end;

function GetSqlGeneratorOrSequence(const DataBaseType, SeqName: string): string;
begin
  Result:='';
  if DataBaseType = 'FireBird' then
  begin
    Result := 'CREATE GENERATOR '+SeqName+';';
  end else
  if (DataBaseType = 'Oracle') or (DataBaseType = 'PostgreSQL') then
  begin
    Result := 'CREATE SEQUENCE '+SeqName+';';
  end;
end;

function GetDtExclusionSqlTableDef(const DbType, TbName, ColName: string): string;
var
  Str : TStringList;
begin
  //DbType is received just to maintain future compatibility.
  //This code implements a generic table creation

  Str := TStringList.Create;

  Str.Add('CREATE TABLE ' + TbName + ' (');
  Str.Add('  ' + ColName + ' VARCHAR(15), ');
  Str.Add('  TABLE_NAME VARCHAR(64) NOT NULL, ');
  Str.Add('  PRIMARY KEY (TABLE_NAME)');
  Str.Add('); ');

  Result := Str.Text;
  Str.Free;
end;

function BuildSQLScript(EERModel: TEERModel; Tables: TList;
  const Options: TSQLScriptOptions): string;
var
  s: string;
  i: integer;
  theEERTbl: TEERTable;
  DropIfExists: boolean;
begin
  Result:='';

  DropIfExists := (Options.TargetDatabase = 'My SQL');

  if Tables.Count=0 then
    Exit;

  //Remove Linked Tables if CreateSQLforLinkedObjects is deactivated
  if(Not(EERModel.CreateSQLforLinkedObjects))then
  begin
    i:=0;
    while(i<Tables.Count)do
      if(TEERTable(Tables[i]).IsLinkedObject)then
        Tables.Delete(i)
      else
        inc(i);
  end;

  //Sort tables alphabetically
  EERModel.SortEERObjectListByObjName(Tables);

  //Sort in FK order
  if(Options.SortByForeignKeys)then
    EERModel.SortEERTableListByForeignKeyReferences(Tables);

  //When dropping the tables, reverse tablelist order
  if(Options.ScriptMode=ssmDrop)then
    DMMain.ReverseList(Tables);

  s:='';

  if Options.AutoIncrement then
  begin
    s :=
      s +
      GetSqlGeneratorOrSequence(Options.TargetDatabase, Options.AutoIncrementSeqName)+
      #13#10#13#10;
  end;

  //do for all tables
  if Options.DropTables and (Options.ScriptMode=ssmCreate) then
  begin
    for i:=Tables.Count-1 downto 0 do
    begin
      theEERTbl:=Tables[i];
      s:=s+theEERTbl.GetSQLDropCode(DropIfExists, Options.TargetDatabase)+#13#10#13#10
    end;
  end;

  //Create Last Delete record datetime
  if Options.LastDelete then
  begin
    s := s + GetDtExclusionSqlTableDef(
                                        Options.TargetDatabase,
                                        Options.LastDeleteTbName,
                                        Options.LastDeleteColName);
    s := s + sLineBreak;
  end;

  //do for all tables
  for i:=0 to Tables.Count-1 do
  begin
    theEERTbl:=Tables[i];

    if(Options.ScriptMode=ssmCreate)then
      s:=s+theEERTbl.GetSQLCreateCode(Options.DefinePK,
        Options.CreateIndices, Options.DefineFK,
        Options.TblOptions, Options.StdInserts,
        Options.OutputComments,
        Options.HideNullField,
        Options.PortableIndices,
        Options.HideOnDeleteUpdateNoAction,
        Options.GOStatement,
        Options.CommitStatement,
        Options.FKIndex,
        Options.DefaultBeforeNotNull,
        Options.TargetDatabase,
        Options.AutoIncrementSeqName,
        Options.AutoIncrementPrefix,
        Options.AutoIncrement,
        Options.LastChange,
        Options.LastChangeDateColName,
        Options.LastChangeUserColName,
        Options.LastChangeTriggerPrefix,
        Options.LastDelete,
        Options.LastDeleteTbName,
        Options.LastDeleteColName,
        Options.LastDeleteTriggerPrefix
        )
        //SQLite: the table code is tidied, one empty line between tables
        +IfThen((Options.TargetDatabase = 'SQLite')or(Options.TargetDatabase = 'FireBird'), #13#10, #13#10#13#10)
    else if(Options.ScriptMode=ssmDrop)then
      s:=s+theEERTbl.GetSQLDropCode(DropIfExists, Options.TargetDatabase)+#13#10#13#10
    else if(Options.ScriptMode=ssmOptimize)then
      s:=s+'OPTIMIZE TABLE '+theEERTbl.GetSQLTableName+';'+#13#10#13#10
    else if(Options.ScriptMode=ssmRepair)then
      s:=s+'REPAIR TABLE '+theEERTbl.GetSQLTableName+';'+#13#10#13#10;

  end;

  if(DMEER.OutputLinuxStyleLineBreaks)then
    s:=DMMain.ReplaceString(s, #13#10, #10);

  Result:=s;
end;

end.
