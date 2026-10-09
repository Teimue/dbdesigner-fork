program DBDesignerMCP;

// MCP server (Model Context Protocol) for DBDesigner models: JSON-RPC 2.0,
// one message per line, on stdin/stdout. It works on the model classes of
// the application (src/EERModel.pas), so it reads the files and writes the
// SQL the same way as DBDesigner Fork itself.
//
// Tools:
//   open_model      load a model file, it stays open for the other tools
//   new_model       start an empty model
//   list_tables     the tables of the open model
//   describe_table  columns, indices and relations of one table
//   list_relations  the relations of the model or of one table
//   export_sql      the SQL script for a target database
//   add_table       a new table, with its columns
//   add_column      a new column of a table
//   add_relation    a relation between two tables (foreign key)
//   rename_table    another name for a table
//   change_column   another name, datatype or other properties of a column
//   delete_table, delete_column, delete_relation
//   add_index, delete_index
//   move_table      another place in the diagram
//   arrange_tables  tables side by side in rows, without overlaps
//   list_regions, add_region, change_region, delete_region
//   list_notes, add_note, change_note, delete_note
//   list_images, add_image, change_image, delete_image
//   export_model_image     the diagram as a PNG, JPG or BMP file
//   list_datatypes, add_datatype, change_datatype, delete_datatype
//   get_model_settings, change_model_settings
//   save_model      write the model to its file or to another one
//   list_connections       the database connections stored in DBDesigner
//   connect_database       connect to a Firebird database
//   disconnect_database
//   list_database_tables   the tables of the connected database
//   reverse_engineer       tables of the database into the open model
//   sync_database          change the database to match the open model
//
// The database tools work with Firebird only. The settings of the program
// are read (stored connections) but never written.
//
// Needs the application infrastructure (data modules, LCL), like the
// programs in tests/: the model classes are controls. No window is shown.
//   lazbuild mcp/DBDesignerMCP.lpi   ->   bin/DBDesignerMCP
//
// Message boxes of the application code are not shown, their text goes into
// the result of the tool (see McpPromptDialog).

{$I DBDesigner4.inc}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, StrUtils, Types, Forms, Controls, Graphics, Dialogs,
  InterfaceBase,
  iostream, fpjson, jsonparser, LazUTF8, LConvEncoding, FileUtil,
  DB, SQLDB,
  MainDM, DBDM, EERDM, DBEERDM, DBEERFirebird, EERModel, EERSQLScript;

const
  ServerName = 'dbdesigner-fork';
  ServerVersion = '0.6.0';
  //The newest protocol version comes first, it is the answer to a client
  //that asks for a version not in this list
  ProtocolVersions: array[0..2] of string = ('2025-06-18', '2025-03-26', '2024-11-05');

  //The names the SQL export uses for its targets (see EERExportSQLScript)
  TargetDatabases: array[0..5] of string =
    ('FireBird', 'My SQL', 'Oracle', 'PostgreSQL', 'SQL Server', 'SQLite');

  RelKindNames: array[0..5] of string =
    ('1:1', '1:n', '1:n non-identifying', 'n:m', '1:1 sub type', '1:1 non-identifying');
  IndexKindNames: array[0..3] of string =
    ('PRIMARY', 'INDEX', 'UNIQUE', 'FULLTEXT');
  RefActionNames: array[0..4] of string =
    ('RESTRICT', 'CASCADE', 'SET NULL', 'NO ACTION', 'SET DEFAULT');

  //Room that is kept free around a table that is placed without a
  //position: a table grows with the columns it gets later, and the lines
  //of the relations need space
  PlaceGapX = 80;
  PlaceGapY = 80;

type
  //An error of a tool: the text goes to the client as the result
  EToolError = class(Exception);
  //An error of the protocol: answered as a JSON-RPC error
  ERpcError = class(Exception)
  public
    Code: integer;
    constructor Create(ACode: integer; const Msg: string);
  end;

var
  StdIn, StdOut: TIOStream;
  InBuf: string = '';
  ParentForm: TForm;
  Model: TEERModel = nil;
  //The file of the open model, empty for a new one
  ModelFile: string = '';
  //The connection to the database, owned here. DMDB.CurrentDBConn points to
  //it while the connection is open
  DBConn: TDBConn = nil;
  //The texts of the message boxes the application code wanted to show
  DialogMessages: TStringList;

constructor ERpcError.Create(ACode: integer; const Msg: string);
begin
  inherited Create(Msg);
  Code:=ACode;
end;

// ---------------------------------------------------------------------------
// Message boxes

//ShowMessage and MessageDlg end here: nobody can answer a dialog of a
//server, so the text is kept and the dialog counts as cancelled
function McpPromptDialog(const DialogCaption, DialogMessage: String;
  DialogType: longint; Buttons: PLongint;
  ButtonCount, DefaultIndex, EscapeResult: Longint;
  UseDefaultPos: boolean; X, Y: Longint): Longint;
begin
  DialogMessages.Add(DialogMessage);
  Result:=EscapeResult;
end;

function McpMessageBox(Text, Caption: PChar; Flags: Longint): Integer;
begin
  DialogMessages.Add(StrPas(Text));
  Result:=2; //IDCANCEL
end;

// ---------------------------------------------------------------------------
// Transport

//One line from stdin, without the line break. False at the end of the input
function ReadMessage(out Line: string): Boolean;
var Chunk: array[0..4095] of Char;
  n, p: integer;
begin
  Line:='';
  repeat
    p:=Pos(#10, InBuf);
    if(p>0)then
    begin
      Line:=Copy(InBuf, 1, p-1);
      Delete(InBuf, 1, p);
      if(Line<>'')and(Line[Length(Line)]=#13)then
        SetLength(Line, Length(Line)-1);
      Result:=True;
      Exit;
    end;

    n:=StdIn.Read(Chunk, SizeOf(Chunk));
    if(n>0)then
      InBuf:=InBuf+Copy(Chunk, 1, n);
  until(n<=0);

  //The last line may come without a line break
  Line:=InBuf;
  InBuf:='';
  Result:=(Line<>'');
end;

//Takes the ownership of Msg
procedure SendMessage(Msg: TJSONObject);
var s: string;
begin
  try
    s:=Msg.AsJSON+#10;
  finally
    Msg.Free;
  end;
  StdOut.WriteBuffer(s[1], Length(s));
end;

//The id of a request as it has to go back (number or string)
function CloneID(ID: TJSONData): TJSONData;
begin
  if(ID=nil)then
    Result:=TJSONNull.Create
  else
    Result:=ID.Clone;
end;

procedure SendResult(ID: TJSONData; AResult: TJSONData);
begin
  SendMessage(TJSONObject.Create(['jsonrpc', '2.0', 'id', CloneID(ID), 'result', AResult]));
end;

procedure SendError(ID: TJSONData; Code: integer; const Msg: string);
begin
  SendMessage(TJSONObject.Create(['jsonrpc', '2.0', 'id', CloneID(ID),
    'error', TJSONObject.Create(['code', Code, 'message', Msg])]));
end;

// ---------------------------------------------------------------------------
// Helpers

//Text of the model for JSON. The model files of DBDesigner 4 are Latin-1,
//text that is no valid UTF-8 is taken as such
function U(const s: string): string;
begin
  if(FindInvalidUTF8Codepoint(PChar(s), Length(s))>=0)then
    Result:=CP1252ToUTF8(s)
  else
    Result:=s;
end;

function ArgStr(Args: TJSONObject; const Name: string; const Default: string = ''): string;
begin
  if(Args<>nil)and(Args.IndexOfName(Name)>=0)and(Args.Types[Name]=jtString)then
    Result:=Args.Strings[Name]
  else
    Result:=Default;
end;

function ArgBool(Args: TJSONObject; const Name: string; Default: Boolean): Boolean;
begin
  if(Args<>nil)and(Args.IndexOfName(Name)>=0)and(Args.Types[Name]=jtBoolean)then
    Result:=Args.Booleans[Name]
  else
    Result:=Default;
end;

function HasArg(Args: TJSONObject; const Name: string): Boolean;
begin
  Result:=(Args<>nil)and(Args.IndexOfName(Name)>=0)and(Args.Types[Name]<>jtNull);
end;

function ArgInt(Args: TJSONObject; const Name: string; Default: integer): integer;
begin
  if(Args<>nil)and(Args.IndexOfName(Name)>=0)and(Args.Types[Name]=jtNumber)then
    Result:=Args.Integers[Name]
  else
    Result:=Default;
end;

//The position of a name in a list of names, -1 if it is not there
function IndexInList(const Names: array of string; const Name: string): integer;
var i: integer;
begin
  Result:=-1;
  for i:=Low(Names) to High(Names) do
    if(CompareText(Names[i], Name)=0)then
      Result:=i;
end;

procedure NeedModel;
begin
  if(Model=nil)then
    raise EToolError.Create('No model is open. Call open_model first.');
end;

function NeedTable(const TableName: string): TEERTable;
begin
  NeedModel;
  if(TableName='')then
    raise EToolError.Create('The argument "table" is missing.');
  Result:=Model.GetEERObjectByName(EERTable, TableName);
  if(Result=nil)then
    raise EToolError.CreateFmt('There is no table "%s" in the model. '+
      'list_tables shows the tables.', [TableName]);
end;

//The tables or relations of the model, sorted by name. The caller frees it
function GetObjects(ObjType: TEERObject): TList;
begin
  Result:=TList.Create;
  Model.GetEERObjectList([ObjType], Result);
  Model.SortEERObjectListByObjName(Result);
end;

function NameInList(const Names: array of string; Index: integer): string;
begin
  if(Index>=Low(Names))and(Index<=High(Names))then
    Result:=Names[Index]
  else
    Result:=IntToStr(Index);
end;

function PrimaryKeyColumns(Table: TEERTable): TJSONArray;
var i: integer;
begin
  Result:=TJSONArray.Create;
  for i:=0 to Table.Columns.Count-1 do
    if(TEERColumn(Table.Columns[i]).PrimaryKey)then
      Result.Add(U(TEERColumn(Table.Columns[i]).ColName));
end;

function ColumnToJSON(Column: TEERColumn): TJSONObject;
var Datatype: TEERDatatype;
  Options: TJSONArray;
  i: integer;
begin
  Datatype:=Model.GetDataType(Column.idDatatype);

  Result:=TJSONObject.Create;
  Result.Add('name', U(Column.ColName));
  if(Datatype<>nil)then
    Result.Add('datatype', U(Datatype.TypeName+Column.DatatypeParams))
  else
    Result.Add('datatype', U(Column.DatatypeParams));
  Result.Add('primary_key', Column.PrimaryKey);
  Result.Add('not_null', Column.NotNull);
  Result.Add('auto_increment', Column.AutoInc);
  Result.Add('foreign_key', Column.IsForeignKey);

  if(Datatype<>nil)then
  begin
    Options:=TJSONArray.Create;
    for i:=0 to Datatype.OptionCount-1 do
      if(Column.OptionSelected[i])then
        Options.Add(U(Datatype.Options[i]));
    if(Options.Count>0)then
      Result.Add('options', Options)
    else
      Options.Free;
  end;

  if(Column.DefaultValue<>'')then
    Result.Add('default', U(Column.DefaultValue));
  if(Column.Comments<>'')then
    Result.Add('comments', U(Column.Comments));
end;

function IndexToJSON(Table: TEERTable; Index: TEERIndex): TJSONObject;
var Cols: TJSONArray;
  Column: TEERColumn;
  i: integer;
begin
  Cols:=TJSONArray.Create;
  for i:=0 to Index.Columns.Count-1 do
  begin
    Column:=Table.GetColumnByID(StrToIntDef(Index.Columns[i], -1));
    if(Column<>nil)then
      Cols.Add(U(Column.ColName));
  end;

  Result:=TJSONObject.Create(['name', U(Index.IndexName),
    'kind', NameInList(IndexKindNames, Index.IndexKind),
    'columns', Cols]);
  //The index of a foreign key is made and removed with its relation
  if(Index.FKRefDef_Obj_id>-1)then
    Result.Add('foreign_key_index', True);
end;

function RelationToJSON(Rel: TEERRel): TJSONObject;
var Cols: TJSONArray;
  i: integer;
begin
  //FKFields: column of the parent table = column of the child table
  Cols:=TJSONArray.Create;
  for i:=0 to Rel.FKFields.Count-1 do
    Cols.Add(TJSONObject.Create(['parent', U(Rel.FKFields.Names[i]),
      'child', U(Rel.FKFields.ValueFromIndex[i])]));

  Result:=TJSONObject.Create;
  Result.Add('name', U(Rel.ObjName));
  Result.Add('kind', NameInList(RelKindNames, Rel.RelKind));
  if(Rel.SrcTbl<>nil)then
    Result.Add('parent_table', U(Rel.SrcTbl.ObjName));
  if(Rel.DestTbl<>nil)then
    Result.Add('child_table', U(Rel.DestTbl.ObjName));
  Result.Add('columns', Cols);
  Result.Add('optional_parent', Rel.OptionalStart);
  Result.Add('optional_child', Rel.OptionalEnd);

  //Without the reference definition the SQL code has no foreign key
  Result.Add('foreign_key_constraint', Rel.CreateRefDef);
  if(Rel.CreateRefDef)then
  begin
    Result.Add('on_delete', NameInList(RefActionNames,
      StrToIntDef(Rel.RefDef.Values['OnDelete'], 3)));
    Result.Add('on_update', NameInList(RefActionNames,
      StrToIntDef(Rel.RefDef.Values['OnUpdate'], 3)));
  end;
  if(Rel.Comments<>'')then
    Result.Add('comments', U(Rel.Comments));
end;

// ---------------------------------------------------------------------------
// Tools

//A model file has the DBMODEL element at its start
function IsModelFile(const FileName: string): Boolean;
var Stream: TFileStream;
  Head: string;
begin
  Stream:=TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Head, 1024);
    SetLength(Head, Stream.Read(Head[1], Length(Head)));
  finally
    Stream.Free;
  end;
  Result:=(Pos('<DBMODEL', Head)>0);
end;

function ToolOpenModel(Args: TJSONObject): TJSONData;
var FileName: string;
  NewModel: TEERModel;
begin
  FileName:=ArgStr(Args, 'path');
  if(FileName='')then
    raise EToolError.Create('The argument "path" is missing.');
  FileName:=ExpandFileName(FileName);
  if(Not(FileExists(FileName)))then
    raise EToolError.CreateFmt('The file "%s" does not exist.', [FileName]);
  //The loader takes any other file as an empty model
  if(Not(IsModelFile(FileName)))then
    raise EToolError.CreateFmt('The file "%s" is not a DBDesigner model '+
      '(no DBMODEL element).', [FileName]);

  NewModel:=TEERModel.Create(ParentForm);
  try
    NewModel.Visible:=False;
    //Read the settings, do not append to a model
    NewModel.LoadFromFile(FileName, True, False, False, False);

    //The loader reports its errors in message boxes
    if(DialogMessages.Count>0)then
      raise EToolError.CreateFmt('The file "%s" could not be loaded.', [FileName]);
  except
    NewModel.Free;
    raise;
  end;

  FreeAndNil(Model);
  Model:=NewModel;
  ModelFile:=FileName;

  Result:=TJSONObject.Create([
    'file', U(FileName),
    'model_name', U(Model.GetModelName),
    'database_type', U(Model.DatabaseType),
    'tables', Model.GetEERObjectCount([EERTable]),
    'relations', Model.GetEERObjectCount([EERRelation]),
    'regions', Model.GetEERObjectCount([EERRegion]),
    'notes', Model.GetEERObjectCount([EERNote]),
    'comments', U(Model.ModelComments)]);
end;

function ToolNewModel(Args: TJSONObject): TJSONData;
var NewModel: TEERModel;
begin
  NewModel:=TEERModel.Create(ParentForm);
  NewModel.Visible:=False;
  if(ArgStr(Args, 'name')<>'')then
    NewModel.SetModelName(ArgStr(Args, 'name'));

  FreeAndNil(Model);
  Model:=NewModel;
  ModelFile:='';

  Result:=TJSONObject.Create(['model_name', U(Model.GetModelName),
    'database_type', U(Model.DatabaseType), 'tables', 0]);
end;

function ToolListTables(Args: TJSONObject): TJSONData;
var Tables: TList;
  Table: TEERTable;
  Item: TJSONObject;
  i: integer;
begin
  NeedModel;

  Result:=TJSONArray.Create;
  Tables:=GetObjects(EERTable);
  try
    for i:=0 to Tables.Count-1 do
    begin
      Table:=Tables[i];
      Item:=TJSONObject.Create(['name', U(Table.ObjName),
        'columns', Table.Columns.Count,
        'primary_key', PrimaryKeyColumns(Table)]);
      if(Table.IsLinkedObject)then
        Item.Add('linked', True);
      if(Table.GetRegion<>nil)then
        Item.Add('region', U(TEERRegion(Table.GetRegion).ObjName));
      if(Table.Comments<>'')then
        Item.Add('comments', U(Table.Comments));
      TJSONArray(Result).Add(Item);
    end;
  finally
    Tables.Free;
  end;
end;

//Place and size of an object in the diagram, in the units of the model
function PositionToJSON(Obj: TEERObj): TJSONObject;
begin
  Result:=TJSONObject.Create(['x', Obj.Obj_X, 'y', Obj.Obj_Y,
    'width', Obj.Obj_W, 'height', Obj.Obj_H]);
end;

//The tables that lie over or under a table in the diagram
function OverlappingTables(Table: TEERTable): TJSONArray;
var Tables: TList;
  Other: TEERTable;
  i: integer;
begin
  Result:=TJSONArray.Create;
  Tables:=GetObjects(EERTable);
  try
    for i:=0 to Tables.Count-1 do
    begin
      Other:=Tables[i];
      if(Other<>Table)and
        (Table.Obj_X<Other.Obj_X+Other.Obj_W)and(Other.Obj_X<Table.Obj_X+Table.Obj_W)and
        (Table.Obj_Y<Other.Obj_Y+Other.Obj_H)and(Other.Obj_Y<Table.Obj_Y+Table.Obj_H)then
        Result.Add(U(Other.ObjName));
    end;
  finally
    Tables.Free;
  end;
end;

function TableToJSON(Table: TEERTable): TJSONObject;
var Columns, Indices, Parents, Children, Overlaps: TJSONArray;
  i: integer;
begin
  Columns:=TJSONArray.Create;
  for i:=0 to Table.Columns.Count-1 do
    Columns.Add(ColumnToJSON(TEERColumn(Table.Columns[i])));

  Indices:=TJSONArray.Create;
  for i:=0 to Table.Indices.Count-1 do
    Indices.Add(IndexToJSON(Table, TEERIndex(Table.Indices[i])));

  //RelEnd: the relations this table is the child of
  Parents:=TJSONArray.Create;
  for i:=0 to Table.RelEnd.Count-1 do
    Parents.Add(RelationToJSON(TEERRel(Table.RelEnd[i])));
  Children:=TJSONArray.Create;
  for i:=0 to Table.RelStart.Count-1 do
    Children.Add(RelationToJSON(TEERRel(Table.RelStart[i])));

  Result:=TJSONObject.Create;
  Result.Add('name', U(Table.ObjName));
  if(Table.GetTablePrefix<>'')then
    Result.Add('sql_name', U(Table.GetSQLTableName));
  if(Table.Comments<>'')then
    Result.Add('comments', U(Table.Comments));
  if(Table.IsLinkedObject)then
    Result.Add('linked', True);
  Result.Add('position', PositionToJSON(Table));
  if(Table.GetRegion<>nil)then
    Result.Add('region', U(TEERRegion(Table.GetRegion).ObjName));
  //A table that got columns may have grown over its neighbours
  Overlaps:=OverlappingTables(Table);
  if(Overlaps.Count>0)then
    Result.Add('overlaps_tables', Overlaps)
  else
    Overlaps.Free;
  Result.Add('columns', Columns);
  Result.Add('indices', Indices);
  Result.Add('relations_to_parents', Parents);
  Result.Add('relations_to_children', Children);
end;

function ToolDescribeTable(Args: TJSONObject): TJSONData;
begin
  Result:=TableToJSON(NeedTable(ArgStr(Args, 'table')));
end;

function ToolListRelations(Args: TJSONObject): TJSONData;
var Rels: TList;
  Rel: TEERRel;
  Table: TEERTable;
  i: integer;
begin
  NeedModel;
  Table:=nil;
  if(ArgStr(Args, 'table')<>'')then
    Table:=NeedTable(ArgStr(Args, 'table'));

  Result:=TJSONArray.Create;
  Rels:=GetObjects(EERRelation);
  try
    for i:=0 to Rels.Count-1 do
    begin
      Rel:=Rels[i];
      if(Table=nil)or(Rel.SrcTbl=Table)or(Rel.DestTbl=Table)then
        TJSONArray(Result).Add(RelationToJSON(Rel));
    end;
  finally
    Rels.Free;
  end;
end;

//The SQL script as the SQL export dialog writes it (EERSQLScript), with the
//settings the dialog has for the target database
function ToolExportSQL(Args: TJSONObject): TJSONData;
var Target, s, Script: string;
  Tables: TList;
  Options: TSQLScriptOptions;
  i: integer;
begin
  NeedModel;

  i:=IndexInList(TargetDatabases, ArgStr(Args, 'database'));
  if(i<0)then
    raise EToolError.Create('The argument "database" has to be one of: '+
      'FireBird, My SQL, Oracle, PostgreSQL, SQL Server, SQLite.');
  Target:=TargetDatabases[i];

  Script:=LowerCase(ArgStr(Args, 'script', 'create'));
  if(Script<>'create')and(Script<>'drop')then
    raise EToolError.Create('The argument "script" has to be create or drop.');

  InitSQLScriptOptions(Options, Target);
  if(Script='drop')then
    Options.ScriptMode:=ssmDrop;
  Options.DefineFK:=ArgBool(Args, 'foreign_keys', True);
  Options.OutputComments:=ArgBool(Args, 'comments', False);
  Options.DropTables:=ArgBool(Args, 'drop_tables', False);
  Options.StdInserts:=ArgBool(Args, 'standard_inserts', False);
  Options.AutoIncrement:=ArgBool(Args, 'auto_increment_triggers', False);
  Options.AutoIncrementSeqName:=ArgStr(Args, 'sequence_name', Options.AutoIncrementSeqName);
  Options.LastChange:=ArgBool(Args, 'last_change_triggers', False);
  Options.LastDelete:=ArgBool(Args, 'last_delete_triggers', False);

  //The dialog offers these only where the generator has them
  if(Options.AutoIncrement)and(Target<>'Oracle')and(Target<>'FireBird')then
    raise EToolError.Create('"auto_increment_triggers" is for Oracle and FireBird only.');
  if(Options.LastChange or Options.LastDelete)and
    (Target<>'Oracle')and(Target<>'FireBird')and(Target<>'SQL Server')then
    raise EToolError.Create('"last_change_triggers" and "last_delete_triggers" '+
      'are for Oracle, FireBird and SQL Server only.');

  Tables:=TList.Create;
  try
    if(ArgStr(Args, 'table')<>'')then
    begin
      Tables.Add(NeedTable(ArgStr(Args, 'table')));
      //The order by foreign keys takes a list in which every table refers
      //to a table outside of it for circular relations
      Options.SortByForeignKeys:=False;
    end
    else
      Model.GetEERObjectList([EERTable], Tables);

    s:=BuildSQLScript(Model, Tables, Options);
    if(Tables.Count=0)then
      raise EToolError.Create('There is no table to write: the model is empty, '+
        'or the table is linked from another model.');
  finally
    Tables.Free;
  end;

  Result:=TJSONString.Create(U(TrimRight(StringReplace(s, #13#10, #10, [rfReplaceAll]))));
end;

// ---------------------------------------------------------------------------
// Tools that change the model

function HasPrimaryKey(Table: TEERTable): Boolean;
var i: integer;
begin
  Result:=False;
  for i:=0 to Table.Columns.Count-1 do
    if(TEERColumn(Table.Columns[i]).PrimaryKey)then
      Result:=True;
end;

//The column of that name, upper and lower case make no difference in SQL
function FindColumn(Table: TEERTable; const ColName: string): TEERColumn;
var i: integer;
begin
  Result:=nil;
  for i:=0 to Table.Columns.Count-1 do
    if(CompareText(TEERColumn(Table.Columns[i]).ColName, ColName)=0)then
      Result:=TEERColumn(Table.Columns[i]);
end;

procedure NeedChangeable(Table: TEERTable);
begin
  if(Table.IsLinkedObject)then
    raise EToolError.CreateFmt('The table "%s" is linked from another model '+
      'and cannot be changed here.', [Table.ObjName]);
end;

//"VARCHAR(45)", "DECIMAL(10,2)", "INTEGER UNSIGNED": the datatype of the
//model, its parameters as the model stores them and the options. An option
//is selected only if it is named
procedure ParseDatatype(const Text: string; out Datatype: TEERDatatype;
  out Params: string; Options: TStrings);
var TypeName, Rest, Names: string;
  p, q, i: integer;
begin
  Params:='';
  Options.Clear;
  Rest:='';
  TypeName:=Trim(Text);

  p:=Pos('(', TypeName);
  if(p>0)then
  begin
    q:=RPos(')', TypeName);
    if(q<p)then
      raise EToolError.CreateFmt('The datatype "%s" has no closing bracket.', [Text]);
    Params:=StringReplace(Copy(TypeName, p, q-p+1), ' ', '', [rfReplaceAll]);
    Rest:=Trim(Copy(TypeName, q+1, Length(TypeName)));
    TypeName:=Trim(Copy(TypeName, 1, p-1));
  end;

  //"DOUBLE PRECISION" is a name, "INTEGER UNSIGNED" a name and an option
  Datatype:=Model.GetDataTypeByName(TypeName);
  while(Datatype=nil)and(Pos(' ', TypeName)>0)do
  begin
    q:=RPos(' ', TypeName);
    Rest:=Trim(Copy(TypeName, q+1, Length(TypeName))+' '+Rest);
    TypeName:=Trim(Copy(TypeName, 1, q-1));
    Datatype:=Model.GetDataTypeByName(TypeName);
  end;

  if(Datatype=nil)then
  begin
    Names:='';
    for i:=0 to Model.Datatypes.Count-1 do
      Names:=Names+IfThen(i>0, ', ')+TEERDatatype(Model.Datatypes[i]).TypeName;
    raise EToolError.CreateFmt('The model has no datatype "%s". Its datatypes: %s',
      [Text, Names]);
  end;
  if(Params='')and(Datatype.ParamRequired)then
    raise EToolError.CreateFmt('The datatype %s needs its parameters, e.g. %s(%s).',
      [Datatype.TypeName, Datatype.TypeName, IfThen(Datatype.ParamCount>1, '10,2', '45')]);

  Options.Delimiter:=' ';
  Options.StrictDelimiter:=True;
  Options.DelimitedText:=Rest;
  for i:=Options.Count-1 downto 0 do
    if(Options[i]='')then
      Options.Delete(i);
  for i:=0 to Options.Count-1 do
  begin
    p:=-1;
    for q:=0 to Datatype.OptionCount-1 do
      if(CompareText(Datatype.Options[q], Options[i])=0)then
        p:=q;
    if(p<0)then
      raise EToolError.CreateFmt('The datatype %s has no option "%s".',
        [Datatype.TypeName, Options[i]]);
  end;
end;

//A new column at the end of the table, from the arguments name, datatype,
//primary_key, not_null, auto_increment, default and comments
procedure AddColumn(Table: TEERTable; Args: TJSONObject);
var ColName: string;
  Datatype: TEERDatatype;
  Params: string;
  Options: TStringList;
  Column: TEERColumn;
  i: integer;
begin
  ColName:=Trim(ArgStr(Args, 'name'));
  if(ColName='')then
    raise EToolError.Create('A column needs a "name".');
  if(FindColumn(Table, ColName)<>nil)then
    raise EToolError.CreateFmt('The table "%s" has a column "%s" already.',
      [Table.ObjName, FindColumn(Table, ColName).ColName]);
  if(ArgStr(Args, 'datatype')='')then
    raise EToolError.CreateFmt('The column "%s" needs a "datatype".', [ColName]);

  Options:=TStringList.Create;
  try
    Options.CaseSensitive:=False;
    ParseDatatype(ArgStr(Args, 'datatype'), Datatype, Params, Options);

    Column:=TEERColumn.Create(Table);
    Column.ColName:=ColName;
    Column.PrevColName:='';
    Column.Obj_id:=DMMain.GetNextGlobalID;
    Column.Pos:=Table.Columns.Count;
    Column.idDatatype:=Datatype.id;
    Column.DatatypeParams:=Params;
    Column.Width:=-1;
    Column.Prec:=-1;
    Column.PrimaryKey:=ArgBool(Args, 'primary_key', False);
    Column.NotNull:=ArgBool(Args, 'not_null', False)or(Column.PrimaryKey);
    Column.AutoInc:=ArgBool(Args, 'auto_increment', False);
    Column.IsForeignKey:=False;
    for i:=0 to Datatype.OptionCount-1 do
      Column.OptionSelected[i]:=(Options.IndexOf(Datatype.Options[i])>=0);
    Column.DefaultValue:=ArgStr(Args, 'default');
    Column.Comments:=ArgStr(Args, 'comments');
    Table.Columns.Add(Column);
  finally
    Options.Free;
  end;
end;

//Moves a table to the nearest place where it has free room on all sides:
//the place is looked for with a frame of half the gap around the table
procedure PlaceWithRoom(Table: TEERTable);
var x, y: integer;
begin
  x:=Table.Obj_X-PlaceGapX div 2;
  y:=Table.Obj_Y-PlaceGapY div 2;
  if(x<0)then x:=0;
  if(y<0)then y:=0;
  with Model.GetFreeObjPos(x, y, Table.Obj_W+PlaceGapX, Table.Obj_H+PlaceGapY, Table) do
  begin
    Table.Obj_X:=X+PlaceGapX div 2;
    Table.Obj_Y:=Y+PlaceGapY div 2;
  end;
end;

function ToolAddTable(Args: TJSONObject): TJSONData;
var TableName: string;
  Table: TEERTable;
  Columns: TJSONArray;
  i: integer;
begin
  NeedModel;
  TableName:=Trim(ArgStr(Args, 'name'));
  if(TableName='')then
    raise EToolError.Create('The argument "name" is missing.');
  if(Model.GetEERObjectByName(EERTable, TableName)<>nil)then
    raise EToolError.CreateFmt('The model has a table "%s" already.', [TableName]);

  Columns:=nil;
  if(Args.IndexOfName('columns')>=0)and(Args.Types['columns']=jtArray)then
    Columns:=Args.Arrays['columns'];

  Table:=Model.NewTable(ArgInt(Args, 'x', 40), ArgInt(Args, 'y', 40), False);
  try
    Table.ObjName:=TableName;
    Table.Comments:=ArgStr(Args, 'comments');

    if(Columns<>nil)then
      for i:=0 to Columns.Count-1 do
      begin
        if(Columns.Types[i]<>jtObject)then
          raise EToolError.Create('Every entry of "columns" has to be an object.');
        AddColumn(Table, Columns.Objects[i]);
      end;

    Table.CheckPrimaryIndex;
    //The size of the table is known now
    Table.RefreshObj;

    //Without a position: the nearest place where no other object is
    if(Args.IndexOfName('x')<0)or(Args.IndexOfName('y')<0)then
      PlaceWithRoom(Table);
    Table.RefreshObj;
  except
    Table.Free;
    raise;
  end;

  Model.ModelHasChanged;
  Result:=TableToJSON(Table);
end;

function ToolAddColumn(Args: TJSONObject): TJSONData;
var Table: TEERTable;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);

  AddColumn(Table, Args);

  Table.CheckPrimaryIndex;
  Table.RefreshObj;
  //A new primary key column goes to the tables that refer to this one
  Model.CheckAllRelations;

  Model.ModelHasChanged;
  Result:=TableToJSON(Table);
end;

procedure SetRefDef(Rel: TEERRel; Args: TJSONObject; OnDelete, OnUpdate: integer);
begin
  Rel.CreateRefDef:=ArgBool(Args, 'foreign_key_constraint', True);
  Rel.RefDef.Values['OnDelete']:=IntToStr(OnDelete);
  Rel.RefDef.Values['OnUpdate']:=IntToStr(OnUpdate);
end;

//The names of the foreign key columns of a new relation (primary key column
//of the parent = column of the child), found before the relation is made.
//The model takes the name of the primary key column (with the prefix and
//postfix of its settings) and uses a column of that name if the child has
//one: with a primary key "id" in both tables the primary key of the child
//would become the foreign key. Such a name gets the name of the parent
//table in front, and so do all names with WithTableName. ChildColumn names
//the column for a parent with one primary key column, also one the child
//has already
procedure ForeignKeyNames(Parent, Child: TEERTable; const ChildColumn: string;
  WithTableName: Boolean; Names: TStrings);
var i, PKCount: integer;
  PKName, FKName: string;
begin
  PKCount:=0;
  for i:=0 to Parent.Columns.Count-1 do
    if(TEERColumn(Parent.Columns[i]).PrimaryKey)then
      inc(PKCount);
  if(ChildColumn<>'')and(PKCount<>1)then
    raise EToolError.CreateFmt('"child_column" names one column, but the '+
      'primary key of "%s" has %d.', [Parent.ObjName, PKCount]);

  Names.Clear;
  for i:=0 to Parent.Columns.Count-1 do
    if(TEERColumn(Parent.Columns[i]).PrimaryKey)then
    begin
      PKName:=TEERColumn(Parent.Columns[i]).ColName;
      if(ChildColumn<>'')then
        FKName:=ChildColumn
      else
      begin
        FKName:=Model.FKPrefix+PKName+Model.FKPostfix;
        if(WithTableName)or(FindColumn(Child, FKName)<>nil)then
          FKName:=Parent.ObjName+'_'+PKName;
        if(FindColumn(Child, FKName)<>nil)then
          raise EToolError.CreateFmt('The table "%s" has a column "%s" already. '+
            'Name the foreign key column with "child_column".',
            [Child.ObjName, FKName]);
      end;
      Names.Add(PKName+'='+FKName);
    end;
end;

procedure SetForeignKeyNames(Rel: TEERRel; Names: TStrings);
var i: integer;
begin
  for i:=0 to Names.Count-1 do
    Rel.FKFields.Values[Names.Names[i]]:=Names.ValueFromIndex[i];
end;

//Two tables with a primary key column of the same name
function SharePrimaryKeyName(A, B: TEERTable): Boolean;
var i: integer;
  Column: TEERColumn;
begin
  Result:=False;
  for i:=0 to A.Columns.Count-1 do
    if(TEERColumn(A.Columns[i]).PrimaryKey)then
    begin
      Column:=FindColumn(B, TEERColumn(A.Columns[i]).ColName);
      if(Column<>nil)and(Column.PrimaryKey)then
        Result:=True;
    end;
end;

function ToolAddRelation(Args: TJSONObject): TJSONData;
var Parent, Child, JoinTable: TEERTable;
  Rel: TEERRel;
  Kind, OnDelete, OnUpdate: integer;
  JoinName: string;
  WithTableName: Boolean;
  Names: TStringList;
begin
  Parent:=NeedTable(ArgStr(Args, 'parent_table'));
  Child:=NeedTable(ArgStr(Args, 'child_table'));

  Kind:=IndexInList(RelKindNames, ArgStr(Args, 'kind', RelKindNames[rk_1nNonId]));
  if(Kind<0)or(Kind=rk_11Sub)then
    raise EToolError.Create('The argument "kind" has to be one of: 1:n, '+
      '1:n non-identifying, 1:1, 1:1 non-identifying, n:m.');
  OnDelete:=IndexInList(RefActionNames, ArgStr(Args, 'on_delete', 'NO ACTION'));
  OnUpdate:=IndexInList(RefActionNames, ArgStr(Args, 'on_update', 'NO ACTION'));
  if(OnDelete<0)or(OnUpdate<0)then
    raise EToolError.Create('"on_delete" and "on_update" have to be one of: '+
      'RESTRICT, CASCADE, SET NULL, NO ACTION, SET DEFAULT.');

  //The foreign key columns are the primary key columns of the parent
  if(Not(HasPrimaryKey(Parent)))then
    raise EToolError.CreateFmt('The table "%s" has no primary key, so nothing '+
      'can refer to it.', [Parent.ObjName]);

  if(Kind=rk_nm)then
  begin
    if(Not(HasPrimaryKey(Child)))then
      raise EToolError.CreateFmt('The table "%s" has no primary key, so nothing '+
        'can refer to it.', [Child.ObjName]);
    if(Parent=Child)then
      raise EToolError.Create('An n:m relation needs two different tables.');
    JoinName:=Parent.ObjName+'_has_'+Child.ObjName;
    if(Model.GetEERObjectByName(EERTable, JoinName)<>nil)then
      raise EToolError.CreateFmt('The model has a table "%s" already.', [JoinName]);

    //The table between the two, as the n:m tool of the program makes it
    JoinTable:=Model.NewTable(
      (Parent.Obj_X+Parent.Obj_W div 2+Child.Obj_X+Child.Obj_W div 2) div 2,
      (Parent.Obj_Y+Parent.Obj_H div 2+Child.Obj_Y+Child.Obj_H div 2) div 2, False);
    JoinTable.ObjName:=JoinName;
    JoinTable.SetnmTableStatus(True);

    WithTableName:=SharePrimaryKeyName(Parent, Child);
    Names:=TStringList.Create;
    try
      ForeignKeyNames(Parent, JoinTable, '', WithTableName, Names);
      Rel:=Model.NewRelation(rk_1n, Parent, JoinTable, False);
      SetRefDef(Rel, Args, OnDelete, OnUpdate);
      SetForeignKeyNames(Rel, Names);

      ForeignKeyNames(Child, JoinTable, '', WithTableName, Names);
      Rel:=Model.NewRelation(rk_1n, Child, JoinTable, False);
      SetRefDef(Rel, Args, OnDelete, OnUpdate);
      SetForeignKeyNames(Rel, Names);
    finally
      Names.Free;
    end;
    Model.CheckAllRelations;

    JoinTable.RefreshObj;
    PlaceWithRoom(JoinTable);
    JoinTable.RefreshObj;

    Model.ModelHasChanged;
    Result:=TJSONObject.Create(['join_table', TableToJSON(JoinTable)]);
    Exit;
  end;

  if(Parent=Child)and((Kind=rk_1n)or(Kind=rk_11))then
    raise EToolError.Create('A table cannot refer to itself with an identifying '+
      'relation. Use a non-identifying kind.');
  NeedChangeable(Child);

  Names:=TStringList.Create;
  try
    ForeignKeyNames(Parent, Child, Trim(ArgStr(Args, 'child_column')), False, Names);
    Rel:=Model.NewRelation(Kind, Parent, Child, False);
    SetForeignKeyNames(Rel, Names);
  finally
    Names.Free;
  end;
  if(Trim(ArgStr(Args, 'name'))<>'')then
    Rel.ObjName:=Trim(ArgStr(Args, 'name'));
  SetRefDef(Rel, Args, OnDelete, OnUpdate);
  Rel.Comments:=ArgStr(Args, 'comments');

  //Makes the foreign key columns in the child table
  Model.CheckAllRelations;

  Model.ModelHasChanged;
  Result:=TJSONObject.Create(['relation', RelationToJSON(Rel),
    'child_table', TableToJSON(Child)]);
end;

function NeedColumn(Table: TEERTable; const ColName: string): TEERColumn;
begin
  if(ColName='')then
    raise EToolError.Create('The argument "column" is missing.');
  Result:=FindColumn(Table, ColName);
  if(Result=nil)then
    raise EToolError.CreateFmt('The table "%s" has no column "%s".',
      [Table.ObjName, ColName]);
end;

function PrimaryKeyCount(Table: TEERTable): integer;
var i: integer;
begin
  Result:=0;
  for i:=0 to Table.Columns.Count-1 do
    if(TEERColumn(Table.Columns[i]).PrimaryKey)then
      inc(Result);
end;

//The relation that makes a foreign key column of the table
function RelationOfColumn(Table: TEERTable; Column: TEERColumn): TEERRel;
var i, j: integer;
begin
  Result:=nil;
  for i:=0 to Table.RelEnd.Count-1 do
    for j:=0 to TEERRel(Table.RelEnd[i]).FKFields.Count-1 do
      if(CompareText(TEERRel(Table.RelEnd[i]).FKFields.ValueFromIndex[j], Column.ColName)=0)then
        Result:=TEERRel(Table.RelEnd[i]);
end;

//After a change of the columns of a table: its primary index, the foreign
//key columns of the tables that refer to it, its size in the diagram
procedure TableChanged(Table: TEERTable);
begin
  Table.CheckPrimaryIndex;
  Table.RefreshRelations;
  Model.CheckAllRelations;
  Table.RefreshObj;
  Model.ModelHasChanged;
end;

function ToolRenameTable(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  NewName, OldName: string;
  Other: Pointer;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);
  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(NewName='')then
    raise EToolError.Create('The argument "new_name" is missing.');
  Other:=Model.GetEERObjectByName(EERTable, NewName);
  if(Other<>nil)and(Other<>Pointer(Table))then
    raise EToolError.CreateFmt('The model has a table "%s" already.', [NewName]);

  //The synchronisation renames the table in the database when it finds the
  //name the table had (as the table editor keeps it)
  OldName:=Table.ObjName;
  if(Table.PrevTableName='')then
    Table.PrevTableName:=OldName;
  Table.ObjName:=NewName;
  if(Table.PrevTableName=NewName)then
    Table.PrevTableName:='';

  Table.RefreshObj;
  Table.RefreshRelations;
  Model.ModelHasChanged;

  Result:=TableToJSON(Table);
  TJSONObject(Result).Add('renamed_from', U(OldName));
end;

function ToolChangeColumn(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  Column: TEERColumn;
  Datatype: TEERDatatype;
  Params, NewName, OldName: string;
  Options: TStringList;
  Rel: TEERRel;
  i, j: integer;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);
  Column:=NeedColumn(Table, ArgStr(Args, 'column'));

  if(Not(HasArg(Args, 'new_name') or HasArg(Args, 'datatype') or
    HasArg(Args, 'primary_key') or HasArg(Args, 'not_null') or
    HasArg(Args, 'auto_increment') or HasArg(Args, 'default') or
    HasArg(Args, 'comments')))then
    raise EToolError.Create('Nothing to change: give new_name, datatype, '+
      'primary_key, not_null, auto_increment, default or comments.');

  //Datatype and primary key of a foreign key column follow the relation
  if(Column.IsForeignKey)and(HasArg(Args, 'datatype') or HasArg(Args, 'primary_key'))then
    raise EToolError.CreateFmt('"%s" is a foreign key column: its datatype is '+
      'the one of the referenced column, and whether it is part of the primary '+
      'key is set by the kind of the relation.', [Column.ColName]);
  //Without a primary key the relations from this table have nothing to refer to
  if(HasArg(Args, 'primary_key'))and(Not(ArgBool(Args, 'primary_key', True)))and
    (Column.PrimaryKey)and(PrimaryKeyCount(Table)=1)and(Table.RelStart.Count>0)then
    raise EToolError.CreateFmt('"%s" is the only primary key column of "%s" and '+
      'relations refer to it. Delete the relations first.', [Column.ColName, Table.ObjName]);

  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(HasArg(Args, 'new_name'))then
  begin
    if(NewName='')then
      raise EToolError.Create('"new_name" is empty.');
    if(FindColumn(Table, NewName)<>nil)and(FindColumn(Table, NewName)<>Column)then
      raise EToolError.CreateFmt('The table "%s" has a column "%s" already.',
        [Table.ObjName, NewName]);
  end;

  //Check the datatype before anything is changed
  Options:=TStringList.Create;
  try
    Options.CaseSensitive:=False;
    if(HasArg(Args, 'datatype'))then
    begin
      ParseDatatype(ArgStr(Args, 'datatype'), Datatype, Params, Options);
      Column.idDatatype:=Datatype.id;
      Column.DatatypeParams:=Params;
      for i:=0 to High(Column.OptionSelected) do
        Column.OptionSelected[i]:=(i<Datatype.OptionCount)and
          (Options.IndexOf(Datatype.Options[i])>=0);
    end;
  finally
    Options.Free;
  end;

  if(NewName<>'')and(NewName<>Column.ColName)then
  begin
    //The synchronisation renames the column in the database when it finds
    //the name the column had
    OldName:=Column.ColName;
    if(Column.PrevColName='')then
      Column.PrevColName:=OldName;
    Column.ColName:=NewName;
    if(Column.PrevColName=NewName)then
      Column.PrevColName:='';

    //The relations know the columns by their names. A renamed primary key
    //column keeps the foreign key columns that refer to it, a renamed
    //foreign key column stays the column of its relation
    for i:=0 to Table.RelStart.Count-1 do
    begin
      Rel:=TEERRel(Table.RelStart[i]);
      for j:=0 to Rel.FKFields.Count-1 do
        if(CompareText(Rel.FKFields.Names[j], OldName)=0)then
          Rel.FKFields[j]:=NewName+'='+Rel.FKFields.ValueFromIndex[j];
    end;
    for i:=0 to Table.RelEnd.Count-1 do
    begin
      Rel:=TEERRel(Table.RelEnd[i]);
      for j:=0 to Rel.FKFields.Count-1 do
        if(CompareText(Rel.FKFields.ValueFromIndex[j], OldName)=0)then
          Rel.FKFields[j]:=Rel.FKFields.Names[j]+'='+NewName;
    end;
  end;

  if(HasArg(Args, 'primary_key'))then
    Column.PrimaryKey:=ArgBool(Args, 'primary_key', Column.PrimaryKey);
  if(HasArg(Args, 'not_null'))then
    Column.NotNull:=ArgBool(Args, 'not_null', Column.NotNull);
  if(Column.PrimaryKey)then
    Column.NotNull:=True;
  if(HasArg(Args, 'auto_increment'))then
    Column.AutoInc:=ArgBool(Args, 'auto_increment', Column.AutoInc);
  if(HasArg(Args, 'default'))then
    Column.DefaultValue:=ArgStr(Args, 'default');
  if(HasArg(Args, 'comments'))then
    Column.Comments:=ArgStr(Args, 'comments');

  TableChanged(Table);
  Result:=TableToJSON(Table);
end;

function ToolDeleteColumn(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  Column: TEERColumn;
  Rel: TEERRel;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);
  Column:=NeedColumn(Table, ArgStr(Args, 'column'));

  if(Column.IsForeignKey)then
  begin
    Rel:=RelationOfColumn(Table, Column);
    if(Rel<>nil)then
      raise EToolError.CreateFmt('"%s" is the foreign key column of the relation '+
        '"%s" (%s -> %s). Delete the relation with delete_relation, the column '+
        'goes with it.', [Column.ColName, Rel.ObjName, Rel.SrcTbl.ObjName, Rel.DestTbl.ObjName]);
  end;
  if(Column.PrimaryKey)and(PrimaryKeyCount(Table)=1)and(Table.RelStart.Count>0)then
    raise EToolError.CreateFmt('"%s" is the only primary key column of "%s" and '+
      'relations refer to it. Delete the relations first.', [Column.ColName, Table.ObjName]);

  //Takes the column out of the indices as well
  Table.DeleteColumn(Table.Columns.IndexOf(Column));

  TableChanged(Table);
  Result:=TableToJSON(Table);
end;

function ToolDeleteTable(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  Rels: TJSONArray;
  TableName: string;
  i: integer;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  TableName:=Table.ObjName;

  //The relations from and to the table go with it, and with them the
  //foreign key columns in the other tables
  Rels:=TJSONArray.Create;
  for i:=0 to Table.RelStart.Count-1 do
    Rels.Add(RelationToJSON(TEERRel(Table.RelStart[i])));
  for i:=0 to Table.RelEnd.Count-1 do
    if(TEERRel(Table.RelEnd[i]).SrcTbl<>Table)then
      Rels.Add(RelationToJSON(TEERRel(Table.RelEnd[i])));

  Table.DeleteObj;
  Model.CheckAllRelations;
  Model.ModelHasChanged;

  Result:=TJSONObject.Create(['deleted_table', U(TableName),
    'deleted_relations', Rels,
    'tables_in_model', Model.GetEERObjectCount([EERTable])]);
end;

function ToolDeleteRelation(Args: TJSONObject): TJSONData;
var Rels: TList;
  Rel, Found: TEERRel;
  Child: TEERTable;
  Column: TEERColumn;
  RelName, List: string;
  Parent, ChildFilter: TEERTable;
  Info: TJSONObject;
  Count, i: integer;
begin
  NeedModel;
  RelName:=Trim(ArgStr(Args, 'name'));
  Parent:=nil;
  ChildFilter:=nil;
  if(ArgStr(Args, 'parent_table')<>'')then
    Parent:=NeedTable(ArgStr(Args, 'parent_table'));
  if(ArgStr(Args, 'child_table')<>'')then
    ChildFilter:=NeedTable(ArgStr(Args, 'child_table'));
  if(RelName='')and(Parent=nil)and(ChildFilter=nil)then
    raise EToolError.Create('Name the relation: "name", or "parent_table" and '+
      '"child_table". list_relations shows the relations.');

  Found:=nil;
  Count:=0;
  List:='';
  Rels:=GetObjects(EERRelation);
  try
    for i:=0 to Rels.Count-1 do
    begin
      Rel:=Rels[i];
      if((RelName='')or(CompareText(Rel.ObjName, RelName)=0))and
        ((Parent=nil)or(Rel.SrcTbl=Parent))and
        ((ChildFilter=nil)or(Rel.DestTbl=ChildFilter))then
      begin
        Found:=Rel;
        inc(Count);
        List:=List+IfThen(Count>1, ', ')+Rel.ObjName+' ('+Rel.SrcTbl.ObjName+
          ' -> '+Rel.DestTbl.ObjName+')';
      end;
    end;
  finally
    Rels.Free;
  end;
  if(Count=0)then
    raise EToolError.Create('There is no such relation. list_relations shows the relations.');
  if(Count>1)then
    raise EToolError.Create('More than one relation fits: '+List+
      '. Give "name" together with "parent_table" and "child_table".');

  Child:=Found.DestTbl;
  Info:=RelationToJSON(Found);

  //The model removes the foreign key columns that have no relation any
  //more. To keep them they become ordinary columns first
  if(ArgBool(Args, 'keep_columns', False))then
    for i:=0 to Found.FKFields.Count-1 do
    begin
      Column:=FindColumn(Child, Found.FKFields.ValueFromIndex[i]);
      if(Column<>nil)then
        Column.IsForeignKey:=False;
    end;

  //Checks all relations and refreshes the tables
  Found.DeleteObj;
  Model.ModelHasChanged;

  Result:=TJSONObject.Create(['deleted_relation', Info,
    'child_table', TableToJSON(Child)]);
end;

function ToolAddIndex(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  Cols: TJSONArray;
  Column: TEERColumn;
  Index: TEERIndex;
  IndexName: string;
  Kind, ID, i: integer;
  IDs: TStringList;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);

  Cols:=nil;
  if(HasArg(Args, 'columns'))and(Args.Types['columns']=jtArray)then
    Cols:=Args.Arrays['columns'];
  if(Cols=nil)or(Cols.Count=0)then
    raise EToolError.Create('"columns" has to name at least one column.');

  Kind:=IndexInList(IndexKindNames, ArgStr(Args, 'kind', 'INDEX'));
  if(Kind<=ik_PRIMARY)then
    raise EToolError.Create('"kind" has to be INDEX, UNIQUE or FULLTEXT. The '+
      'primary index is made from the primary key columns.');

  ID:=DMMain.GetNextGlobalID;
  IndexName:=Trim(ArgStr(Args, 'name'));
  //The name the table editor proposes
  if(IndexName='')then
    IndexName:=Table.ObjName+'_index'+IntToStr(ID);
  if(CompareText(IndexName, 'PRIMARY')=0)then
    raise EToolError.Create('PRIMARY is the name of the primary index.');
  for i:=0 to Table.Indices.Count-1 do
    if(CompareText(TEERIndex(Table.Indices[i]).IndexName, IndexName)=0)then
      raise EToolError.CreateFmt('The table "%s" has an index "%s" already.',
        [Table.ObjName, IndexName]);

  IDs:=TStringList.Create;
  try
    for i:=0 to Cols.Count-1 do
    begin
      if(Cols.Types[i]<>jtString)then
        raise EToolError.Create('"columns" has to be a list of column names.');
      Column:=NeedColumn(Table, Cols.Strings[i]);
      if(IDs.IndexOf(IntToStr(Column.Obj_id))>=0)then
        raise EToolError.CreateFmt('The column "%s" is named twice.', [Column.ColName]);
      IDs.Add(IntToStr(Column.Obj_id));
    end;

    Index:=TEERIndex.Create(Table);
    Index.Obj_id:=ID;
    Index.IndexName:=IndexName;
    Index.IndexKind:=Kind;
    Index.Columns.Assign(IDs);
    Table.Indices.Add(Index);
    Index.Pos:=Table.Indices.Count-1;
  finally
    IDs.Free;
  end;

  Table.RefreshObj;
  Model.ModelHasChanged;
  Result:=TableToJSON(Table);
end;

function ToolDeleteIndex(Args: TJSONObject): TJSONData;
var Table: TEERTable;
  Index: TEERIndex;
  IndexName: string;
  i, Found: integer;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  NeedChangeable(Table);
  IndexName:=Trim(ArgStr(Args, 'index'));
  if(IndexName='')then
    raise EToolError.Create('The argument "index" is missing.');

  Found:=-1;
  for i:=0 to Table.Indices.Count-1 do
    if(CompareText(TEERIndex(Table.Indices[i]).IndexName, IndexName)=0)then
      Found:=i;
  if(Found<0)then
    raise EToolError.CreateFmt('The table "%s" has no index "%s". describe_table '+
      'shows its indices.', [Table.ObjName, IndexName]);

  Index:=TEERIndex(Table.Indices[Found]);
  if(Index.IndexKind=ik_PRIMARY)then
    raise EToolError.Create('The primary index follows the primary key columns: '+
      'change them with change_column.');
  if(Index.FKRefDef_Obj_id>-1)then
    raise EToolError.Create('This index belongs to a foreign key and goes with '+
      'its relation (delete_relation).');

  Table.Indices.Delete(Found);
  for i:=0 to Table.Indices.Count-1 do
    TEERIndex(Table.Indices[i]).Pos:=i;

  Table.RefreshObj;
  Model.ModelHasChanged;
  Result:=TableToJSON(Table);
end;

// ---------------------------------------------------------------------------
// Diagram: positions, regions, notes

//An object has to lie inside the canvas of the model
procedure NeedInsideCanvas(x, y, w, h: integer);
begin
  if(x<0)or(y<0)or(x+w>Model.EERModel_Width)or(y+h>Model.EERModel_Height)then
    raise EToolError.CreateFmt('The place %d, %d with the size %d x %d is outside '+
      'of the canvas of the model (%d x %d).',
      [x, y, w, h, Model.EERModel_Width, Model.EERModel_Height]);
end;

function ToolMoveTable(Args: TJSONObject): TJSONData;
var Table: TEERTable;
begin
  Table:=NeedTable(ArgStr(Args, 'table'));
  if(Not(HasArg(Args, 'x')))or(Not(HasArg(Args, 'y')))then
    raise EToolError.Create('The arguments "x" and "y" are missing.');
  NeedInsideCanvas(ArgInt(Args, 'x', 0), ArgInt(Args, 'y', 0), Table.Obj_W, Table.Obj_H);

  Table.Obj_X:=ArgInt(Args, 'x', 0);
  Table.Obj_Y:=ArgInt(Args, 'y', 0);
  Table.RefreshObj;
  //The lines of the relations follow
  Table.RefreshRelations;
  Model.ModelHasChanged;

  Result:=TJSONObject.Create(['name', U(Table.ObjName),
    'position', PositionToJSON(Table)]);
  if(Table.GetRegion<>nil)then
    TJSONObject(Result).Add('region', U(TEERRegion(Table.GetRegion).ObjName));
end;

//Tables side by side in rows, each row as high as its highest table. For
//a model that was built without positions, or whose tables have grown
//over each other
function ToolArrangeTables(Args: TJSONObject): TJSONData;
var Tables: TList;
  Names: TJSONArray;
  Table: TEERTable;
  Item: TJSONObject;
  x0, y0, RowWidth, x, y, RowHeight, i: integer;
begin
  NeedModel;
  x0:=ArgInt(Args, 'x', 40);
  y0:=ArgInt(Args, 'y', 40);
  RowWidth:=ArgInt(Args, 'row_width', 1400);
  if(RowWidth<200)then
    raise EToolError.Create('"row_width" is at least 200.');

  Tables:=TList.Create;
  try
    Names:=nil;
    if(HasArg(Args, 'tables'))and(Args.Types['tables']=jtArray)then
      Names:=Args.Arrays['tables'];
    if(Names<>nil)and(Names.Count>0)then
    begin
      for i:=0 to Names.Count-1 do
      begin
        if(Names.Types[i]<>jtString)then
          raise EToolError.Create('"tables" has to be a list of table names.');
        Table:=NeedTable(Names.Strings[i]);
        if(Tables.IndexOf(Table)<0)then
          Tables.Add(Table);
      end;
    end
    else
    begin
      //The regions hold the tables that lie in them: all tables in rows
      //would take them out of their regions
      if(Model.GetEERObjectCount([EERRegion])>0)then
        raise EToolError.Create('The model has regions, and a table belongs to the '+
          'region it lies in. Name the tables to arrange with "tables" and give '+
          'the place with "x" and "y" (list_regions shows the regions).');
      Model.GetEERObjectList([EERTable], Tables);
      //A table comes after the tables it refers to
      Model.SortEERObjectListByObjName(Tables);
      try
        Model.SortEERTableListByForeignKeyReferences(Tables);
      except
        //Circular relations: the order by name stays
      end;
    end;
    if(Tables.Count=0)then
      raise EToolError.Create('The model has no tables.');

    //Check the whole arrangement before a table is moved
    x:=x0;
    y:=y0;
    RowHeight:=0;
    for i:=0 to Tables.Count-1 do
    begin
      Table:=Tables[i];
      if(x>x0)and(x+Table.Obj_W>x0+RowWidth)then
      begin
        x:=x0;
        y:=y+RowHeight+PlaceGapY;
        RowHeight:=0;
      end;
      NeedInsideCanvas(x, y, Table.Obj_W, Table.Obj_H);
      if(Table.Obj_H>RowHeight)then
        RowHeight:=Table.Obj_H;
      x:=x+Table.Obj_W+PlaceGapX;
    end;

    Result:=TJSONArray.Create;
    x:=x0;
    y:=y0;
    RowHeight:=0;
    for i:=0 to Tables.Count-1 do
    begin
      Table:=Tables[i];
      if(x>x0)and(x+Table.Obj_W>x0+RowWidth)then
      begin
        x:=x0;
        y:=y+RowHeight+PlaceGapY;
        RowHeight:=0;
      end;
      Table.Obj_X:=x;
      Table.Obj_Y:=y;
      Table.RefreshObj;
      if(Table.Obj_H>RowHeight)then
        RowHeight:=Table.Obj_H;
      x:=x+Table.Obj_W+PlaceGapX;
    end;
    //The lines of the relations, when all tables have their places
    for i:=0 to Tables.Count-1 do
    begin
      Table:=Tables[i];
      Table.RefreshRelations;
      Item:=TJSONObject.Create(['name', U(Table.ObjName),
        'position', PositionToJSON(Table)]);
      if(Table.GetRegion<>nil)then
        Item.Add('region', U(TEERRegion(Table.GetRegion).ObjName));
      TJSONArray(Result).Add(Item);
    end;
  finally
    Tables.Free;
  end;
  Model.ModelHasChanged;
end;

function NeedRegion(const RegionName: string): TEERRegion;
begin
  NeedModel;
  if(RegionName='')then
    raise EToolError.Create('The argument "region" is missing.');
  Result:=Model.GetEERObjectByName(EERRegion, RegionName);
  if(Result=nil)then
    raise EToolError.CreateFmt('There is no region "%s" in the model. '+
      'list_regions shows the regions.', [RegionName]);
end;

function RegionColorName(Region: TEERRegion): string;
begin
  if(Region.RegionColor>=0)and(Region.RegionColor<Model.RegionColors.Count)then
    Result:=Model.RegionColors.Names[Region.RegionColor]
  else
    Result:=IntToStr(Region.RegionColor);
end;

//The names of the colours the model has for its regions
function RegionColorNames: string;
var i: integer;
begin
  Result:='';
  for i:=0 to Model.RegionColors.Count-1 do
    Result:=Result+IfThen(i>0, ', ')+Model.RegionColors.Names[i];
end;

procedure SetRegionColor(Region: TEERRegion; const ColorName: string);
var i, Found: integer;
begin
  Found:=-1;
  for i:=0 to Model.RegionColors.Count-1 do
    if(CompareText(Model.RegionColors.Names[i], ColorName)=0)then
      Found:=i;
  if(Found<0)then
    raise EToolError.CreateFmt('The model has no region colour "%s". Its colours: %s',
      [ColorName, RegionColorNames]);
  Region.RegionColor:=Found;
end;

//A region holds the objects that lie completely inside of it
function RegionToJSON(Region: TEERRegion): TJSONObject;
var Tables: TList;
  Names: TJSONArray;
  i: integer;
begin
  Names:=TJSONArray.Create;
  Tables:=TList.Create;
  try
    Region.GetEERObjsInRegion([EERTable], Tables);
    Model.SortEERObjectListByObjName(Tables);
    for i:=0 to Tables.Count-1 do
      Names.Add(U(TEERTable(Tables[i]).ObjName));
  finally
    Tables.Free;
  end;

  Result:=TJSONObject.Create(['name', U(Region.ObjName),
    'position', PositionToJSON(Region),
    'color', U(RegionColorName(Region)),
    'tables', Names]);
  if(Region.Comments<>'')then
    Result.Add('comments', U(Region.Comments));
end;

function ToolListRegions(Args: TJSONObject): TJSONData;
var Regions: TList;
  i: integer;
begin
  NeedModel;
  Result:=TJSONArray.Create;
  Regions:=GetObjects(EERRegion);
  try
    for i:=0 to Regions.Count-1 do
      TJSONArray(Result).Add(RegionToJSON(TEERRegion(Regions[i])));
  finally
    Regions.Free;
  end;
end;

function ToolAddRegion(Args: TJSONObject): TJSONData;
const
  //Space around the tables, and for the name of the region above them
  Margin = 20;
  TitleHeight = 20;
var Region: TEERRegion;
  Names: TJSONArray;
  Table: TEERTable;
  RegionName: string;
  x, y, w, h, x2, y2, i: integer;
begin
  NeedModel;
  RegionName:=Trim(ArgStr(Args, 'name'));
  if(RegionName<>'')and(Model.GetEERObjectByName(EERRegion, RegionName)<>nil)then
    raise EToolError.CreateFmt('The model has a region "%s" already.', [RegionName]);

  Names:=nil;
  if(HasArg(Args, 'tables'))and(Args.Types['tables']=jtArray)then
    Names:=Args.Arrays['tables'];
  if(Names<>nil)and(Names.Count>0)then
  begin
    //The rectangle around the tables
    x:=MaxInt;
    y:=MaxInt;
    x2:=0;
    y2:=0;
    for i:=0 to Names.Count-1 do
    begin
      if(Names.Types[i]<>jtString)then
        raise EToolError.Create('"tables" has to be a list of table names.');
      Table:=NeedTable(Names.Strings[i]);
      if(Table.Obj_X<x)then x:=Table.Obj_X;
      if(Table.Obj_Y<y)then y:=Table.Obj_Y;
      if(Table.Obj_X+Table.Obj_W>x2)then x2:=Table.Obj_X+Table.Obj_W;
      if(Table.Obj_Y+Table.Obj_H>y2)then y2:=Table.Obj_Y+Table.Obj_H;
    end;
    x:=x-Margin;
    y:=y-Margin-TitleHeight;
    if(x<0)then x:=0;
    if(y<0)then y:=0;
    w:=x2+Margin-x;
    h:=y2+Margin-y;
    if(x+w>Model.EERModel_Width)then w:=Model.EERModel_Width-x;
    if(y+h>Model.EERModel_Height)then h:=Model.EERModel_Height-y;
  end
  else
  begin
    if(Not(HasArg(Args, 'x') and HasArg(Args, 'y') and HasArg(Args, 'width') and
      HasArg(Args, 'height')))then
      raise EToolError.Create('Give "tables" (the region is laid around them) or '+
        '"x", "y", "width" and "height".');
    x:=ArgInt(Args, 'x', 0);
    y:=ArgInt(Args, 'y', 0);
    w:=ArgInt(Args, 'width', 0);
    h:=ArgInt(Args, 'height', 0);
  end;
  if(w<20)or(h<20)then
    raise EToolError.Create('A region is at least 20 wide and 20 high.');
  NeedInsideCanvas(x, y, w, h);

  Region:=Model.NewRegion(x, y, w, h, False);
  if(Region=nil)then
    raise EToolError.Create('The region could not be made.');
  try
    if(RegionName<>'')then
      Region.ObjName:=RegionName;
    if(ArgStr(Args, 'color')<>'')then
      SetRegionColor(Region, ArgStr(Args, 'color'));
    Region.Comments:=ArgStr(Args, 'comments');
  except
    Region.Free;
    raise;
  end;
  Region.RefreshObj;
  Model.ModelHasChanged;

  Result:=RegionToJSON(Region);
end;

function ToolChangeRegion(Args: TJSONObject): TJSONData;
var Region: TEERRegion;
  NewName: string;
  Other: Pointer;
  x, y, w, h: integer;
begin
  Region:=NeedRegion(ArgStr(Args, 'region'));
  if(Not(HasArg(Args, 'new_name') or HasArg(Args, 'x') or HasArg(Args, 'y') or
    HasArg(Args, 'width') or HasArg(Args, 'height') or HasArg(Args, 'color') or
    HasArg(Args, 'comments')))then
    raise EToolError.Create('Nothing to change: give new_name, x, y, width, '+
      'height, color or comments.');

  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(HasArg(Args, 'new_name'))then
  begin
    if(NewName='')then
      raise EToolError.Create('"new_name" is empty.');
    Other:=Model.GetEERObjectByName(EERRegion, NewName);
    if(Other<>nil)and(Other<>Pointer(Region))then
      raise EToolError.CreateFmt('The model has a region "%s" already.', [NewName]);
  end;

  x:=ArgInt(Args, 'x', Region.Obj_X);
  y:=ArgInt(Args, 'y', Region.Obj_Y);
  w:=ArgInt(Args, 'width', Region.Obj_W);
  h:=ArgInt(Args, 'height', Region.Obj_H);
  if(w<20)or(h<20)then
    raise EToolError.Create('A region is at least 20 wide and 20 high.');
  NeedInsideCanvas(x, y, w, h);
  if(HasArg(Args, 'color'))then
    SetRegionColor(Region, ArgStr(Args, 'color'));

  if(NewName<>'')then
    Region.ObjName:=NewName;
  Region.Obj_X:=x;
  Region.Obj_Y:=y;
  Region.Obj_W:=w;
  Region.Obj_H:=h;
  if(HasArg(Args, 'comments'))then
    Region.Comments:=ArgStr(Args, 'comments');

  Region.RefreshObj;
  Model.ModelHasChanged;
  Result:=RegionToJSON(Region);
end;

function ToolDeleteRegion(Args: TJSONObject): TJSONData;
var Region: TEERRegion;
begin
  Region:=NeedRegion(ArgStr(Args, 'region'));
  //The tables in it stay where they are
  Result:=TJSONObject.Create(['deleted_region', RegionToJSON(Region)]);
  Region.DeleteObj;
  Model.ModelHasChanged;
end;

function NeedNote(const NoteName: string): TEERNote;
begin
  NeedModel;
  if(NoteName='')then
    raise EToolError.Create('The argument "note" is missing.');
  Result:=Model.GetEERObjectByName(EERNote, NoteName);
  if(Result=nil)then
    raise EToolError.CreateFmt('There is no note "%s" in the model. '+
      'list_notes shows the notes.', [NoteName]);
end;

function NoteToJSON(Note: TEERNote): TJSONObject;
begin
  Result:=TJSONObject.Create(['name', U(Note.ObjName),
    'text', U(TrimRight(StringReplace(Note.GetNoteText, #13#10, #10, [rfReplaceAll]))),
    'position', PositionToJSON(Note)]);
  if(Note.GetRegion<>nil)then
    Result.Add('region', U(TEERRegion(Note.GetRegion).ObjName));
end;

function ToolListNotes(Args: TJSONObject): TJSONData;
var Notes: TList;
  i: integer;
begin
  NeedModel;
  Result:=TJSONArray.Create;
  Notes:=GetObjects(EERNote);
  try
    for i:=0 to Notes.Count-1 do
      TJSONArray(Result).Add(NoteToJSON(TEERNote(Notes[i])));
  finally
    Notes.Free;
  end;
end;

function ToolAddNote(Args: TJSONObject): TJSONData;
var Note: TEERNote;
  NoteName: string;
begin
  NeedModel;
  if(Trim(ArgStr(Args, 'text'))='')then
    raise EToolError.Create('The argument "text" is missing.');
  NoteName:=Trim(ArgStr(Args, 'name'));
  if(NoteName<>'')and(Model.GetEERObjectByName(EERNote, NoteName)<>nil)then
    raise EToolError.CreateFmt('The model has a note "%s" already.', [NoteName]);

  Note:=Model.NewNote(ArgInt(Args, 'x', 40), ArgInt(Args, 'y', 40), False);
  try
    if(NoteName<>'')then
      Note.ObjName:=NoteName;
    Note.SetNoteText(ArgStr(Args, 'text'));
    //The size of the note comes from its text
    Note.RefreshObj;

    //Without a position: the nearest place where no other object is
    if(Not(HasArg(Args, 'x')))or(Not(HasArg(Args, 'y')))then
      with Model.GetFreeObjPos(Note.Obj_X, Note.Obj_Y, Note.Obj_W, Note.Obj_H, Note) do
      begin
        Note.Obj_X:=X;
        Note.Obj_Y:=Y;
      end;
    NeedInsideCanvas(Note.Obj_X, Note.Obj_Y, Note.Obj_W, Note.Obj_H);
    Note.RefreshObj;
  except
    Note.Free;
    raise;
  end;
  Model.ModelHasChanged;

  Result:=NoteToJSON(Note);
end;

function ToolChangeNote(Args: TJSONObject): TJSONData;
var Note: TEERNote;
  NewName, OldText: string;
  Other: Pointer;
  x, y: integer;
begin
  Note:=NeedNote(ArgStr(Args, 'note'));
  if(Not(HasArg(Args, 'new_name') or HasArg(Args, 'text') or HasArg(Args, 'x') or
    HasArg(Args, 'y')))then
    raise EToolError.Create('Nothing to change: give new_name, text, x or y.');

  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(HasArg(Args, 'new_name'))then
  begin
    if(NewName='')then
      raise EToolError.Create('"new_name" is empty.');
    Other:=Model.GetEERObjectByName(EERNote, NewName);
    if(Other<>nil)and(Other<>Pointer(Note))then
      raise EToolError.CreateFmt('The model has a note "%s" already.', [NewName]);
  end;
  if(HasArg(Args, 'text'))and(Trim(ArgStr(Args, 'text'))='')then
    raise EToolError.Create('"text" is empty. delete_note removes a note.');

  x:=ArgInt(Args, 'x', Note.Obj_X);
  y:=ArgInt(Args, 'y', Note.Obj_Y);
  OldText:=Note.GetNoteText;
  if(HasArg(Args, 'text'))then
  begin
    Note.SetNoteText(ArgStr(Args, 'text'));
    Note.RefreshObj;
  end;
  try
    NeedInsideCanvas(x, y, Note.Obj_W, Note.Obj_H);
  except
    Note.SetNoteText(OldText);
    Note.RefreshObj;
    raise;
  end;

  if(NewName<>'')then
    Note.ObjName:=NewName;
  Note.Obj_X:=x;
  Note.Obj_Y:=y;
  Note.RefreshObj;
  Model.ModelHasChanged;
  Result:=NoteToJSON(Note);
end;

function ToolDeleteNote(Args: TJSONObject): TJSONData;
var Note: TEERNote;
begin
  Note:=NeedNote(ArgStr(Args, 'note'));
  Result:=TJSONObject.Create(['deleted_note', NoteToJSON(Note)]);
  Note.DeleteObj;
  Model.ModelHasChanged;
end;

// ---------------------------------------------------------------------------
// Images

function NeedImage(const ImageName: string): TEERImage;
begin
  NeedModel;
  if(ImageName='')then
    raise EToolError.Create('The argument "image" is missing.');
  Result:=Model.GetEERObjectByName(EERImage, ImageName);
  if(Result=nil)then
    raise EToolError.CreateFmt('There is no image "%s" in the model. '+
      'list_images shows the images.', [ImageName]);
end;

function ImageToJSON(Image: TEERImage): TJSONObject;
begin
  Result:=TJSONObject.Create(['name', U(Image.ObjName),
    'position', PositionToJSON(Image),
    'picture_width', Image.GetImgSize.cx,
    'picture_height', Image.GetImgSize.cy,
    'stretch', Image.GetStrechImg]);
  if(Image.GetRegion<>nil)then
    Result.Add('region', U(TEERRegion(Image.GetRegion).ObjName));
end;

//The picture of an image from a PNG or BMP file
procedure LoadPicture(Image: TEERImage; const FileName: string);
var Stream: TFileStream;
begin
  if(Not(FileExists(FileName)))then
    raise EToolError.CreateFmt('The file "%s" does not exist.', [FileName]);
  Stream:=TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    try
      Image.LoadImgFromStream(Stream);
    except
      on E: Exception do
        raise EToolError.CreateFmt('The file "%s" could not be read as a picture '+
          '(PNG or BMP): %s', [FileName, E.Message]);
    end;
  finally
    Stream.Free;
  end;
  if(Image.GetImgSize.cx<1)or(Image.GetImgSize.cy<1)then
    raise EToolError.CreateFmt('The file "%s" holds no picture.', [FileName]);
end;

//Width and height from the arguments. With one of them the other follows
//the proportions of the picture, with none it is the size of the picture
procedure ImageSizeFromArgs(Image: TEERImage; Args: TJSONObject; out w, h: integer);
var Size: TSize;
begin
  Size:=Image.GetImgSize;
  w:=ArgInt(Args, 'width', 0);
  h:=ArgInt(Args, 'height', 0);
  if(HasArg(Args, 'width'))and(Not(HasArg(Args, 'height')))and(Size.cx>0)then
    h:=Round(w*Size.cy/Size.cx)
  else if(HasArg(Args, 'height'))and(Not(HasArg(Args, 'width')))and(Size.cy>0)then
    w:=Round(h*Size.cx/Size.cy)
  else if(Not(HasArg(Args, 'width')))and(Not(HasArg(Args, 'height')))then
  begin
    w:=Size.cx;
    h:=Size.cy;
  end;
  if(w<2)or(h<2)then
    raise EToolError.Create('An image is at least 2 wide and 2 high.');
end;

function ToolListImages(Args: TJSONObject): TJSONData;
var Images: TList;
  i: integer;
begin
  NeedModel;
  Result:=TJSONArray.Create;
  Images:=GetObjects(EERImage);
  try
    for i:=0 to Images.Count-1 do
      TJSONArray(Result).Add(ImageToJSON(TEERImage(Images[i])));
  finally
    Images.Free;
  end;
end;

function ToolAddImage(Args: TJSONObject): TJSONData;
var Image: TEERImage;
  ImageName: string;
  w, h: integer;
begin
  NeedModel;
  if(ArgStr(Args, 'path')='')then
    raise EToolError.Create('The argument "path" is missing.');
  ImageName:=Trim(ArgStr(Args, 'name'));
  if(ImageName<>'')and(Model.GetEERObjectByName(EERImage, ImageName)<>nil)then
    raise EToolError.CreateFmt('The model has an image "%s" already.', [ImageName]);

  Image:=Model.NewImage(ArgInt(Args, 'x', 40), ArgInt(Args, 'y', 40), 0, 0, False);
  try
    LoadPicture(Image, ExpandFileName(ArgStr(Args, 'path')));
    if(ImageName<>'')then
      Image.ObjName:=ImageName;
    Image.SetStrechImg(ArgBool(Args, 'stretch', True));
    ImageSizeFromArgs(Image, Args, w, h);
    Image.Obj_W:=w;
    Image.Obj_H:=h;

    //Without a position: the nearest place where no other object is
    if(Not(HasArg(Args, 'x')))or(Not(HasArg(Args, 'y')))then
      with Model.GetFreeObjPos(Image.Obj_X, Image.Obj_Y, w, h, Image) do
      begin
        Image.Obj_X:=X;
        Image.Obj_Y:=Y;
      end;
    NeedInsideCanvas(Image.Obj_X, Image.Obj_Y, w, h);
    Image.RefreshObj;
  except
    Image.Free;
    raise;
  end;
  Model.ModelHasChanged;

  Result:=ImageToJSON(Image);
end;

function ToolChangeImage(Args: TJSONObject): TJSONData;
var Image: TEERImage;
  NewName: string;
  Other: Pointer;
  x, y, w, h: integer;
begin
  Image:=NeedImage(ArgStr(Args, 'image'));
  if(Not(HasArg(Args, 'new_name') or HasArg(Args, 'path') or HasArg(Args, 'x') or
    HasArg(Args, 'y') or HasArg(Args, 'width') or HasArg(Args, 'height') or
    HasArg(Args, 'stretch')))then
    raise EToolError.Create('Nothing to change: give new_name, path, x, y, '+
      'width, height or stretch.');

  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(HasArg(Args, 'new_name'))then
  begin
    if(NewName='')then
      raise EToolError.Create('"new_name" is empty.');
    Other:=Model.GetEERObjectByName(EERImage, NewName);
    if(Other<>nil)and(Other<>Pointer(Image))then
      raise EToolError.CreateFmt('The model has an image "%s" already.', [NewName]);
  end;

  x:=ArgInt(Args, 'x', Image.Obj_X);
  y:=ArgInt(Args, 'y', Image.Obj_Y);
  w:=Image.Obj_W;
  h:=Image.Obj_H;
  if(HasArg(Args, 'width'))or(HasArg(Args, 'height'))then
    ImageSizeFromArgs(Image, Args, w, h);
  NeedInsideCanvas(x, y, w, h);

  //Another picture in the place of the one the image has
  if(HasArg(Args, 'path'))then
    LoadPicture(Image, ExpandFileName(ArgStr(Args, 'path')));

  if(NewName<>'')then
    Image.ObjName:=NewName;
  if(HasArg(Args, 'stretch'))then
    Image.SetStrechImg(ArgBool(Args, 'stretch', True));
  Image.Obj_X:=x;
  Image.Obj_Y:=y;
  Image.Obj_W:=w;
  Image.Obj_H:=h;
  Image.RefreshObj;
  Model.ModelHasChanged;

  Result:=ImageToJSON(Image);
end;

function ToolDeleteImage(Args: TJSONObject): TJSONData;
var Image: TEERImage;
begin
  Image:=NeedImage(ArgStr(Args, 'image'));
  Result:=TJSONObject.Create(['deleted_image', ImageToJSON(Image)]);
  Image.DeleteObj;
  Model.ModelHasChanged;
end;

//The diagram as the program exports it (File > Export > as Image): the
//area of the objects at a zoom of 100 percent
function ToolExportModelImage(Args: TJSONObject): TJSONData;
var FileName, Ext: string;
  Bmp: TBitmap;
begin
  NeedModel;
  if(ArgStr(Args, 'path')='')then
    raise EToolError.Create('The argument "path" is missing.');
  FileName:=ExpandFileName(ArgStr(Args, 'path'));
  Ext:=LowerCase(ExtractFileExt(FileName));
  if(Ext<>'.png')and(Ext<>'.jpg')and(Ext<>'.jpeg')and(Ext<>'.bmp')then
    raise EToolError.Create('The file name has to end with .png, .jpg or .bmp.');
  if(FileExists(FileName))and(Not(ArgBool(Args, 'overwrite', False)))then
    raise EToolError.CreateFmt('The file "%s" exists. Set "overwrite" to '+
      'true to replace it.', [FileName]);

  Bmp:=TBitmap.Create;
  try
    Model.PaintModelToImage(Bmp);
    DMMain.SaveBitmap(Bmp, FileName, Ext);
    Result:=TJSONObject.Create(['file', U(FileName),
      'width', Bmp.Width, 'height', Bmp.Height]);
  finally
    Bmp.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Datatypes of the model

function DatatypeGroupName(Group: integer): string;
begin
  if(Group>=0)and(Group<Model.DatatypeGroups.Count)then
    Result:=TEERDatatypeGroup(Model.DatatypeGroups[Group]).GroupName
  else
    Result:=IntToStr(Group);
end;

function DatatypeGroupNames: string;
var i: integer;
begin
  Result:='';
  for i:=0 to Model.DatatypeGroups.Count-1 do
    Result:=Result+IfThen(i>0, ', ')+TEERDatatypeGroup(Model.DatatypeGroups[i]).GroupName;
end;

//The number of columns that have the datatype
function DatatypeUseCount(Datatype: TEERDatatype): integer;
var Tables: TList;
  i, j: integer;
begin
  Result:=0;
  Tables:=TList.Create;
  try
    Model.GetEERObjectList([EERTable], Tables);
    for i:=0 to Tables.Count-1 do
      for j:=0 to TEERTable(Tables[i]).Columns.Count-1 do
        if(TEERColumn(TEERTable(Tables[i]).Columns[j]).idDatatype=Datatype.id)then
          inc(Result);
  finally
    Tables.Free;
  end;
end;

function DatatypeToJSON(Datatype: TEERDatatype): TJSONObject;
var Params, Options: TJSONArray;
  i: integer;
begin
  Result:=TJSONObject.Create(['name', U(Datatype.TypeName), 'id', Datatype.id,
    'group', U(DatatypeGroupName(Datatype.group))]);
  if(Datatype.description<>'')then
    Result.Add('description', U(Datatype.description));
  if(Datatype.ParamCount>0)then
  begin
    Params:=TJSONArray.Create;
    for i:=0 to Datatype.ParamCount-1 do
      Params.Add(U(Datatype.Param[i]));
    Result.Add('parameters', Params);
    Result.Add('parameters_required', Datatype.ParamRequired);
  end;
  if(Datatype.OptionCount>0)then
  begin
    Options:=TJSONArray.Create;
    for i:=0 to Datatype.OptionCount-1 do
      Options.Add(U(Datatype.Options[i]));
    Result.Add('options', Options);
  end;
  //The name the datatype has in the SQL code, if it is another one
  if(Datatype.PhysicalMapping)and(Datatype.PhysicalTypeName<>'')then
    Result.Add('sql_name', U(Datatype.PhysicalTypeName));
  if(Datatype.id=Model.DefaultDataType)then
    Result.Add('default_of_model', True);
  Result.Add('used_by_columns', DatatypeUseCount(Datatype));
end;

//By "id", or by name. Models have datatypes of the same name in different
//groups: the name stands for the first one, as everywhere in the program
function NeedDatatype(Args: TJSONObject; const ArgName: string): TEERDatatype;
begin
  NeedModel;
  Result:=nil;
  if(ArgName='datatype')and(HasArg(Args, 'id'))then
  begin
    Result:=Model.GetDataType(ArgInt(Args, 'id', -1));
    if(Result=nil)then
      raise EToolError.CreateFmt('The model has no datatype with the id %d.',
        [ArgInt(Args, 'id', -1)]);
    Exit;
  end;
  if(ArgStr(Args, ArgName)='')then
    raise EToolError.CreateFmt('The argument "%s" is missing.', [ArgName]);
  Result:=Model.GetDataTypeByName(Trim(ArgStr(Args, ArgName)));
  if(Result=nil)then
    raise EToolError.CreateFmt('The model has no datatype "%s". list_datatypes '+
      'shows its datatypes.', [ArgStr(Args, ArgName)]);
end;

//Up to 6 names from an array argument
procedure NamesFromArg(Args: TJSONObject; const ArgName: string; Names: TStrings);
var List: TJSONArray;
  i: integer;
begin
  Names.Clear;
  if(Args.Types[ArgName]<>jtArray)then
    raise EToolError.CreateFmt('"%s" has to be a list of names.', [ArgName]);
  List:=Args.Arrays[ArgName];
  if(List.Count>6)then
    raise EToolError.CreateFmt('A datatype has at most 6 %s.', [ArgName]);
  for i:=0 to List.Count-1 do
  begin
    if(List.Types[i]<>jtString)or(Trim(List.Strings[i])='')then
      raise EToolError.CreateFmt('"%s" has to be a list of names.', [ArgName]);
    Names.Add(Trim(List.Strings[i]));
  end;
end;

//The properties of a datatype that add_datatype and change_datatype share
procedure SetDatatypeFromArgs(Datatype: TEERDatatype; Args: TJSONObject);
var Names: TStringList;
  i, Group: integer;
begin
  Names:=TStringList.Create;
  try
    if(HasArg(Args, 'group'))then
    begin
      Group:=-1;
      for i:=0 to Model.DatatypeGroups.Count-1 do
        if(CompareText(TEERDatatypeGroup(Model.DatatypeGroups[i]).GroupName,
          ArgStr(Args, 'group'))=0)then
          Group:=i;
      if(Group<0)then
        raise EToolError.CreateFmt('The model has no datatype group "%s". Its groups: %s',
          [ArgStr(Args, 'group'), DatatypeGroupNames]);
      Datatype.group:=Group;
    end;
    if(HasArg(Args, 'description'))then
      Datatype.description:=ArgStr(Args, 'description');

    if(HasArg(Args, 'parameters'))then
    begin
      NamesFromArg(Args, 'parameters', Names);
      Datatype.ParamCount:=Names.Count;
      for i:=0 to Names.Count-1 do
        Datatype.Param[i]:=Names[i];
    end;
    if(HasArg(Args, 'parameters_required'))then
      Datatype.ParamRequired:=ArgBool(Args, 'parameters_required', False);
    if(Datatype.ParamCount=0)then
      Datatype.ParamRequired:=False;

    if(HasArg(Args, 'options'))then
    begin
      NamesFromArg(Args, 'options', Names);
      Datatype.OptionCount:=Names.Count;
      for i:=0 to Names.Count-1 do
      begin
        Datatype.Options[i]:=Names[i];
        Datatype.OptionDefaults[i]:=False;
      end;
    end;

    //An empty name: the datatype has its own name in the SQL code again
    if(HasArg(Args, 'sql_name'))then
    begin
      Datatype.PhysicalTypeName:=Trim(ArgStr(Args, 'sql_name'));
      Datatype.PhysicalMapping:=(Datatype.PhysicalTypeName<>'');
    end;
  finally
    Names.Free;
  end;
end;

//The tables show the names of the datatypes
procedure RefreshAllTables;
var Tables: TList;
  i: integer;
begin
  Tables:=TList.Create;
  try
    Model.GetEERObjectList([EERTable], Tables);
    for i:=0 to Tables.Count-1 do
      TEERTable(Tables[i]).RefreshObj;
  finally
    Tables.Free;
  end;
end;

function ToolListDatatypes(Args: TJSONObject): TJSONData;
var i: integer;
  Datatype: TEERDatatype;
  Item: TJSONObject;
  UsedOnly: Boolean;
begin
  NeedModel;
  UsedOnly:=ArgBool(Args, 'used_only', False);

  Result:=TJSONArray.Create;
  for i:=0 to Model.Datatypes.Count-1 do
  begin
    Datatype:=TEERDatatype(Model.Datatypes[i]);
    if(ArgStr(Args, 'group')<>'')and
      (CompareText(DatatypeGroupName(Datatype.group), ArgStr(Args, 'group'))<>0)then
      continue;
    Item:=DatatypeToJSON(Datatype);
    if(UsedOnly)and(Item.Integers['used_by_columns']=0)then
      Item.Free
    else
      TJSONArray(Result).Add(Item);
  end;
end;

function ToolAddDatatype(Args: TJSONObject): TJSONData;
var Datatype: TEERDatatype;
  TypeName: string;
  NewID, i: integer;
begin
  NeedModel;
  TypeName:=Trim(ArgStr(Args, 'name'));
  if(TypeName='')then
    raise EToolError.Create('The argument "name" is missing.');
  if(Model.GetDataTypeByName(TypeName)<>nil)then
    raise EToolError.CreateFmt('The model has a datatype "%s" already.', [TypeName]);

  //The next id, as the datatype palette of the program finds it
  NewID:=1;
  for i:=0 to Model.Datatypes.Count-1 do
    if(NewID<=TEERDatatype(Model.Datatypes[i]).id)then
      NewID:=TEERDatatype(Model.Datatypes[i]).id+1;

  Datatype:=TEERDatatype.Create(Model);
  try
    Datatype.id:=NewID;
    Datatype.TypeName:=TypeName;
    //The group of the user defined datatypes
    Datatype.group:=4;
    if(Datatype.group>=Model.DatatypeGroups.Count)then
      Datatype.group:=Model.DatatypeGroups.Count-1;
    Datatype.description:='';
    Datatype.ParamCount:=0;
    Datatype.OptionCount:=0;
    Datatype.ParamRequired:=False;
    Datatype.EditParamsAsString:=False;
    Datatype.SynonymGroup:=0;
    SetDatatypeFromArgs(Datatype, Args);
  except
    Datatype.Free;
    raise;
  end;
  Model.Datatypes.Add(Datatype);
  Model.ModelHasChanged;

  Result:=DatatypeToJSON(Datatype);
end;

function ToolChangeDatatype(Args: TJSONObject): TJSONData;
var Datatype, Other: TEERDatatype;
  NewName: string;
begin
  Datatype:=NeedDatatype(Args, 'datatype');
  if(Not(HasArg(Args, 'new_name') or HasArg(Args, 'group') or
    HasArg(Args, 'description') or HasArg(Args, 'parameters') or
    HasArg(Args, 'parameters_required') or HasArg(Args, 'options') or
    HasArg(Args, 'sql_name')))then
    raise EToolError.Create('Nothing to change: give new_name, group, description, '+
      'parameters, parameters_required, options or sql_name.');

  NewName:=Trim(ArgStr(Args, 'new_name'));
  if(HasArg(Args, 'new_name'))then
  begin
    if(NewName='')then
      raise EToolError.Create('"new_name" is empty.');
    Other:=Model.GetDataTypeByName(NewName);
    if(Other<>nil)and(Other<>Datatype)then
      raise EToolError.CreateFmt('The model has a datatype "%s" already.', [NewName]);
  end;

  SetDatatypeFromArgs(Datatype, Args);
  if(NewName<>'')then
    Datatype.TypeName:=NewName;

  RefreshAllTables;
  Model.ModelHasChanged;
  Result:=DatatypeToJSON(Datatype);
end;

function ToolDeleteDatatype(Args: TJSONObject): TJSONData;
var Datatype, Replacement: TEERDatatype;
  Tables: TList;
  Column: TEERColumn;
  Info: TJSONObject;
  Used, i, j: integer;
begin
  Datatype:=NeedDatatype(Args, 'datatype');
  if(Datatype.id=Model.DefaultDataType)then
    raise EToolError.CreateFmt('%s is the default datatype of the model. Set '+
      'another one with change_model_settings first.', [Datatype.TypeName]);

  //The program puts the default datatype into the columns without asking
  //which. Here the datatype for them has to be named
  Used:=DatatypeUseCount(Datatype);
  Replacement:=nil;
  if(ArgStr(Args, 'replace_with')<>'')then
  begin
    Replacement:=NeedDatatype(Args, 'replace_with');
    if(Replacement=Datatype)then
      raise EToolError.Create('"replace_with" names the datatype that is to be deleted.');
  end;
  if(Used>0)and(Replacement=nil)then
    raise EToolError.CreateFmt('%d column(s) have the datatype %s. Name the '+
      'datatype they get with "replace_with".', [Used, Datatype.TypeName]);

  Info:=DatatypeToJSON(Datatype);
  if(Used>0)then
  begin
    Tables:=TList.Create;
    try
      Model.GetEERObjectList([EERTable], Tables);
      for i:=0 to Tables.Count-1 do
        for j:=0 to TEERTable(Tables[i]).Columns.Count-1 do
        begin
          Column:=TEERColumn(TEERTable(Tables[i]).Columns[j]);
          if(Column.idDatatype=Datatype.id)then
            Column.idDatatype:=Replacement.id;
        end;
    finally
      Tables.Free;
    end;
  end;

  //Out of the list of the common datatypes as well
  i:=Model.CommonDataType.IndexOf(IntToStr(Datatype.id));
  if(i>=0)then
    Model.CommonDataType.Delete(i);
  Model.Datatypes.Delete(Model.Datatypes.IndexOf(Datatype));

  RefreshAllTables;
  Model.ModelHasChanged;
  Result:=TJSONObject.Create(['deleted_datatype', Info]);
  if(Replacement<>nil)and(Used>0)then
    TJSONObject(Result).Add('columns_changed_to', U(Replacement.TypeName));
end;

// ---------------------------------------------------------------------------
// Settings of the model

function ModelSettingsToJSON: TJSONObject;
begin
  Result:=TJSONObject.Create;
  Result.Add('model_name', U(Model.GetModelName));
  Result.Add('comments', U(Model.ModelComments));
  Result.Add('version', U(Model.VersionStr));
  Result.Add('file', U(ModelFile));
  Result.Add('unsaved_changes', Model.IsChanged);
  Result.Add('database_type', U(Model.DatabaseType));
  if(Model.GetDataType(Model.DefaultDataType)<>nil)then
    Result.Add('default_datatype',
      U(TEERDatatype(Model.GetDataType(Model.DefaultDataType)).TypeName));
  //How the model names the foreign key columns it makes
  Result.Add('foreign_key_prefix', U(Model.FKPrefix));
  Result.Add('foreign_key_postfix', U(Model.FKPostfix));
  Result.Add('foreign_key_constraint_for_new_relations', Model.ActivateRefDefForNewRelations);
  Result.Add('index_for_foreign_keys', Model.CreateFKRefDefIndex);
  Result.Add('table_name_in_relation_captions', Model.TableNameInRefs);
  Result.Add('sql_for_linked_tables', Model.CreateSQLforLinkedObjects);
  Result.Add('use_position_grid', Model.UsePositionGrid);
  Result.Add('position_grid_x', Model.PositionGrid.X);
  Result.Add('position_grid_y', Model.PositionGrid.Y);
  Result.Add('canvas_width', Model.EERModel_Width);
  Result.Add('canvas_height', Model.EERModel_Height);
  Result.Add('region_colors', U(RegionColorNames));
end;

function ToolGetModelSettings(Args: TJSONObject): TJSONData;
begin
  NeedModel;
  Result:=ModelSettingsToJSON;
end;

function ToolChangeModelSettings(Args: TJSONObject): TJSONData;
const
  Settings: array[0..12] of string = ('model_name', 'comments', 'version',
    'default_datatype',
    'foreign_key_prefix', 'foreign_key_postfix',
    'foreign_key_constraint_for_new_relations', 'index_for_foreign_keys',
    'table_name_in_relation_captions', 'sql_for_linked_tables',
    'use_position_grid', 'position_grid_x', 'position_grid_y');
var i, Given: integer;
begin
  NeedModel;
  Given:=0;
  for i:=Low(Settings) to High(Settings) do
    if(HasArg(Args, Settings[i]))then
      inc(Given);
  if(Given=0)then
    raise EToolError.Create('Nothing to change. The settings that can be changed: '+
      'model_name, comments, version, default_datatype, foreign_key_prefix, '+
      'foreign_key_postfix, '+
      'foreign_key_constraint_for_new_relations, index_for_foreign_keys, '+
      'table_name_in_relation_captions, sql_for_linked_tables, use_position_grid, '+
      'position_grid_x, position_grid_y.');

  if(HasArg(Args, 'model_name'))and(Trim(ArgStr(Args, 'model_name'))='')then
    raise EToolError.Create('"model_name" is empty.');
  //Raises if the model has no such datatype, before anything is changed
  if(HasArg(Args, 'default_datatype'))then
    NeedDatatype(Args, 'default_datatype');
  if(ArgInt(Args, 'position_grid_x', 1)<1)or(ArgInt(Args, 'position_grid_y', 1)<1)then
    raise EToolError.Create('The position grid is at least 1.');

  if(HasArg(Args, 'model_name'))then
    Model.SetModelName(Trim(ArgStr(Args, 'model_name')));
  if(HasArg(Args, 'comments'))then
    Model.ModelComments:=ArgStr(Args, 'comments');
  if(HasArg(Args, 'version'))then
    Model.VersionStr:=Trim(ArgStr(Args, 'version'));
  if(HasArg(Args, 'default_datatype'))then
    Model.DefaultDataType:=NeedDatatype(Args, 'default_datatype').id;
  if(HasArg(Args, 'foreign_key_prefix'))then
    Model.FKPrefix:=ArgStr(Args, 'foreign_key_prefix');
  if(HasArg(Args, 'foreign_key_postfix'))then
    Model.FKPostfix:=ArgStr(Args, 'foreign_key_postfix');
  Model.ActivateRefDefForNewRelations:=ArgBool(Args,
    'foreign_key_constraint_for_new_relations', Model.ActivateRefDefForNewRelations);
  Model.CreateFKRefDefIndex:=ArgBool(Args, 'index_for_foreign_keys', Model.CreateFKRefDefIndex);
  Model.TableNameInRefs:=ArgBool(Args, 'table_name_in_relation_captions', Model.TableNameInRefs);
  Model.CreateSQLforLinkedObjects:=ArgBool(Args, 'sql_for_linked_tables',
    Model.CreateSQLforLinkedObjects);
  Model.UsePositionGrid:=ArgBool(Args, 'use_position_grid', Model.UsePositionGrid);
  Model.PositionGrid.X:=ArgInt(Args, 'position_grid_x', Model.PositionGrid.X);
  Model.PositionGrid.Y:=ArgInt(Args, 'position_grid_y', Model.PositionGrid.Y);

  //The indices of the foreign keys follow their setting
  Model.CheckAllRelations;
  Model.ModelHasChanged;
  Result:=ModelSettingsToJSON;
end;

function ToolSaveModel(Args: TJSONObject): TJSONData;
var FileName, Backup: string;
begin
  NeedModel;
  FileName:=ArgStr(Args, 'path');
  if(FileName='')then
    FileName:=ModelFile
  else
    FileName:=ExpandFileName(FileName);
  if(FileName='')then
    raise EToolError.Create('The model has no file yet. Give a "path".');

  //Another file than the one of the model is not written over by accident
  if(FileExists(FileName))and(Not(SameFileName(FileName, ModelFile)))and
    (Not(ArgBool(Args, 'overwrite', False)))then
    raise EToolError.CreateFmt('The file "%s" exists. Set "overwrite" to '+
      'true to replace it.', [FileName]);

  //The file as it was stays next to the new one
  Backup:='';
  if(FileExists(FileName))then
  begin
    Backup:=FileName+'.bak';
    if(Not(CopyFile(FileName, Backup)))then
      raise EToolError.CreateFmt('The backup "%s" could not be written, '+
        'the model is not saved.', [Backup]);
  end;

  Model.SaveToFile(FileName);
  Model.IsChanged:=False;
  ModelFile:=FileName;

  Result:=TJSONObject.Create(['file', U(FileName),
    'tables', Model.GetEERObjectCount([EERTable]),
    'relations', Model.GetEERObjectCount([EERRelation])]);
  if(Backup<>'')then
    TJSONObject(Result).Add('backup', U(Backup));
end;

// ---------------------------------------------------------------------------
// Database tools (Firebird)

procedure NeedConnection;
begin
  if(DBConn=nil)or(DMDB.CurrentDBConn=nil)then
    raise EToolError.Create('No database is connected. Call connect_database first.');
end;

procedure CloseConnection;
begin
  if(DMDB.CurrentDBConn<>nil)then
    DMDB.DisconnectFromDB;
  FreeAndNil(DBConn);
end;

//All values of the first column
procedure QueryValues(const Stmt: string; Values: TStrings);
var Q: SQLDB.TSQLQuery;
begin
  Values.Clear;
  Q:=SQLDB.TSQLQuery.Create(nil);
  try
    Q.DataBase:=DMDB.SQLConn;
    Q.Transaction:=SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction);
    Q.ParamCheck:=False;
    Q.SQL.Text:=Stmt;
    Q.Open;
    while(Not(Q.EOF))do
    begin
      Values.Add(Trim(Q.Fields[0].AsString));
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
  end;
  SQLDB.TSQLTransaction(DMDB.SQLConn.Transaction).CommitRetaining;
end;

function IsFirebird(Conn: TDBConn): Boolean;
begin
  Result:=(CompareText(Conn.DriverName, 'Firebird')=0);
end;

//A connection without its password
function ConnectionToJSON(Conn: TDBConn): TJSONObject;
begin
  Result:=TJSONObject.Create;
  Result.Add('name', U(Conn.Name));
  Result.Add('driver', U(Conn.DriverName));
  if(Conn.Description<>'')then
    Result.Add('description', U(Conn.Description));
  if(Conn.Params.Values['HostName']<>'')then
    Result.Add('host', U(Conn.Params.Values['HostName']))
  else if(IsFirebird(Conn))then
    Result.Add('host', '(embedded)');
  Result.Add('database', U(Conn.Params.Values['Database']));
  if(Conn.Params.Values['User_Name']<>'')then
    Result.Add('user', U(Conn.Params.Values['User_Name']));
end;

function ToolListConnections(Args: TJSONObject): TJSONData;
var i: integer;
  Conn: TDBConn;
  Item: TJSONObject;
begin
  Result:=TJSONArray.Create;
  for i:=0 to DMDB.DBConnections.Count-1 do
  begin
    Conn:=TDBConn(DMDB.DBConnections[i]);
    Item:=ConnectionToJSON(Conn);
    Item.Add('password_stored', Conn.Params.Values['Password']<>'');
    //The database tools are for Firebird
    Item.Add('usable', IsFirebird(Conn));
    TJSONArray(Result).Add(Item);
  end;
end;

function ToolConnectDatabase(Args: TJSONObject): TJSONData;
var NewConn, Stored: TDBConn;
  Values: TStringList;
  Names: string;
  i: integer;
begin
  if(ArgStr(Args, 'connection')<>'')then
  begin
    Stored:=nil;
    Names:='';
    for i:=0 to DMDB.DBConnections.Count-1 do
    begin
      Names:=Names+IfThen(i>0, ', ')+TDBConn(DMDB.DBConnections[i]).Name;
      if(CompareText(TDBConn(DMDB.DBConnections[i]).Name, ArgStr(Args, 'connection'))=0)then
        Stored:=TDBConn(DMDB.DBConnections[i]);
    end;
    if(Stored=nil)then
      raise EToolError.CreateFmt('There is no stored connection "%s". The stored '+
        'connections: %s', [ArgStr(Args, 'connection'), IfThen(Names='', '(none)', Names)]);

    //A copy: the list of the program is not changed
    NewConn:=TDBConn.Create;
    NewConn.Assign(Stored);
  end
  else
  begin
    if(ArgStr(Args, 'database')='')then
      raise EToolError.Create('Give "connection" (a stored connection, see '+
        'list_connections) or "database" (file or alias of a Firebird database).');

    //The defaults of the program for a Firebird connection
    NewConn:=DMDB.GetNewDBConn('MCP', False, 'Firebird');
    NewConn.DriverName:='Firebird';
    NewConn.Params.Values['Database']:=ArgStr(Args, 'database');
    //No host name: the embedded engine
    NewConn.Params.Values['HostName']:=ArgStr(Args, 'host');
    if(ArgStr(Args, 'host')='')then
      NewConn.Params.Values['Port']:=''
    else if(Args.IndexOfName('port')>=0)then
      NewConn.Params.Values['Port']:=IntToStr(ArgInt(Args, 'port', 3050));
    if(NewConn.Params.Values['User_Name']='')or(ArgStr(Args, 'user')<>'')then
      NewConn.Params.Values['User_Name']:=ArgStr(Args, 'user', 'SYSDBA');
  end;

  try
    if(Not(IsFirebird(NewConn)))then
      raise EToolError.CreateFmt('The connection "%s" is a %s connection. The '+
        'database tools work with Firebird only.', [NewConn.Name, NewConn.DriverName]);

    if(ArgStr(Args, 'password')<>'')then
      NewConn.Params.Values['Password']:=ArgStr(Args, 'password');
    if(ArgStr(Args, 'client_library')<>'')then
      NewConn.VendorLib:=ArgStr(Args, 'client_library');

    //The embedded engine creates a database file that is not there
    if(NewConn.Params.Values['HostName']='')and
      (Not(FileExists(NewConn.Params.Values['Database'])))and
      (Not(ArgBool(Args, 'create', False)))then
      raise EToolError.CreateFmt('The database file "%s" does not exist. Set '+
        '"create" to true to create it.', [NewConn.Params.Values['Database']]);

    CloseConnection;
    DMDB.ConnectToDB(NewConn);
    if(DMDB.CurrentDBConn=nil)then
      raise EToolError.Create('The connection could not be opened.');
  except
    NewConn.Free;
    raise;
  end;
  DBConn:=NewConn;

  Result:=ConnectionToJSON(DBConn);
  Values:=TStringList.Create;
  try
    QueryValues('SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') FROM RDB$DATABASE', Values);
    if(Values.Count>0)then
      TJSONObject(Result).Add('firebird_version', Values[0]);
    FirebirdGetTables(Values);
    TJSONObject(Result).Add('tables', Values.Count);
  finally
    Values.Free;
  end;
end;

function ToolDisconnectDatabase(Args: TJSONObject): TJSONData;
begin
  NeedConnection;
  CloseConnection;
  Result:=TJSONString.Create('Disconnected.');
end;

function ToolListDatabaseTables(Args: TJSONObject): TJSONData;
var DbTables: TStringList;
  Item: TJSONObject;
  i: integer;
begin
  NeedConnection;

  Result:=TJSONArray.Create;
  DbTables:=TStringList.Create;
  try
    FirebirdGetTables(DbTables);
    for i:=0 to DbTables.Count-1 do
    begin
      Item:=TJSONObject.Create(['name', U(DbTables[i])]);
      if(Model<>nil)then
        Item.Add('in_model', Model.GetEERObjectByName(EERTable, DbTables[i])<>nil);
      TJSONArray(Result).Add(Item);
    end;
  finally
    DbTables.Free;
  end;
end;

function ToolReverseEngineer(Args: TJSONObject): TJSONData;
var DbTables, Selected: TStringList;
  Wanted: TJSONArray;
  Added, Skipped: TJSONArray;
  Guess: string;
  i, j: integer;
begin
  NeedModel;
  NeedConnection;

  Guess:=LowerCase(ArgStr(Args, 'relation_guess', 'by_name'));
  if(Guess<>'by_name')and(Guess<>'by_primary_key')then
    raise EToolError.Create('"relation_guess" has to be by_name or by_primary_key.');

  DbTables:=TStringList.Create;
  Selected:=TStringList.Create;
  try
    FirebirdGetTables(DbTables);

    Wanted:=nil;
    if(Args<>nil)and(Args.IndexOfName('tables')>=0)and(Args.Types['tables']=jtArray)then
      Wanted:=Args.Arrays['tables'];
    if(Wanted=nil)or(Wanted.Count=0)then
      Selected.Assign(DbTables)
    else
      for i:=0 to Wanted.Count-1 do
      begin
        j:=-1;
        if(Wanted.Types[i]=jtString)then
          j:=DbTables.IndexOf(Wanted.Strings[i]);
        if(j<0)then
          raise EToolError.CreateFmt('The database has no table "%s". '+
            'list_database_tables shows its tables.', [Wanted.Items[i].AsString]);
        Selected.Add(DbTables[j]);
      end;

    //A table that is in the model already is left as it is
    Added:=TJSONArray.Create;
    Skipped:=TJSONArray.Create;
    for i:=0 to Selected.Count-1 do
      if(Model.GetEERObjectByName(EERTable, Selected[i])<>nil)then
        Skipped.Add(U(Selected[i]))
      else
        Added.Add(U(Selected[i]));
    Result:=TJSONObject.Create(['added_tables', Added,
      'skipped_tables_already_in_model', Skipped]);

    if(Added.Count>0)then
    begin
      //5 tables in a row; the foreign keys of the database become relations,
      //further ones are guessed
      FirebirdReverseEngineer(Model, Selected, 5,
        ArgBool(Args, 'relations', True), Guess='by_primary_key',
        nil, nil, False, 0);
      Model.ModelHasChanged;
    end;
    TJSONObject(Result).Add('tables_in_model', Model.GetEERObjectCount([EERTable]));
    TJSONObject(Result).Add('relations_in_model', Model.GetEERObjectCount([EERRelation]));
  finally
    DbTables.Free;
    Selected.Free;
  end;
end;

//Without "apply" only what the synchronisation would do with the tables.
//The changes inside a table (columns, indices, keys) are found by the
//synchronisation itself, they are in its log
function ToolSyncDatabase(Args: TJSONObject): TJSONData;
var DbTables, Log: TStringList;
  ModelTables: TList;
  Create, Compare, Keep: TJSONArray;
  Table: TEERTable;
  i: integer;
begin
  NeedModel;
  NeedConnection;

  DbTables:=TStringList.Create;
  Log:=TStringList.Create;
  ModelTables:=TList.Create;
  try
    DbTables.CaseSensitive:=False;
    FirebirdGetTables(DbTables);

    Model.GetEERObjectList([EERTable], ModelTables);
    Model.SortEERObjectListByObjName(ModelTables);
    Create:=TJSONArray.Create;
    Compare:=TJSONArray.Create;
    Keep:=TJSONArray.Create;
    Result:=TJSONObject.Create([
      'database', ConnectionToJSON(DBConn),
      'tables_to_create', Create,
      'tables_to_compare_and_alter', Compare,
      'tables_only_in_database_kept', Keep]);

    for i:=0 to ModelTables.Count-1 do
    begin
      Table:=ModelTables[i];
      if(Table.IsLinkedObject)and(Not(Model.CreateSQLforLinkedObjects))then
        continue;
      if(DbTables.IndexOf(Table.ObjName)>=0)then
        Compare.Add(U(Table.ObjName))
      //A renamed table is renamed in the database
      else if(Table.PrevTableName<>'')and(DbTables.IndexOf(Table.PrevTableName)>=0)then
        Compare.Add(U(Table.PrevTableName+' -> '+Table.ObjName))
      else
        Create.Add(U(Table.ObjName));
    end;
    for i:=0 to DbTables.Count-1 do
      if(Model.GetEERObjectByName(EERTable, DbTables[i])=nil)then
        Keep.Add(U(DbTables[i]));

    if(Not(ArgBool(Args, 'apply', False)))then
    begin
      TJSONObject(Result).Add('applied', False);
      TJSONObject(Result).Add('note', 'Nothing was changed. In the tables to '+
        'compare, columns, indices and keys are changed to match the model; '+
        'a column that is not in the model is dropped with its data. Call '+
        'again with "apply": true to do it.');
      Exit;
    end;

    try
      //Tables that are not in the model are kept, no standard inserts
      DMDBEER.EERMySQLSyncDB(Model, DBConn, Log, True,
        ArgBool(Args, 'standard_inserts', False), False);
    except
      on E: Exception do
      begin
        Result.Free;
        raise EToolError.Create(E.ClassName+': '+E.Message+#10#10'Log:'#10+Trim(Log.Text));
      end;
    end;
    TJSONObject(Result).Add('applied', True);
    TJSONObject(Result).Add('errors', Pos('ERROR', Log.Text)>0);
    TJSONObject(Result).Add('log', U(Trim(StringReplace(Log.Text, #13#10, #10, [rfReplaceAll]))));
  finally
    DbTables.Free;
    Log.Free;
    ModelTables.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Protocol

//The hints tell a client which tools only read, which may destroy
//something (a file, data in a database) and which reach a database
function Tool(const Name, Description, InputSchema: string): TJSONObject;
const
  ReadOnlyTools: array[0..11] of string = ('open_model', 'list_tables',
    'describe_table', 'list_relations', 'export_sql', 'list_connections',
    'list_database_tables', 'list_regions', 'list_notes', 'get_model_settings',
    'list_images', 'list_datatypes');
  DestructiveTools: array[0..9] of string = ('save_model', 'sync_database',
    'delete_table', 'delete_column', 'delete_relation', 'delete_index',
    'delete_region', 'delete_note', 'delete_image', 'delete_datatype');
  DatabaseTools: array[0..4] of string = ('connect_database',
    'disconnect_database', 'list_database_tables', 'reverse_engineer',
    'sync_database');
begin
  Result:=TJSONObject.Create(['name', Name, 'description', Description,
    'inputSchema', GetJSON(InputSchema),
    'annotations', TJSONObject.Create([
      'readOnlyHint', IndexInList(ReadOnlyTools, Name)>=0,
      'destructiveHint', IndexInList(DestructiveTools, Name)>=0,
      'openWorldHint', IndexInList(DatabaseTools, Name)>=0])]);
end;

function ToolList: TJSONObject;
begin
  Result:=TJSONObject.Create(['tools', TJSONArray.Create([
    Tool('open_model',
      'Open a DBDesigner model file (.xml). The model stays open for the '+
      'other tools until another one is opened. Returns the name of the '+
      'model and the number of its objects.',
      '{"type":"object","properties":{"path":{"type":"string",'+
      '"description":"Path of the model file"}},"required":["path"]}'),
    Tool('list_tables',
      'List the tables of the open model with the number of columns, the '+
      'primary key columns and the comments.',
      '{"type":"object","properties":{}}'),
    Tool('describe_table',
      'The columns (datatype, primary key, not null, auto increment, '+
      'default, comments), the indices and the relations of one table of '+
      'the open model.',
      '{"type":"object","properties":{"table":{"type":"string",'+
      '"description":"Name of the table"}},"required":["table"]}'),
    Tool('list_relations',
      'List the relations (foreign keys) of the open model: parent and '+
      'child table, the column pairs, the kind and the referential actions. '+
      'With "table" only the relations of that table.',
      '{"type":"object","properties":{"table":{"type":"string",'+
      '"description":"Only the relations of this table"}}}'),
    Tool('export_sql',
      'The SQL script of the open model for a target database, as the SQL'+
      ' export of DBDesigner writes it: all tables in the order of their '+
      'foreign keys, or one table. Script create (default) or drop.',
      '{"type":"object","properties":{"database":{"type":"string","enum":'+
      '["FireBird","My SQL","Oracle","PostgreSQL","SQL Server","SQLite"],'+
      '"description":"Target database"},"table":{"type":"string","descrip'+
      'tion":"Only this table"},"script":{"type":"string","enum":["create'+
      '","drop"],"description":"Default: create"},"foreign_keys":{"type":'+
      '"boolean","description":"Write the foreign key constraints (defaul'+
      't true)"},"comments":{"type":"boolean","description":"Write the co'+
      'mments of tables and columns (default false)"},"drop_tables":{"typ'+
      'e":"boolean","description":"DROP TABLE statements in front of the '+
      'creates (default false)"},"standard_inserts":{"type":"boolean","de'+
      'scription":"Write the standard inserts stored in the model (defaul'+
      't false)"},"auto_increment_triggers":{"type":"boolean","descriptio'+
      'n":"Oracle and FireBird: auto increment by a sequence or generator'+
      ' and triggers (default false; FireBird then uses identity columns)'+
      '"},"sequence_name":{"type":"string","description":"Name of that se'+
      'quence or generator (default GlobalSequence)"},"last_change_trigge'+
      'rs":{"type":"boolean","description":"Oracle, FireBird, SQL Server:'+
      ' columns and triggers that store the last change of a row (default'+
      ' false)"},"last_delete_triggers":{"type":"boolean","description":"'+
      'Oracle, FireBird, SQL Server: a table and triggers that store the '+
      'last delete per table (default false)"}},"required":["database"]}'),
    Tool('new_model',
      'Start a new, empty model in place of the open one. It has no file '+
      'until save_model gets a path.',
      '{"type":"object","properties":{"name":{"type":"string","descriptio'+
      'n":"Name of the model"}}}'),
    Tool('add_table',
      'Add a table to the open model, with its columns. Without x and y i'+
      't is placed where no other object is. The change is in memory unti'+
      'l save_model. Returns the table.',
      '{"type":"object","properties":{"name":{"type":"string","descriptio'+
      'n":"Name of the table"},"comments":{"type":"string"},"columns":{"t'+
      'ype":"array","items":{"type":"object","properties":{"name":{"type"'+
      ':"string"},"datatype":{"type":"string","description":"Datatype of '+
      'the model with its parameters and options, e.g. INTEGER, VARCHAR(4'+
      '5), DECIMAL(10,2), INTEGER UNSIGNED"},"primary_key":{"type":"boole'+
      'an"},"not_null":{"type":"boolean"},"auto_increment":{"type":"boole'+
      'an"},"default":{"type":"string","description":"Default value"},"co'+
      'mments":{"type":"string"}},"required":["name","datatype"]}},"x":{"'+
      'type":"integer","description":"Position in the diagram"},"y":{"typ'+
      'e":"integer"}},"required":["name"]}'),
    Tool('add_column',
      'Add a column at the end of a table of the open model. A new primar'+
      'y key column is added to the tables that refer to this one as well'+
      '. Do not add foreign key columns: add_relation makes them. Returns'+
      ' the table.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"name":{"type":"string"},"datatype":{"typ'+
      'e":"string","description":"Datatype of the model with its paramete'+
      'rs and options, e.g. INTEGER, VARCHAR(45), DECIMAL(10,2), INTEGER '+
      'UNSIGNED"},"primary_key":{"type":"boolean"},"not_null":{"type":"bo'+
      'olean"},"auto_increment":{"type":"boolean"},"default":{"type":"str'+
      'ing","description":"Default value"},"comments":{"type":"string"}},'+
      '"required":["table","name","datatype"]}'),
    Tool('add_relation',
      'Add a relation from a parent table to a child table. The foreign k'+
      'ey columns are made in the child table from the primary key of the'+
      ' parent (identifying kinds make them part of the primary key of th'+
      'e child). They get the names of the primary key columns, with the '+
      'name of the parent table in front (kunde_id) if the child has such'+
      ' a column already; child_column sets the name or names an existing'+
      ' column of the child to use. Kind n:m makes a table <parent>_has_<'+
      'child> between the two. Returns the relation and the child table.',
      '{"type":"object","properties":{"parent_table":{"type":"string","de'+
      'scription":"The referenced table"},"child_table":{"type":"string",'+
      '"description":"The table that gets the foreign key"},"kind":{"type'+
      '":"string","enum":["1:n","1:n non-identifying","1:1","1:1 non-iden'+
      'tifying","n:m"],"description":"Default: 1:n non-identifying"},"nam'+
      'e":{"type":"string","description":"Name of the relation"},"child_c'+
      'olumn":{"type":"string","description":"Name of the foreign key col'+
      'umn, for a parent with one primary key column"},"foreign_key_const'+
      'raint":{"type":"boolean","description":"Write a FOREIGN KEY constr'+
      'aint in the SQL code (default true)"},"on_delete":{"type":"string"'+
      ',"enum":["RESTRICT","CASCADE","SET NULL","NO ACTION","SET DEFAULT"'+
      ']},"on_update":{"type":"string","enum":["RESTRICT","CASCADE","SET '+
      'NULL","NO ACTION","SET DEFAULT"]},"comments":{"type":"string"}},"r'+
      'equired":["parent_table","child_table"]}'),
    Tool('rename_table',
      'Give a table of the open model another name. The names of columns '+
      'and relations stay as they are. The model keeps the former name, s'+
      'o sync_database renames the table in the database instead of creat'+
      'ing a new one. Returns the table.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"new_name":{"type":"string"}},"required":'+
      '["table","new_name"]}'),
    Tool('change_column',
      'Change a column of a table of the open model: its name, datatype, '+
      'primary key, not null, auto increment, default or comments. Only w'+
      'hat is given is changed. The model keeps the former name of a rena'+
      'med column, so sync_database renames it in the database; the relat'+
      'ions go on using the column. Datatype and primary key of a foreign'+
      ' key column cannot be changed, they follow the relation. A primary'+
      ' key column that is added or removed is added to or removed from t'+
      'he tables that refer to this one. Returns the table.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"column":{"type":"string","description":"'+
      'Name of the column"},"new_name":{"type":"string"},"datatype":{"typ'+
      'e":"string","description":"e.g. INTEGER, VARCHAR(45), DECIMAL(10,2'+
      '), INTEGER UNSIGNED"},"primary_key":{"type":"boolean"},"not_null":'+
      '{"type":"boolean"},"auto_increment":{"type":"boolean"},"default":{'+
      '"type":"string","description":"Default value, empty for none"},"co'+
      'mments":{"type":"string"}},"required":["table","column"]}'),
    Tool('delete_column',
      'Delete a column of a table of the open model; it is taken out of t'+
      'he indices as well. A foreign key column is deleted with its relat'+
      'ion (delete_relation). Returns the table.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"column":{"type":"string","description":"'+
      'Name of the column"}},"required":["table","column"]}'),
    Tool('delete_table',
      'Delete a table of the open model with the relations from and to it'+
      '; the foreign key columns in the tables that referred to it are re'+
      'moved. Returns the deleted relations.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"}},"required":["table"]}'),
    Tool('delete_relation',
      'Delete a relation of the open model, named by its name or by paren'+
      't and child table. Its foreign key columns are removed from the ch'+
      'ild table, unless keep_columns is set: then they stay as ordinary '+
      'columns. Returns the deleted relation and the child table.',
      '{"type":"object","properties":{"name":{"type":"string","descriptio'+
      'n":"Name of the relation"},"parent_table":{"type":"string"},"child'+
      '_table":{"type":"string"},"keep_columns":{"type":"boolean","descri'+
      'ption":"Keep the foreign key columns as ordinary columns (default '+
      'false)"}}}'),
    Tool('add_index',
      'Add an index to a table of the open model. The primary index and t'+
      'he indices of foreign keys are made by the model. Returns the tabl'+
      'e.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"columns":{"type":"array","items":{"type"'+
      ':"string"},"description":"Names of the columns, in the order of th'+
      'e index"},"name":{"type":"string","description":"Name of the index'+
      '; default <table>_index<number>"},"kind":{"type":"string","enum":['+
      '"INDEX","UNIQUE","FULLTEXT"],"description":"Default INDEX"}},"requ'+
      'ired":["table","columns"]}'),
    Tool('delete_index',
      'Delete an index of a table of the open model. Not the primary inde'+
      'x and not the index of a foreign key. Returns the table.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"index":{"type":"string","description":"N'+
      'ame of the index"}},"required":["table","index"]}'),
    Tool('move_table',
      'Move a table of the open model to another place in the diagram. de'+
      'scribe_table shows the place and the size of a table. A table belo'+
      'ngs to the region it lies completely inside of.',
      '{"type":"object","properties":{"table":{"type":"string","descripti'+
      'on":"Name of the table"},"x":{"type":"integer","description":"Posi'+
      'tion in the diagram, in the units of the model"},"y":{"type":"inte'+
      'ger"}},"required":["table","x","y"]}'),
    Tool('list_regions',
      'The regions of the open model: coloured rectangles that group the '+
      'tables lying completely inside of them. With their place, size, co'+
      'lour and tables.',
      '{"type":"object","properties":{}}'),
    Tool('add_region',
      'Add a region to the open model: around the named tables (other tab'+
      'les inside that rectangle belong to it as well, see the result), o'+
      'r at a place with a size. Returns the region with its tables.',
      '{"type":"object","properties":{"name":{"type":"string","descriptio'+
      'n":"Name of the region; default Region_<number>"},"tables":{"type"'+
      ':"array","items":{"type":"string"},"description":"The region is la'+
      'id around these tables"},"x":{"type":"integer","description":"Posi'+
      'tion in the diagram, in the units of the model"},"y":{"type":"inte'+
      'ger"},"width":{"type":"integer"},"height":{"type":"integer"},"colo'+
      'r":{"type":"string","description":"One of the region colours of th'+
      'e model, see get_model_settings; default: the next one"},"comments'+
      '":{"type":"string"}}}'),
    Tool('change_region',
      'Change a region of the open model: name, place, size, colour or co'+
      'mments. Only what is given is changed. The tables do not move with'+
      ' the region.',
      '{"type":"object","properties":{"region":{"type":"string","descript'+
      'ion":"Name of the region"},"new_name":{"type":"string"},"x":{"type'+
      '":"integer","description":"Position in the diagram, in the units o'+
      'f the model"},"y":{"type":"integer"},"width":{"type":"integer"},"h'+
      'eight":{"type":"integer"},"color":{"type":"string"},"comments":{"t'+
      'ype":"string"}},"required":["region"]}'),
    Tool('delete_region',
      'Delete a region of the open model. The tables in it stay.',
      '{"type":"object","properties":{"region":{"type":"string","descript'+
      'ion":"Name of the region"}},"required":["region"]}'),
    Tool('list_notes',
      'The notes of the open model: texts placed in the diagram.',
      '{"type":"object","properties":{}}'),
    Tool('add_note',
      'Add a note with a text to the diagram of the open model. Without x'+
      ' and y it is placed where no other object is.',
      '{"type":"object","properties":{"text":{"type":"string","descriptio'+
      'n":"Text of the note, may have several lines"},"name":{"type":"str'+
      'ing","description":"Name of the note; default Note_<number>"},"x":'+
      '{"type":"integer","description":"Position in the diagram, in the u'+
      'nits of the model"},"y":{"type":"integer"}},"required":["text"]}'),
    Tool('change_note',
      'Change a note of the open model: text, name or place. Only what is'+
      ' given is changed.',
      '{"type":"object","properties":{"note":{"type":"string","descriptio'+
      'n":"Name of the note"},"new_name":{"type":"string"},"text":{"type"'+
      ':"string"},"x":{"type":"integer","description":"Position in the di'+
      'agram, in the units of the model"},"y":{"type":"integer"}},"requir'+
      'ed":["note"]}'),
    Tool('delete_note',
      'Delete a note of the open model.',
      '{"type":"object","properties":{"note":{"type":"string","descriptio'+
      'n":"Name of the note"}},"required":["note"]}'),
    Tool('get_model_settings',
      'The settings of the open model: name, comments, version, file, whe'+
      'ther it has unsaved changes, how foreign key columns are named, wh'+
      'ether new relations get a foreign key constraint and an index, the'+
      ' position grid, the size of the canvas, the region colours.',
      '{"type":"object","properties":{}}'),
    Tool('change_model_settings',
      'Change settings of the open model. Only what is given is changed. '+
      'Prefix and postfix of foreign key columns are for the relations ma'+
      'de afterwards. Returns all settings.',
      '{"type":"object","properties":{"model_name":{"type":"string"},"com'+
      'ments":{"type":"string"},"version":{"type":"string","description":'+
      '"e.g. 1.0.0.0"},"default_datatype":{"type":"string","description":'+
      '"Name of the datatype new columns get in the table editor of the p'+
      'rogram"},"foreign_key_prefix":{"type":"string","description":"Put '+
      'in front of the name of a primary key column to name its foreign k'+
      'ey column"},"foreign_key_postfix":{"type":"string"},"foreign_key_c'+
      'onstraint_for_new_relations":{"type":"boolean","description":"Defa'+
      'ult of the program for relations made in its diagram"},"index_for_'+
      'foreign_keys":{"type":"boolean","description":"An index in the chi'+
      'ld table for every relation with a foreign key constraint"},"table'+
      '_name_in_relation_captions":{"type":"boolean"},"sql_for_linked_tab'+
      'les":{"type":"boolean","description":"Write SQL for tables linked '+
      'from other models"},"use_position_grid":{"type":"boolean"},"positi'+
      'on_grid_x":{"type":"integer"},"position_grid_y":{"type":"integer"}'+
      '}}'),
    Tool('list_images',
      'The images of the open model: pictures placed in the diagram, with'+
      ' their place, their size there and the size of the picture.',
      '{"type":"object","properties":{}}'),
    Tool('add_image',
      'Put a picture from a PNG or BMP file into the diagram of the open '+
      'model. The picture is stored in the model file (as an uncompressed'+
      ' bitmap, so a large picture makes the file large). Without x and y'+
      ' it is placed where no other object is; without width and height i'+
      't has the size of the picture, with one of them it keeps its propo'+
      'rtions.',
      '{"type":"object","properties":{"path":{"type":"string","descriptio'+
      'n":"PNG or BMP file"},"name":{"type":"string","description":"Name '+
      'of the image; default Image_<number>"},"x":{"type":"integer","desc'+
      'ription":"Position in the diagram, in the units of the model"},"y"'+
      ':{"type":"integer"},"width":{"type":"integer"},"height":{"type":"i'+
      'nteger"},"stretch":{"type":"boolean","description":"Scale the pict'+
      'ure to the size of the image (default true)"}},"required":["path"]'+
      '}'),
    Tool('change_image',
      'Change an image of the open model: name, place, size, whether the '+
      'picture is scaled, or another picture from a file. Only what is gi'+
      'ven is changed.',
      '{"type":"object","properties":{"image":{"type":"string","descripti'+
      'on":"Name of the image"},"new_name":{"type":"string"},"path":{"typ'+
      'e":"string","description":"PNG or BMP file with another picture"},'+
      '"x":{"type":"integer","description":"Position in the diagram, in t'+
      'he units of the model"},"y":{"type":"integer"},"width":{"type":"in'+
      'teger"},"height":{"type":"integer"},"stretch":{"type":"boolean"}},'+
      '"required":["image"]}'),
    Tool('delete_image',
      'Delete an image of the open model.',
      '{"type":"object","properties":{"image":{"type":"string","descripti'+
      'on":"Name of the image"}},"required":["image"]}'),
    Tool('export_model_image',
      'Write the diagram of the open model to a picture file, as the prog'+
      'ram exports it: tables, relations, regions, notes and images, the '+
      'area of the objects at 100 percent. Use it to look at the layout.',
      '{"type":"object","properties":{"path":{"type":"string","descriptio'+
      'n":"File to write, ending with .png, .jpg or .bmp"},"overwrite":{"'+
      'type":"boolean","description":"Replace an existing file (default f'+
      'alse)"}},"required":["path"]}'),
    Tool('list_datatypes',
      'The datatypes of the open model: name, id, group, parameters, opti'+
      'ons, the name in the SQL code if it is another one, and how many c'+
      'olumns have the datatype. A model may have datatypes of the same n'+
      'ame in different groups.',
      '{"type":"object","properties":{"group":{"type":"string","descripti'+
      'on":"Only the datatypes of this group"},"used_only":{"type":"boole'+
      'an","description":"Only datatypes that columns have (default false'+
      ')"}}}'),
    Tool('add_datatype',
      'Add a datatype to the open model, in the group of the user defined'+
      ' datatypes unless another one is named.',
      '{"type":"object","properties":{"name":{"type":"string","descriptio'+
      'n":"Name of the datatype"},"group":{"type":"string","description":'+
      '"Datatype group of the model, see list_datatypes"},"description":{'+
      '"type":"string"},"parameters":{"type":"array","items":{"type":"str'+
      'ing"},"description":"Names of the parameters in the brackets, e.g.'+
      ' [\"length\"] or [\"precision\",\"scale\"]; at most 6"},"parameter'+
      's_required":{"type":"boolean","description":"A column has to give '+
      'the parameters"},"options":{"type":"array","items":{"type":"string'+
      '"},"description":"Words a column may add, e.g. UNSIGNED; at most 6'+
      '"},"sql_name":{"type":"string","description":"The name written in '+
      'the SQL code instead of the name of the datatype; empty for none"}'+
      '},"required":["name"]}'),
    Tool('change_datatype',
      'Change a datatype of the open model: name, group, description, par'+
      'ameters, options or the name in the SQL code. Only what is given i'+
      's changed; the columns that have the datatype keep it.',
      '{"type":"object","properties":{"datatype":{"type":"string","descri'+
      'ption":"Name of the datatype"},"id":{"type":"integer","description'+
      '":"Id of the datatype instead of its name, for one of several with'+
      ' the same name"},"new_name":{"type":"string"},"group":{"type":"str'+
      'ing","description":"Datatype group of the model, see list_datatype'+
      's"},"description":{"type":"string"},"parameters":{"type":"array","'+
      'items":{"type":"string"},"description":"Names of the parameters in'+
      ' the brackets, e.g. [\"length\"] or [\"precision\",\"scale\"]; at '+
      'most 6"},"parameters_required":{"type":"boolean","description":"A '+
      'column has to give the parameters"},"options":{"type":"array","ite'+
      'ms":{"type":"string"},"description":"Words a column may add, e.g. '+
      'UNSIGNED; at most 6"},"sql_name":{"type":"string","description":"T'+
      'he name written in the SQL code instead of the name of the datatyp'+
      'e; empty for none"}}}'),
    Tool('delete_datatype',
      'Delete a datatype of the open model. If columns have it, replace_w'+
      'ith has to name the datatype they get. The default datatype of the'+
      ' model cannot be deleted.',
      '{"type":"object","properties":{"datatype":{"type":"string","descri'+
      'ption":"Name of the datatype"},"id":{"type":"integer","description'+
      '":"Id of the datatype instead of its name"},"replace_with":{"type"'+
      ':"string","description":"Datatype for the columns that have the de'+
      'leted one"}}}'),
    Tool('arrange_tables',
      'Lay tables of the open model side by side in rows, without overlap'+
      's and with room for the lines of the relations. Without tables: al'+
      'l tables, in the order of their foreign keys (not for a model with'+
      ' regions). Notes and images are not moved. Use export_model_image '+
      'to look at the result.',
      '{"type":"object","properties":{"tables":{"type":"array","items":{"'+
      'type":"string"},"description":"Only these tables, in this order"},'+
      '"x":{"type":"integer","description":"Place of the first table (def'+
      'ault 40)"},"y":{"type":"integer"},"row_width":{"type":"integer","d'+
      'escription":"Width after which a new row begins (default 1400)"}}}'),
    Tool('save_model',
      'Write the open model to its file, or to path. The file as it was i'+
      's kept as <file>.bak. A file other than the one of the model is re'+
      'placed only with overwrite.',
      '{"type":"object","properties":{"path":{"type":"string","descriptio'+
      'n":"Another file than the one the model was opened from"},"overwri'+
      'te":{"type":"boolean","description":"Replace an existing other fil'+
      'e"}}}'),
    Tool('list_connections',
      'The database connections stored in DBDesigner Fork (name, driver, '+
      'host, database, user, whether the password is stored). No password'+
      's are returned.',
      '{"type":"object","properties":{}}'),
    Tool('connect_database',
      'Connect to a Firebird database: a stored connection by its name (p'+
      'referred, its stored password is used), or database with host, por'+
      't and user. Without host the embedded engine opens the database fi'+
      'le. One connection is open at a time.',
      '{"type":"object","properties":{"connection":{"type":"string","desc'+
      'ription":"Name of a stored connection, see list_connections"},"dat'+
      'abase":{"type":"string","description":"Database file or alias, whe'+
      'n no stored connection is used"},"host":{"type":"string","descript'+
      'ion":"Server; leave it out for the embedded engine"},"port":{"type'+
      '":"integer","description":"Default 3050"},"user":{"type":"string",'+
      '"description":"Default SYSDBA"},"password":{"type":"string","descr'+
      'iption":"Only if it is not stored with the connection"},"client_li'+
      'brary":{"type":"string","description":"Path of fbclient.dll, if it'+
      ' is not found next to the program or in an installed Firebird"},"c'+
      'reate":{"type":"boolean","description":"Embedded engine: create th'+
      'e database file if it does not exist (default false)"}}}'),
    Tool('disconnect_database',
      'Close the database connection.',
      '{"type":"object","properties":{}}'),
    Tool('list_database_tables',
      'The tables of the connected database, and whether the open model h'+
      'as a table of that name.',
      '{"type":"object","properties":{}}'),
    Tool('reverse_engineer',
      'Read tables of the connected Firebird database into the open model'+
      ': columns, primary keys, indices, comments, and the foreign keys a'+
      's relations. Tables that are in the model already are left as they'+
      ' are. The database is only read; the change of the model is in mem'+
      'ory until save_model.',
      '{"type":"object","properties":{"tables":{"type":"array","items":{"'+
      'type":"string"},"description":"Only these tables; default: all tab'+
      'les of the database"},"relations":{"type":"boolean","description":'+
      '"Make relations (default true)"},"relation_guess":{"type":"string"'+
      ',"enum":["by_name","by_primary_key"],"description":"Relations beyo'+
      'nd the foreign keys of the database: by_name (default) for a colum'+
      'n id<table>, by_primary_key for tables that contain the primary ke'+
      'y columns of another table (many wrong relations when every table '+
      'has a primary key column of the same name)"}}}'),
    Tool('sync_database',
      'Change the connected Firebird database to match the open model: mi'+
      'ssing tables are created, existing ones altered (columns, indices,'+
      ' primary and foreign keys; a column that is not in the model is dr'+
      'opped with its data). Tables that are only in the database are kep'+
      't. Without apply nothing is changed and the tables that would be c'+
      'reated or compared are returned; call it that way first and show t'+
      'he result to the user. With apply true the changes are made and ca'+
      'nnot be undone.',
      '{"type":"object","properties":{"apply":{"type":"boolean","descript'+
      'ion":"Make the changes (default false: only report)"},"standard_in'+
      'serts":{"type":"boolean","description":"Run the standard inserts o'+
      'f the model for newly created tables (default false)"}}}')
    ])]);
end;

//A tool result: the data as JSON text, or the error text
function ToolResult(const Text: string; IsError: Boolean): TJSONObject;
begin
  Result:=TJSONObject.Create(['content', TJSONArray.Create([
    TJSONObject.Create(['type', 'text', 'text', Text])]),
    'isError', IsError]);
end;

function CallTool(Params: TJSONObject): TJSONObject;
var Name, Text: string;
  Args: TJSONObject;
  Data: TJSONData;
begin
  if(Params=nil)then
    raise ERpcError.Create(-32602, 'Missing params');
  Name:=ArgStr(Params, 'name');
  Args:=nil;
  if(Params.IndexOfName('arguments')>=0)and(Params.Types['arguments']=jtObject)then
    Args:=Params.Objects['arguments'];

  DialogMessages.Clear;
  try
    if(Name='open_model')then
      Data:=ToolOpenModel(Args)
    else if(Name='list_tables')then
      Data:=ToolListTables(Args)
    else if(Name='describe_table')then
      Data:=ToolDescribeTable(Args)
    else if(Name='list_relations')then
      Data:=ToolListRelations(Args)
    else if(Name='export_sql')then
      Data:=ToolExportSQL(Args)
    else if(Name='new_model')then
      Data:=ToolNewModel(Args)
    else if(Name='add_table')then
      Data:=ToolAddTable(Args)
    else if(Name='add_column')then
      Data:=ToolAddColumn(Args)
    else if(Name='add_relation')then
      Data:=ToolAddRelation(Args)
    else if(Name='save_model')then
      Data:=ToolSaveModel(Args)
    else if(Name='move_table')then
      Data:=ToolMoveTable(Args)
    else if(Name='list_regions')then
      Data:=ToolListRegions(Args)
    else if(Name='add_region')then
      Data:=ToolAddRegion(Args)
    else if(Name='change_region')then
      Data:=ToolChangeRegion(Args)
    else if(Name='delete_region')then
      Data:=ToolDeleteRegion(Args)
    else if(Name='list_notes')then
      Data:=ToolListNotes(Args)
    else if(Name='add_note')then
      Data:=ToolAddNote(Args)
    else if(Name='change_note')then
      Data:=ToolChangeNote(Args)
    else if(Name='delete_note')then
      Data:=ToolDeleteNote(Args)
    else if(Name='get_model_settings')then
      Data:=ToolGetModelSettings(Args)
    else if(Name='change_model_settings')then
      Data:=ToolChangeModelSettings(Args)
    else if(Name='list_images')then
      Data:=ToolListImages(Args)
    else if(Name='add_image')then
      Data:=ToolAddImage(Args)
    else if(Name='change_image')then
      Data:=ToolChangeImage(Args)
    else if(Name='delete_image')then
      Data:=ToolDeleteImage(Args)
    else if(Name='export_model_image')then
      Data:=ToolExportModelImage(Args)
    else if(Name='list_datatypes')then
      Data:=ToolListDatatypes(Args)
    else if(Name='add_datatype')then
      Data:=ToolAddDatatype(Args)
    else if(Name='change_datatype')then
      Data:=ToolChangeDatatype(Args)
    else if(Name='delete_datatype')then
      Data:=ToolDeleteDatatype(Args)
    else if(Name='arrange_tables')then
      Data:=ToolArrangeTables(Args)
    else if(Name='rename_table')then
      Data:=ToolRenameTable(Args)
    else if(Name='change_column')then
      Data:=ToolChangeColumn(Args)
    else if(Name='delete_column')then
      Data:=ToolDeleteColumn(Args)
    else if(Name='delete_table')then
      Data:=ToolDeleteTable(Args)
    else if(Name='delete_relation')then
      Data:=ToolDeleteRelation(Args)
    else if(Name='add_index')then
      Data:=ToolAddIndex(Args)
    else if(Name='delete_index')then
      Data:=ToolDeleteIndex(Args)
    else if(Name='list_connections')then
      Data:=ToolListConnections(Args)
    else if(Name='connect_database')then
      Data:=ToolConnectDatabase(Args)
    else if(Name='disconnect_database')then
      Data:=ToolDisconnectDatabase(Args)
    else if(Name='list_database_tables')then
      Data:=ToolListDatabaseTables(Args)
    else if(Name='reverse_engineer')then
      Data:=ToolReverseEngineer(Args)
    else if(Name='sync_database')then
      Data:=ToolSyncDatabase(Args)
    else
      raise ERpcError.Create(-32602, 'Unknown tool: '+Name);

    try
      if(Data.JSONType=jtString)then
        Text:=Data.AsString
      else
        Text:=Data.FormatJSON;
    finally
      Data.Free;
    end;
    //What the application code wanted to tell in a message box
    if(DialogMessages.Count>0)then
      Text:=Text+#10#10'Messages:'#10+U(Trim(DialogMessages.Text));
    Result:=ToolResult(Text, False);
  except
    on E: ERpcError do
      raise;
    on E: Exception do
    begin
      Text:=E.Message;
      if(Not(E is EToolError))then
        Text:=E.ClassName+': '+Text;
      if(DialogMessages.Count>0)then
        Text:=Text+#10+Trim(DialogMessages.Text);
      Result:=ToolResult(U(Text), True);
    end;
  end;

  //The application code posts events to the main form: drop them
  Application.ProcessMessages;
end;

function Initialize(Params: TJSONObject): TJSONObject;
var Version: string;
  i: integer;
begin
  Version:=ProtocolVersions[0];
  for i:=Low(ProtocolVersions) to High(ProtocolVersions) do
    if(ProtocolVersions[i]=ArgStr(Params, 'protocolVersion'))then
      Version:=ProtocolVersions[i];

  Result:=TJSONObject.Create([
    'protocolVersion', Version,
    'capabilities', TJSONObject.Create(['tools', TJSONObject.Create]),
    'serverInfo', TJSONObject.Create(['name', ServerName, 'version', ServerVersion]),
    'instructions', 'Reads and changes DBDesigner Fork database models. Open '+
      'a model file with open_model (or start one with new_model) first, the '+
      'other tools work on the open model. Changes are in memory until '+
      'save_model. The database tools (Firebird) need connect_database; '+
      'sync_database changes the database, call it without apply first.']);
end;

procedure HandleMessage(const Line: string);
var Msg: TJSONData;
  Req, Params: TJSONObject;
  ID: TJSONData;
  Method: string;
begin
  Msg:=nil;
  try
    try
      Msg:=GetJSON(Line);
    except
      on E: Exception do
      begin
        SendError(nil, -32700, 'Parse error: '+E.Message);
        Exit;
      end;
    end;
    if(Msg=nil)or(Msg.JSONType<>jtObject)then
    begin
      SendError(nil, -32600, 'Invalid request');
      Exit;
    end;

    Req:=TJSONObject(Msg);
    ID:=Req.Find('id');
    Method:=ArgStr(Req, 'method');
    Params:=nil;
    if(Req.IndexOfName('params')>=0)and(Req.Types['params']=jtObject)then
      Params:=Req.Objects['params'];

    //Answers of the client and notifications get no answer
    if(Method='')or(ID=nil)then
      Exit;

    try
      if(Method='initialize')then
        SendResult(ID, Initialize(Params))
      else if(Method='ping')then
        SendResult(ID, TJSONObject.Create)
      else if(Method='tools/list')then
        SendResult(ID, ToolList)
      else if(Method='tools/call')then
        SendResult(ID, CallTool(Params))
      else
        SendError(ID, -32601, 'Method not found: '+Method);
    except
      on E: ERpcError do
        SendError(ID, E.Code, E.Message);
      on E: Exception do
        SendError(ID, -32603, E.ClassName+': '+E.Message);
    end;
  finally
    Msg.Free;
  end;
end;

var Line: string;
begin
  //stdout carries the protocol: the WriteLn output of the application code
  //must not get there
  AssignFile(Output, {$IFDEF MSWINDOWS}'NUL'{$ELSE}'/dev/null'{$ENDIF});
  Rewrite(Output);

  StdIn:=TIOStream.Create(iosInput);
  StdOut:=TIOStream.Create(iosOutput);
  DialogMessages:=TStringList.Create;

  //The settings of the program (and its list of connections) are read but
  //never written from here
  SettingsReadOnly:=True;

  Application.Initialize;
  InterfaceBase.PromptDialogFunction:=@McpPromptDialog;
  Forms.MessageBoxFunction:=@McpMessageBox;

  //The main form is never shown. The application code posts events to it
  //and the model needs a parent
  Application.CreateForm(TForm, ParentForm);
  DMMain:=TDMMain.Create(ParentForm);
  //The settings files have the name of the program in their names. The
  //server works with the settings of DBDesigner Fork (defaults of a new
  //model, region colours, options of the SQL code), not with a file of
  //its own
  DMMain.ProgName:='DBDesignerFork';
  DMDB:=TDMDB.Create(ParentForm);
  DMEER:=TDMEER.Create(ParentForm);

  while(ReadMessage(Line))do
    if(Trim(Line)<>'')then
      HandleMessage(Line);
end.
