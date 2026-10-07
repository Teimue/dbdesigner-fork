program DBDplugin_TestDataGenerator;

{$IFDEF MSWINDOWS}
{$I ..\..\src\DBDesigner4.inc}
{$ELSE}
{$I ../../src/DBDesigner4.inc}
{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,
  Forms,
  Main in 'Main.pas' {MainForm},
  TestDataGen in 'TestDataGen.pas',
  EERModel in '../../src/EERModel.pas',
  EERDM in '../../src/EERDM.pas' {DMEER: TDataModule},
  MainDM in '../../src/MainDM.pas' {DMMain: TDataModule},
  EditorString in '../../src/EditorString.pas' {EditorStringForm},
{$IFDEF USE_IXMLDBMODELType}
  EERModel_XML in '../../src/EERModel_XML.pas',
{$ENDIF}
  LibXmlParser in '../../src/LibXmlParser.pas';

{$R *.res}

begin
  Application.Scaled := True;
  Application.Initialize;
  Application.Title := 'Test Data Generator';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
