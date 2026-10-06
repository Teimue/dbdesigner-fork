unit FirebirdLib;

// Loads the Firebird client library for ibase60dyn/IBConnection.
//
// FPC's ibase60dyn only tries the bare names (fbembed.dll, fbclient.dll,
// gds32.dll / libfbclient.so), i.e. the library has to be on the search path.
// A Firebird server installation is usually not, and the zip kit (which also
// holds the embedded engine) can be unpacked anywhere. So look for the
// library in the usual places and load it by its full path at the first
// connect; the later parameterless InitialiseIBase60 of TIBConnection then
// only bumps the reference count. The library stays loaded until the program
// ends, so the first one found is used for all connections.

{$mode delphi}

interface

//VendorLib: the VendorLib parameter of the connection, a bare library name
//or a full path. Raises an exception when no library can be loaded.
procedure LoadFirebirdLibrary(const VendorLib: string);

implementation

uses SysUtils, Classes, dynlibs, ibase60dyn
  {$IFDEF MSWINDOWS}, Windows, Registry{$ENDIF};

const
  {$IFDEF MSWINDOWS}
  DefaultLibName = 'fbclient.dll';
  {$ELSE}
  DefaultLibName = 'libfbclient.so.2';
  {$ENDIF}

var
  LibraryLoaded: Boolean = False;

{$IFDEF MSWINDOWS}
function SetDllDirectoryW(lpPathName: PWideChar): LongBool; stdcall;
  external 'kernel32.dll' name 'SetDllDirectoryW';
{$ENDIF}

{$IFDEF MSWINDOWS}
//Root directory of an installed Firebird server ('' if there is none)
function InstalledFirebirdDir: string;
var Reg: TRegistry;
begin
  Result:='';
  Reg:=TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:=HKEY_LOCAL_MACHINE;
    if(Reg.OpenKeyReadOnly('SOFTWARE\Firebird Project\Firebird Server\Instances'))then
    begin
      if(Reg.ValueExists('DefaultInstance'))then
        Result:=Reg.ReadString('DefaultInstance');
      Reg.CloseKey;
    end;
  except
    Result:='';
  end;
  Reg.Free;
end;
{$ENDIF}

function TryLoad(const LibName: string): Boolean;
{$IFDEF MSWINDOWS}
var LibDir: UnicodeString;
{$ENDIF}
begin
  Result:=False;

  //A full path that does not exist needs no load attempt
  if(ExtractFilePath(LibName)<>'')and(Not(FileExists(LibName)))then
    Exit;

  {$IFDEF MSWINDOWS}
  //The client library needs the runtime DLLs that lie next to it
  LibDir:=UnicodeString(ExtractFileDir(LibName));
  if(LibDir<>'')then
    SetDllDirectoryW(PWideChar(LibDir));
  try
  {$ENDIF}
    try
      Result:=(InitialiseIBase60(LibName)>0);
    except
      Result:=False;
    end;
  {$IFDEF MSWINDOWS}
  finally
    if(LibDir<>'')then
      SetDllDirectoryW(nil);
  end;
  {$ENDIF}
end;

procedure LoadFirebirdLibrary(const VendorLib: string);
var LibName, ExeDir, s: string;
  Candidates: TStringList;
  i: Integer;
begin
  if(LibraryLoaded)then
    Exit;

  LibName:=ExtractFileName(Trim(VendorLib));
  if(LibName='')then
    LibName:=DefaultLibName;
  ExeDir:=ExtractFilePath(ParamStr(0));

  Candidates:=TStringList.Create;
  try
    //1. the path given in the connection
    if(ExtractFilePath(Trim(VendorLib))<>'')then
      Candidates.Add(Trim(VendorLib));
    //2. FIREBIRD environment variable (root directory of an installation)
    s:=SysUtils.GetEnvironmentVariable('FIREBIRD');
    if(s<>'')then
      Candidates.Add(IncludeTrailingPathDelimiter(s)+LibName);
    //3. next to the program
    Candidates.Add(ExeDir+LibName);
    Candidates.Add(ExeDir+'firebird'+PathDelim+LibName);
    {$IFDEF MSWINDOWS}
    //4. an installed server
    s:=InstalledFirebirdDir;
    if(s<>'')then
      Candidates.Add(IncludeTrailingPathDelimiter(s)+LibName);
    {$ENDIF}
    //5. the library search path
    Candidates.Add(LibName);
    {$IFNDEF MSWINDOWS}
    Candidates.Add('libfbclient.so');
    {$ENDIF}

    for i:=0 to Candidates.Count-1 do
      if(TryLoad(Candidates[i]))then
      begin
        LibraryLoaded:=True;
        Exit;
      end;
  finally
    Candidates.Free;
  end;

  raise Exception.Create('The Firebird client library ('+LibName+') could not be loaded.'#13#10+
    'Enter its full path as VendorLib in the advanced parameters of the '+
    'connection, or copy it next to the program.');
end;

end.
