; Inno Setup script for DBDesigner Fork (Windows, 64 bit)
;
; Build the program and the plugins first (see README.md), then
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

; Firebird client library: taken from an unpacked Firebird zip kit (64 bit),
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

[Files]
; program and plugins
Source: "{#BinDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\DBDplugin_*.exe"; DestDir: "{app}"; Flags: ignoreversion

; licence
Source: "{#BinDir}\Copying.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinDir}\Copying Addition for Win32.txt"; DestDir: "{app}"; Flags: ignoreversion

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

; Firebird client (connections to a server). The program looks for
; fbclient.dll in the subdirectory "firebird" of its directory; the runtime
; DLLs it needs lie next to it. The embedded engine is not packed.
#if FileExists(SourcePath + FirebirdDir + "\fbclient.dll")
Source: "{#FirebirdDir}\fbclient.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\msvcp140*.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\vcruntime140*.dll"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\firebird.msg"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\IDPLicense.txt"; DestDir: "{app}\firebird"; Flags: ignoreversion
Source: "{#FirebirdDir}\IPLicense.txt"; DestDir: "{app}\firebird"; Flags: ignoreversion
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

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
