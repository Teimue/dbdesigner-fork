unit PasswordStore;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit PasswordStore.pas
// ----------------------
// Description
//   Protects the password of a database connection for the list of the
//   connections (DBConn.ini), which is a plain text file.
//
//   Windows: the data protection API (CryptProtectData). The result can
//   only be read again by the same Windows user on the same computer; the
//   key is kept by Windows, not by the program.
//   Other systems: not available - the password is not stored, as before.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils;

//Can a password be stored on this system?
function PasswordStoreAvailable: Boolean;

//The protected password as text for an ini file; '' when it cannot be
//protected (nothing is stored then)
function ProtectPassword(const Password: string): string;

//The password again; '' when the text is not from this user and computer
//or damaged
function UnprotectPassword(const Protected: string): string;

implementation

uses base64;

{$IFDEF MSWINDOWS}
type
  TDataBlob = record
    cbData: LongWord;
    pbData: PByte;
  end;
  PDataBlob = ^TDataBlob;

const
  CRYPTPROTECT_UI_FORBIDDEN = 1;
  //makes the data of this program differ from that of others
  Entropy: AnsiString = 'DBDesignerFork.DBConn';

function CryptProtectData(pDataIn: PDataBlob; szDataDescr: PWideChar;
  pOptionalEntropy: PDataBlob; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: LongWord; pDataOut: PDataBlob): LongBool; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';
function CryptUnprotectData(pDataIn: PDataBlob; ppszDataDescr: PPWideChar;
  pOptionalEntropy: PDataBlob; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: LongWord; pDataOut: PDataBlob): LongBool; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';
function LocalFree(hMem: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'LocalFree';
{$ENDIF}

function PasswordStoreAvailable: Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result:=True;
  {$ELSE}
  Result:=False;
  {$ENDIF}
end;

function ProtectPassword(const Password: string): string;
{$IFDEF MSWINDOWS}
var DataIn, DataOut, Ent: TDataBlob;
  Raw: AnsiString;
begin
  Result:='';
  if(Password='')then
    Exit;

  DataIn.cbData:=Length(Password);
  DataIn.pbData:=PByte(PAnsiChar(Password));
  Ent.cbData:=Length(Entropy);
  Ent.pbData:=PByte(PAnsiChar(Entropy));
  DataOut.cbData:=0;
  DataOut.pbData:=nil;

  if(CryptProtectData(@DataIn, nil, @Ent, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @DataOut))then
    try
      SetString(Raw, PAnsiChar(DataOut.pbData), DataOut.cbData);
      Result:=EncodeStringBase64(Raw);
    finally
      LocalFree(DataOut.pbData);
    end;
end;
{$ELSE}
begin
  Result:='';
end;
{$ENDIF}

function UnprotectPassword(const Protected: string): string;
{$IFDEF MSWINDOWS}
var DataIn, DataOut, Ent: TDataBlob;
  Raw: AnsiString;
begin
  Result:='';
  if(Trim(Protected)='')then
    Exit;

  try
    Raw:=DecodeStringBase64(Trim(Protected));
  except
    Exit;
  end;
  if(Raw='')then
    Exit;

  DataIn.cbData:=Length(Raw);
  DataIn.pbData:=PByte(PAnsiChar(Raw));
  Ent.cbData:=Length(Entropy);
  Ent.pbData:=PByte(PAnsiChar(Entropy));
  DataOut.cbData:=0;
  DataOut.pbData:=nil;

  if(CryptUnprotectData(@DataIn, nil, @Ent, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @DataOut))then
    try
      SetString(Result, PAnsiChar(DataOut.pbData), DataOut.cbData);
    finally
      LocalFree(DataOut.pbData);
    end;
end;
{$ELSE}
begin
  Result:='';
end;
{$ENDIF}

end.
