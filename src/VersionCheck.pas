unit VersionCheck;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit VersionCheck.pas
// ---------------------
// Description
//   Help menu, Check for New Versions: asks the GitHub API for the latest
//   release of the project and compares its tag (v2.1.2) with the version
//   of the program (2.1.2.7, the build number is not compared).
//
//   Windows: WinINet, which uses the certificates and TLS of the system.
//   Other systems: TFPHTTPClient with OpenSSL (libssl of the system).
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils;

const
  GitHubProjectURL = 'https://github.com/Teimue/dbdesigner-fork';
  GitHubLatestReleaseURL = GitHubProjectURL+'/releases/latest';
  GitHubLatestReleaseAPI = 'https://api.github.com/repos/Teimue/dbdesigner-fork/releases/latest';

type
  TReleaseInfo = record
    TagName: string; //v2.1.2
    Version: string; //2.1.2
    Name: string;    //DBDesigner Fork 2.1.2
    URL: string;     //the page of the release
  end;

//Gets the latest release from GitHub; False and ErrorMsg when that fails
function GetLatestRelease(out Release: TReleaseInfo; out ErrorMsg: string): Boolean;

//Compares two versions part by part (2.1.10 > 2.1.9), a leading v is
//ignored; only the first Parts parts are compared, missing parts are 0.
//Result <0 when A is older than B, 0 when equal, >0 when A is newer
function CompareVersions(const A, B: string; Parts: integer = 3): integer;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows, WinINet,
  {$ELSE}
  fphttpclient, opensslsockets,
  {$ENDIF}
  fpjson, jsonparser;

const
  TimeoutMS = 10000;
  UserAgent = 'DBDesignerFork';

{$IFDEF MSWINDOWS}
function HttpGet(const URL: string; out Body: string; out ErrorMsg: string): Boolean;
var
  hNet, hUrl: HINTERNET;
  Headers, Chunk: string;
  Buffer: array[0..8191] of Char;
  BytesRead, Status, StatusLen, Index, Timeout: DWORD;
begin
  Result:=False;
  Body:='';
  ErrorMsg:='';

  hNet:=InternetOpen(UserAgent, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if(hNet=nil)then
  begin
    ErrorMsg:=SysErrorMessage(GetLastError);
    Exit;
  end;

  try
    Timeout:=TimeoutMS;
    InternetSetOption(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOption(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));

    Headers:='Accept: application/vnd.github+json'#13#10;
    hUrl:=InternetOpenUrl(hNet, PChar(URL), PChar(Headers), Length(Headers),
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or
      INTERNET_FLAG_PRAGMA_NOCACHE or INTERNET_FLAG_SECURE, 0);
    if(hUrl=nil)then
    begin
      ErrorMsg:=SysErrorMessage(GetLastError);
      if(Trim(ErrorMsg)='')then
        ErrorMsg:='WinINet error '+IntToStr(GetLastError);
      Exit;
    end;

    try
      Status:=0;
      StatusLen:=SizeOf(Status);
      Index:=0;
      HttpQueryInfo(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
        @Status, StatusLen, Index);

      repeat
        BytesRead:=0;
        if(Not(InternetReadFile(hUrl, @Buffer, SizeOf(Buffer), BytesRead)))then
        begin
          ErrorMsg:=SysErrorMessage(GetLastError);
          Exit;
        end;
        if(BytesRead>0)then
        begin
          SetString(Chunk, PChar(@Buffer[0]), BytesRead);
          Body:=Body+Chunk;
        end;
      until(BytesRead=0);

      if(Status<>200)then
      begin
        ErrorMsg:='HTTP '+IntToStr(Status);
        Exit;
      end;

      Result:=True;
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;
{$ELSE}
function HttpGet(const URL: string; out Body: string; out ErrorMsg: string): Boolean;
var
  Client: TFPHTTPClient;
begin
  Result:=False;
  Body:='';
  ErrorMsg:='';

  Client:=TFPHTTPClient.Create(nil);
  try
    Client.ConnectTimeout:=TimeoutMS;
    Client.IOTimeout:=TimeoutMS;
    Client.AllowRedirect:=True;
    Client.AddHeader('User-Agent', UserAgent);
    Client.AddHeader('Accept', 'application/vnd.github+json');
    try
      Body:=Client.Get(URL);
    except
      on E: Exception do
      begin
        //Get raises on every status but 200
        ErrorMsg:=E.Message;
        Exit;
      end;
    end;

    Result:=True;
  finally
    Client.Free;
  end;
end;
{$ENDIF}

function GetLatestRelease(out Release: TReleaseInfo; out ErrorMsg: string): Boolean;
var
  Body: string;
  Data: TJSONData;
  Obj: TJSONObject;
begin
  Result:=False;
  Release.TagName:='';
  Release.Version:='';
  Release.Name:='';
  Release.URL:=GitHubLatestReleaseURL;

  if(Not(HttpGet(GitHubLatestReleaseAPI, Body, ErrorMsg)))then
    Exit;

  try
    Data:=GetJSON(Body);
  except
    on E: Exception do
    begin
      ErrorMsg:=E.Message;
      Exit;
    end;
  end;

  try
    if(Not(Data is TJSONObject))then
    begin
      ErrorMsg:='Unexpected answer from GitHub';
      Exit;
    end;

    Obj:=TJSONObject(Data);
    Release.TagName:=Obj.Get('tag_name', '');
    Release.Name:=Obj.Get('name', '');
    if(Obj.Get('html_url', '')<>'')then
      Release.URL:=Obj.Get('html_url', '');

    Release.Version:=Release.TagName;
    if(Release.Version<>'')and(Release.Version[1] in ['v', 'V'])then
      Delete(Release.Version, 1, 1);

    if(Release.Version='')then
    begin
      ErrorMsg:='The release has no tag';
      Exit;
    end;

    Result:=True;
  finally
    Data.Free;
  end;
end;

function CompareVersions(const A, B: string; Parts: integer = 3): integer;

  //The next number of the version from position P on
  function NextPart(const s: string; var P: integer): integer;
  begin
    Result:=0;
    while(P<=Length(s))and(s[P] in ['0'..'9'])do
    begin
      Result:=Result*10+Ord(s[P])-Ord('0');
      inc(P);
    end;
    //skip the dot (and whatever is not a number, e.g. -beta)
    while(P<=Length(s))and(Not(s[P] in ['0'..'9']))do
      inc(P);
  end;

var
  i, PA, PB, NA, NB: integer;
begin
  Result:=0;
  PA:=1;
  PB:=1;
  if(A<>'')and(A[1] in ['v', 'V'])then
    PA:=2;
  if(B<>'')and(B[1] in ['v', 'V'])then
    PB:=2;

  for i:=1 to Parts do
  begin
    NA:=NextPart(A, PA);
    NB:=NextPart(B, PB);
    if(NA<>NB)then
    begin
      if(NA<NB)then
        Result:=-1
      else
        Result:=1;
      Exit;
    end;
  end;
end;

end.
