unit FirebirdConn;

// TIBConnection with a fix for the character set lookup of text blobs.
//
// TIBConnection.AddFieldDefs of FPC 3.2.2 asks isc_blob_lookup_desc for the
// character set of every text blob column of a result set. The global field
// name that function writes back goes into a buffer of 32 bytes; Firebird 4
// and newer write up to 253 bytes there (identifiers of 63 characters in
// UTF8, blank padded). That overwrites the stack: on Linux the program
// crashed in the first query with a BLOB SUB_TYPE TEXT column and the
// synchronisation hung.
//
// This class does the lookup itself with a big enough buffer, hides the
// table name of those columns from the inherited AddFieldDefs (so that it
// skips its own lookup) and sets the code page that the inherited one would
// have set. It is registered under the connector type 'Firebird' in place
// of TIBConnection.

{$mode delphi}

interface

uses
  Classes, SysUtils, DB, SQLDB, IBConnection, ibase60dyn;

type
  TFirebirdConnection = class(TIBConnection)
  private
    function BlobCharset(Cursor: TSQLCursor; PSQLVar: PXSQLVAR;
      out Charset: SmallInt): Boolean;
  protected
    procedure AddFieldDefs(cursor: TSQLCursor; FieldDefs: TFieldDefs); override;
  end;

  TFirebirdConnectionDef = class(TIBConnectionDef)
    class function ConnectionClass: TSQLConnectionClass; override;
  end;

implementation

type
  //Access to the protected fields of the cursor
  TIBCursorAccess = class(TIBCursor);

const
  CS_NONE = 0;
  CS_BINARY = 1;

function TFirebirdConnection.BlobCharset(Cursor: TSQLCursor; PSQLVar: PXSQLVAR;
  out Charset: SmallInt): Boolean;
var
  Status: array[0..19] of ISC_STATUS;
  DatabaseHandle, TransactionHandle: pointer;
  BlobDesc: TISC_BLOB_DESC;
  Global: array[0..1023] of AnsiChar;
  TableName, ColumnName: AnsiString;
begin
  SetString(TableName, PAnsiChar(@PSQLVar^.relname[0]), PSQLVar^.relname_length);
  SetString(ColumnName, PAnsiChar(@PSQLVar^.sqlname[0]), PSQLVar^.sqlname_length);
  DatabaseHandle := GetHandle;
  TransactionHandle := TIBCursorAccess(Cursor).TransactionHandle;
  FillChar(Global, SizeOf(Global), 0);
  Result := (isc_blob_lookup_desc(@Status[0], @DatabaseHandle, @TransactionHandle,
    PByte(PAnsiChar(TableName)), PByte(PAnsiChar(ColumnName)), @BlobDesc,
    @Global[0]) = 0);
  if Result then
    Charset := BlobDesc.blob_desc_charset;
end;

procedure TFirebirdConnection.AddFieldDefs(cursor: TSQLCursor; FieldDefs: TFieldDefs);
var
  i, j: Integer;
  PSQLVar: PXSQLVAR;
  Charset: SmallInt;
  SavedLength: array of SmallInt;
  NoCodePage: array of Boolean;
  Def: TFieldDef;
  AName: string;
  ADataType: TFieldType;
  ASize, APrecision: Integer;
  ARequired: Boolean;
begin
  with TIBCursorAccess(cursor) do
  begin
    SetLength(SavedLength, SQLDA^.SQLD);
    SetLength(NoCodePage, SQLDA^.SQLD);
    {$push}{$R-}
    for i := 0 to SQLDA^.SQLD - 1 do
    begin
      PSQLVar := @SQLDA^.SQLVar[i];
      SavedLength[i] := -1;
      NoCodePage[i] := False;
      //A text blob (sub type 1) of a table column: the inherited method
      //would look up its character set
      if ((PSQLVar^.SQLType and not 1) = SQL_BLOB) and (PSQLVar^.sqlsubtype = 1) and
        (PSQLVar^.relname_length > 0) and (PSQLVar^.sqlname_length > 0) then
      begin
        if BlobCharset(cursor, PSQLVar, Charset) then
          NoCodePage[i] := Charset in [CS_NONE, CS_BINARY];
        SavedLength[i] := PSQLVar^.relname_length;
        PSQLVar^.relname_length := 0;
      end;
    end;
    try
      inherited AddFieldDefs(cursor, FieldDefs);
    finally
      for i := 0 to SQLDA^.SQLD - 1 do
        if SavedLength[i] >= 0 then
          SQLDA^.SQLVar[i].relname_length := SavedLength[i];
    end;
    {$pop}
  end;

  //Character set NONE or OCTETS: no code page, as the inherited method does
  //it. The code page of a field definition can only be given when it is
  //made, so make it anew at the same place.
  for i := 0 to High(NoCodePage) do
    if NoCodePage[i] then
      for j := 0 to FieldDefs.Count - 1 do
        if FieldDefs[j].FieldNo = i + 1 then
        begin
          Def := FieldDefs[j];
          AName := Def.Name;
          ADataType := Def.DataType;
          ASize := Def.Size;
          APrecision := Def.Precision;
          ARequired := Def.Required;
          Def.Free;
          Def := FieldDefs.Add(AName, ADataType, ASize, APrecision, ARequired,
            False, i + 1, CP_NONE);
          Def.Index := j;
          Break;
        end;
end;

class function TFirebirdConnectionDef.ConnectionClass: TSQLConnectionClass;
begin
  Result := TFirebirdConnection;
end;

initialization
  RegisterConnection(TFirebirdConnectionDef);

finalization
  UnRegisterConnection(TFirebirdConnectionDef);

end.
