unit MySQLClientConn;

// TMySQL80Connection that also accepts the MySQL 8.4 client library.
//
// TMySQL80Connection of FPC 3.2.2 refuses every client library whose
// version does not start with 8.0 ("can not work with the installed MySQL
// client version: Expected (8.0), got (8.4.11)"). From Ubuntu 26.04 on the
// distribution ships only libmysqlclient.so.24 of MySQL 8.4, whose C API is
// the same for what SQLDB uses (mysql_ssl_set, removed in 8.4, is not
// called). So skip the check for an 8.4 library; other versions keep it.
// Registered under the connector type 'MySQL 8.0' in place of
// TMySQL80Connection.

{$mode delphi}

interface

uses
  Classes, SysUtils, SQLDB, MySQL80Conn;

type
  TMySQLClientConnection = class(TMySQL80Connection)
  protected
    procedure DoInternalConnect; override;
  end;

  TMySQLClientConnectionDef = class(TMySQL80ConnectionDef)
    class function ConnectionClass: TSQLConnectionClass; override;
  end;

implementation

uses mysql80dyn;

procedure TMySQLClientConnection.DoInternalConnect;
var
  ClientVersion: string;
begin
  InitialiseMysql;
  try
    ClientVersion := StrPas(mysql_get_client_info());
  finally
    ReleaseMysql;
  end;
  if Pos('8.4.', ClientVersion) = 1 then
    SkipLibraryVersionCheck := True;
  inherited DoInternalConnect;
end;

class function TMySQLClientConnectionDef.ConnectionClass: TSQLConnectionClass;
begin
  Result := TMySQLClientConnection;
end;

initialization
  RegisterConnection(TMySQLClientConnectionDef);

finalization
  UnRegisterConnection(TMySQLClientConnectionDef);

end.
