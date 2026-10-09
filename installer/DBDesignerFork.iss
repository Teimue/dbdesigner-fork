; Inno Setup script for DBDesigner Fork (Windows, 64 bit)
;
; Build the program, the plugins and the MCP server first (see README.md), then
;   "C:\Program Files\Inno Setup 7\ISCC.exe" installer\DBDesignerFork.iss
; The setup program is written to installer\Output.
;
; The program only reads from its directory (Data, Gfx, Doc, Examples) and
; keeps the settings of the user in %APPDATA%\DBDesigner4, so it can be
; installed below "Program Files".

#define BinDir "..\bin"
#define AppName "DBDesigner Fork"
#define AppExe "DBDesignerFork.exe"
#define AppVersion GetVersionNumbersString(BinDir + "\" + AppExe)

; The MCP server for AI assistants (mcp\DBDesignerMCP.lpi) is an optional
; part of the setup. Without the program in bin the setup is built without it.
#define McpExe "DBDesignerMCP.exe"
#if FileExists(SourcePath + BinDir + "\" + McpExe)
  #define WithMcp
#else
  #pragma warning "No " + McpExe + " in bin, the MCP server is left out"
#endif

; Firebird client and embedded engine: taken from an unpacked Firebird zip kit (64 bit),
; by default next to the repository. Another place:
;   ISCC.exe /DFirebirdDir=C:\path\to\Firebird installer\DBDesignerFork.iss
#ifndef FirebirdDir
  #define FirebirdDir "..\..\Firebird-5.0.4-x64"
#endif

[Setup]
AppId={{D2C086DD-9E03-4143-B0F7-042EA417D499}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisherURL=https://github.com/Teimue/dbdesigner-fork
AppSupportURL=https://github.com/Teimue/dbdesigner-fork
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile={#BinDir}\Copying.txt
; Windows 10 or 11, 64 bit (as the manifest of the program says)
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; for all users by default, the dialog offers an installation for the current user
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=Output
OutputBaseFilename=DBDesignerFork-{#AppVersion}-win64-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
#ifdef WithMcp
; The MCP server and its registration are offered, not preselected. The
; registrations need the server, so they are its subtasks.
Name: "mcpserver"; Description: "{cm:McpServer}"; GroupDescription: "{cm:McpGroup}"; Flags: unchecked
Name: "mcpserver\claudecode"; Description: "{cm:McpClaudeCode}"; GroupDescription: "{cm:McpGroup}"; Flags: unchecked
Name: "mcpserver\claudedesktop"; Description: "{cm:McpClaudeDesktop}"; GroupDescription: "{cm:McpGroup}"; Flags: unchecked
#endif

[Files]
; program and plugins
Source: "{#BinDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\DBDplugin_*.exe"; DestDir: "{app}"; Flags: ignoreversion
#ifdef WithMcp
; MCP server: a console program next to the program, it uses its Data and
; Gfx directories and its client libraries
Source: "{#BinDir}\{#McpExe}"; DestDir: "{app}"; Flags: ignoreversion; Tasks: mcpserver
#endif

; licence
Source: "{#BinDir}\Copying.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\Copying Addition for Win32.txt"; DestDir: "{app}"; Flags: ignoreversion
; licences of the client libraries below (the ones of Firebird lie in "firebird")
Source: "licenses\*.txt"; DestDir: "{app}\licenses"; Flags: ignoreversion

; default settings, translations, templates of the plugins
Source: "{#BinDir}\Data\*"; DestDir: "{app}\Data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BinDir}\Gfx\*"; DestDir: "{app}\Gfx"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BinDir}\Doc\*"; DestDir: "{app}\Doc"; Flags: ignoreversion recursesubdirs createallsubdirs

; The example model goes into the documents (all users: the public documents,
; current user: the own documents) - below "Program Files" it could not be
; saved. The open dialog of the program starts there (GetDefaultModelDir).
; A model the user has changed is neither overwritten nor removed.
Source: "{#BinDir}\Examples\order.xml"; DestDir: "{autodocs}\DBDesigner"; Flags: onlyifdoesntexist uninsneveruninstall

; 64 bit client libraries (SQLite, MySQL and what libmysql needs). They are
; not part of the repository; a library that is missing is left out.
; The 32 bit DLLs of the Delphi version in bin are of no use to the program.
Source: "{#BinDir}\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; The libmySQL.dll of the repository is the 32 bit one of the Delphi version
; (233 KB); only a 64 bit library (several MB) is taken.
#if FileExists(SourcePath + BinDir + "\libmySQL.dll")
  #if FileSize(SourcePath + BinDir + "\libmySQL.dll") > 1000000
Source: "{#BinDir}\libmySQL.dll"; DestDir: "{app}"; Flags: ignoreversion
  #else
    #pragma warning "bin\libmySQL.dll is not a 64 bit library, it is left out"
  #endif
#endif
Source: "{#BinDir}\libssl-3-x64.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BinDir}\libcrypto-3-x64.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BinDir}\z.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BinDir}\zstd.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; Firebird client. The program looks for fbclient.dll in the subdirectory
; "firebird" of its directory; the runtime DLLs it needs lie next to it.
#if FileExists(SourcePath + FirebirdDir + "\fbclient.dll")
Source: "{#FirebirdDir}\fbclient.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\msvcp140*.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\vcruntime140*.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\firebird.msg"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\IDPLicense.txt"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\IPLicense.txt"; DestDir: "{app}\firebird"; Flags: ignoreversion
; Embedded engine (a connection without host name opens the database file
; itself): the engine, ICU, the character sets and the time zones. This set
; has been run through tests\TestFirebirdSync. No server, no service, no
; security database; the plugins for a server (authentication, wire
; encryption, UDR, trace) are left out.
Source: "{#FirebirdDir}\plugins\engine13.dll"; DestDir: "{app}\firebird\plugins"; Flags: ignoreversion
Source: "{#FirebirdDir}\firebird.conf"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\ib_util.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\icu*.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\icudt*.dat"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\intl\*"; DestDir: "{app}\firebird\intl"; Flags: ignoreversion
Source: "{#FirebirdDir}\tzdata\*"; DestDir: "{app}\firebird\tzdata"; Flags: ignoreversion
#else
  #pragma warning "No fbclient.dll in " + FirebirdDir + ", the Firebird client is left out"
#endif

[InstallDelete]
; earlier setups put the example next to the program; the program would
; still prefer that directory
Type: files; Name: "{app}\Examples\order.xml"
Type: dirifempty; Name: "{app}\Examples"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{group}\{cm:ManualName}"; Filename: "{app}\Doc\DBDesigner4_manual_1.0.42.pdf"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[CustomMessages]
english.ManualName=DBDesigner 4 Manual
german.ManualName=DBDesigner 4 Handbuch
english.McpGroup=AI assistants (Model Context Protocol):
german.McpGroup=KI-Assistenten (Model Context Protocol):
english.McpServer=Install the MCP server (an AI assistant can read and change models with it)
german.McpServer=MCP-Server installieren (damit kann ein KI-Assistent Modelle lesen und ändern)
english.McpClaudeCode=Register the MCP server in Claude Code (for the current user)
german.McpClaudeCode=MCP-Server in Claude Code registrieren (für den aktuellen Benutzer)
english.McpClaudeDesktop=Register the MCP server in Claude Desktop (for the current user)
german.McpClaudeDesktop=MCP-Server in Claude Desktop registrieren (für den aktuellen Benutzer)
english.McpClaudeCodeFailed=The MCP server is installed, but it could not be registered in Claude Code: the command "claude" was not found or refused it.%n%nWith Claude Code installed, register it with:%n%nclaude mcp add --scope user dbdesigner -- "%1"
german.McpClaudeCodeFailed=Der MCP-Server ist installiert, konnte aber nicht in Claude Code registriert werden: Der Befehl "claude" wurde nicht gefunden oder hat es abgelehnt.%n%nMit installiertem Claude Code lässt er sich so registrieren:%n%nclaude mcp add --scope user dbdesigner -- "%1"
english.McpClaudeDesktopFailed=The MCP server is installed, but it could not be registered in Claude Desktop: Claude Desktop was not found, or its file claude_desktop_config.json could not be read.%n%nTo register it later, run:%n%n"%1" --register-claude-desktop
german.McpClaudeDesktopFailed=Der MCP-Server ist installiert, konnte aber nicht in Claude Desktop registriert werden: Claude Desktop wurde nicht gefunden, oder seine Datei claude_desktop_config.json ließ sich nicht lesen.%n%nSpäter lässt er sich so registrieren:%n%n"%1" --register-claude-desktop

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#ifdef WithMcp
[UninstallRun]
; The server takes its entries out of the clients again, only those that name
; this installation. It does so for the user who runs the uninstaller.
Filename: "{app}\{#McpExe}"; Parameters: "--unregister-claude-code"; RunOnceId: "McpClaudeCode"; Flags: runhidden skipifdoesntexist
Filename: "{app}\{#McpExe}"; Parameters: "--unregister-claude-desktop"; RunOnceId: "McpClaudeDesktop"; Flags: runhidden skipifdoesntexist

[Code]
// The registration belongs to the user who started the setup, not to the
// administrator account an installation for all users may run with: the
// server registers itself (see mcp\DBDesignerMCP.pas), started as that user.
// A failure does not undo the installation; a message says how to register
// the server later.
procedure RegisterMcpServer(const TaskName, Param, FailMessage: String);
var
  ResultCode: Integer;
  Server: String;
begin
  if not WizardIsTaskSelected(TaskName) then
    Exit;

  Server := ExpandConstant('{app}\{#McpExe}');
  if (not ExecAsOriginalUser(Server, Param, '', SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
    (ResultCode <> 0) then
    SuppressibleMsgBox(FmtMessage(CustomMessage(FailMessage), [Server]), mbInformation, MB_OK, IDOK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RegisterMcpServer('mcpserver\claudecode', '--register-claude-code', 'McpClaudeCodeFailed');
    RegisterMcpServer('mcpserver\claudedesktop', '--register-claude-desktop', 'McpClaudeDesktopFailed');
  end;
end;
#endif
