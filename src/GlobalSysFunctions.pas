unit GlobalSysFunctions;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of fabFORCE DBDesigner4.
// Copyright (C) 2002 Michael G. Zinner, www.fabFORCE.net
//
// DBDesigner4 is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// DBDesigner4 is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with DBDesigner4; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//----------------------------------------------------------------------------------------------------------------------
//
// Unit GlobalSysFunctions.pas
// ---------------------------
// Version 1.0, 20.08.2003, Mike
// Description
//   Sets the Global Font of the Application
//
// Changes:
//   Version 1.0, 20.08.2003, Mike
//     initial version
//
//----------------------------------------------------------------------------------------------------------------------



{$I DBDesigner4.inc}

interface

uses Forms,
  IniFiles,
  SysUtils,
  {$IFDEF MSWINDOWS}
  Windows, Messages,
  ActiveX, ShellAPI, ShlObj, // for SHGetSpecialFolderLocation() und SHGetPathFromIDList()
  {$ENDIF}
  Graphics;

procedure LoadApplicationFont;
{$IFDEF MSWINDOWS}
function GetSpecialFolder(Folder: Integer): String;
{$ENDIF}
function GetGlobalSettingsPath: string;
//The directory the open dialog starts in as long as the user has not
//opened a model: the one with the examples
function GetDefaultModelDir: string;
function GetProgramVersionStr: string;

implementation

uses
  // the version info of the program and the readers of its resources
  fileinfo, winpeimagereader, elfreader, machoreader;

//The version of the program as it is set in the project options
//(DBDesignerFork.lpi, Version Info), e.g. 1.5 for 1.5.0.0;
//an empty string when the program has no version info
function GetProgramVersionStr: string;
var
  theVersion: TProgramVersion;
  s: string;
begin
  GetProgramVersionStr:='';

  try
    if(Not(GetProgramVersion(theVersion)))then
      Exit;
  except
    Exit;
  end;

  s:=IntToStr(theVersion.Major)+'.'+IntToStr(theVersion.Minor);

  //Revision and build are only shown when they are set
  if(theVersion.Revision<>0)or(theVersion.Build<>0)then
    s:=s+'.'+IntToStr(theVersion.Revision);
  if(theVersion.Build<>0)then
    s:=s+'.'+IntToStr(theVersion.Build);

  GetProgramVersionStr:=s;
end;

{$IFDEF MSWINDOWS}
//CSIDL_COOKIES              Cookies
//CSIDL_DESKTOPDIRECTORY     Desktop
//CSIDL_FAVORITES            Favoriten
//CSIDL_HISTORY              Internet-Verlauf
//CSIDL_INTERNET_CACHE       "Temporary Internet Files"
//CSIDL_PERSONAL             Eigene Dateien               $0005
//CSIDL_PROGRAMS             "Programme" im Startmenü
//CSIDL_RECENT               "Dokumente" im Startmenü
//CSIDL_SENDTO               "Senden an" im Kontextmenü
//CSIDL_STARTMENU            Startmenü
//CSIDL_STARTUP              Autostart

//e.g. : s:=GetSpecialFolder(CSIDL_RECENT);

function GetSpecialFolder(Folder: Integer): String;
var
  Path: array[0..MAX_PATH] of WideChar;
begin
  //The wide function: the ANSI one gives the path in the code page of
  //Windows, the strings of the program are UTF-8. With an umlaut in the
  //user name the settings directory could not be created and the program
  //tried to write its settings to the Data directory next to it
  Result:='';
  Path[0]:=#0;
  if(SHGetSpecialFolderPathW(0, @Path[0], Folder, False))then
    Result:=UTF8Encode(WideString(PWideChar(@Path[0])));
end;
{$ENDIF}

function GetGlobalSettingsPath: string;
var SettingsPath: string;
{$IFDEF MSWINDOWS}
  i: integer;
  disablePersonalSettings: Boolean;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  SettingsPath:=GetSpecialFolder(CSIDL_APPDATA)+PathDelim+'DBDesigner4'+PathDelim;

  //Create DBDesigner4 settings dir if it is not disabled by start parameter
  disablePersonalSettings:=False;
  for i:=0 to ParamCount do
    if(CompareText(ParamStr(i), '-disablePersonalSettings')=0)then
    begin
      disablePersonalSettings:=True;
      break;
    end;
  if(Not(disablePersonalSettings))then
    ForceDirectories(SettingsPath);

  //Check if a DBDesigner4 Directory has been created in the Users
  //Home Directory. if not, use the Data dir in the Appl-Dir
  if(Not(DirectoryExists(SettingsPath)))then
    SettingsPath:=ExtractFilePath(Application.ExeName)+'Data'+PathDelim;
{$ELSE}
    //the settings are stored in a dir '.DBDesigner4' in the users home dir
  SettingsPath:=GetEnvironmentVariable('HOME')+PathDelim+'.DBDesigner4'+PathDelim;
{$ENDIF}

  //Create the directory if it doesn't already exist
  ForceDirectories(SettingsPath);

  GetGlobalSettingsPath:=SettingsPath;
end;

function GetDefaultModelDir: string;
var ExamplesDir: string;
{$IFDEF MSWINDOWS}
  s: string;
{$ENDIF}
begin
  //Next to the program (source tree, unpacked archive)
  ExamplesDir:=ExtractFilePath(Application.ExeName)+'Examples'+PathDelim;
  GetDefaultModelDir:=ExamplesDir;
  if(DirectoryExists(ExamplesDir))then
    Exit;

{$IFDEF MSWINDOWS}
  //The setup program puts the examples into the documents, for all users
  //or for the current user: below "Program Files" they could not be saved
  try
    s:=GetSpecialFolder(CSIDL_COMMON_DOCUMENTS)+PathDelim+'DBDesigner'+PathDelim;
    if(DirectoryExists(s))then
    begin
      GetDefaultModelDir:=s;
      Exit;
    end;

    s:=GetSpecialFolder(CSIDL_PERSONAL)+PathDelim+'DBDesigner'+PathDelim;
    if(DirectoryExists(s))then
      GetDefaultModelDir:=s;
  except
  end;
{$ENDIF}
end;

procedure LoadApplicationFont;
var theIni: TMemIniFile;
  s: string;
begin
  //Read IniFile
  theIni:=TMemIniFile.Create(GetGlobalSettingsPath+
    Copy(ExtractFileName(Application.ExeName), 1,
    Length(ExtractFileName(Application.ExeName))-
    Length(ExtractFileExt(Application.ExeName)))+'_Settings.ini');

  try
    try
{$IFDEF LINUX}
      Screen.SystemFont.Name:=theIni.ReadString('GeneralSettings', 'ApplicationFontName', 'Sans');
      Screen.SystemFont.Size:=StrToInt(theIni.ReadString('GeneralSettings', 'ApplicationFontSize', '8'));
{$ELSE}
      Screen.SystemFont.Name:=theIni.ReadString('GeneralSettings', 'ApplicationFontName', 'MS Sans Serif');
      Screen.SystemFont.Size:=StrToInt(theIni.ReadString('GeneralSettings', 'ApplicationFontSize', '8'));
{$ENDIF}
      s:=theIni.ReadString('GeneralSettings', 'ApplicationFontStyle', '');
      Screen.SystemFont.Style:=[];
      if(Pos('bold', lowercase(s))>0)then
        Screen.SystemFont.Style:=Screen.SystemFont.Style+[fsBold]
      else if(Pos('italic', lowercase(s))>0)then
        Screen.SystemFont.Style:=Screen.SystemFont.Style+[fsItalic]
      else if(Pos('underline', lowercase(s))>0)then
        Screen.SystemFont.Style:=Screen.SystemFont.Style+[fsUnderline]
      else if(Pos('strikeout', lowercase(s))>0)then
        Screen.SystemFont.Style:=Screen.SystemFont.Style+[fsStrikeOut];
    except
{$IFDEF LINUX}
      Screen.SystemFont.Name:='Sans';
      Screen.SystemFont.Size:=11;
      Screen.SystemFont.Style:=[];
{$ELSE}
      Screen.SystemFont.Name:='MS Sans Serif';
      Screen.SystemFont.Size:=8;
      Screen.SystemFont.Style:=[];
{$ENDIF}
    end;
  finally
    theIni.Free;
  end;
end;


end.
