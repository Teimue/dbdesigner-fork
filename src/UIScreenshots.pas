unit UIScreenshots;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit UIScreenshots.pas
// ----------------------
// Description
//   Saves a picture of every dialog of the program, with every page of its
//   page controls, to check the layout (other fonts, translations, DPI):
//
//     DBDesignerFork --screenshots <directory>
//
//   The program opens the order example, shows one dialog after the other,
//   writes <dialog>[_<page>].png into the directory and ends. Like --selftest
//   it runs with read-only settings. The dialogs that need a database are
//   shown without a connection, i.e. empty.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, Forms;

//--screenshots <directory> on the command line
function HasScreenshotParam: Boolean;

procedure SaveDialogScreenshots(AMainForm: TForm);

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  LCLType, LCLIntf, Controls, Graphics, ExtCtrls, ComCtrls, Contnrs,
  Main, MainDM, DBDM, EER, EERModel, EERDM,
  Options, OptionsModel, EERExportSQLScript, EERPageSetup,
  PaletteDataTypesReplace, ZoomSel, DBConnSelect, DBConnEditor, DBConnLogin,
  EERReverseEngineering, EERSynchronisation, EERStoreInDatabase,
  EERPlaceModel, EditorString, EditorDatatype, EditorTableFieldParam,
  Tips, Splash, EditorQueryDragTarget, EditorImage;

{$IFDEF MSWINDOWS}
function PrintWindow(hwnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';
{$ENDIF}

type
  TShooter = class
    procedure OnTimer(Sender: TObject);
  end;

var
  OutDir: string;
  Shooter: TShooter;
  ShotTimer: TTimer;
  ShotName: string;
  ShotFired: Boolean;
  Baseline: TList;      //the forms that were visible before the action
  Existing: TList;      //the forms that existed before the action
  Model: TEERModel;
  Conn: TDBConn;        //a SQLite database for the dialogs that need one
  Report: TStringList;

function ScreenshotDir: string;
var i: integer;
begin
  Result:='';
  for i:=1 to ParamCount-1 do
    if(CompareText(ParamStr(i), '--screenshots')=0)then
      Result:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(i+1)));
end;

function HasScreenshotParam: Boolean;
begin
  Result:=(ScreenshotDir<>'');
end;

procedure Pump(ms: integer);
var t: QWord;
begin
  t:=GetTickCount64;
  repeat
    Application.ProcessMessages;
    Sleep(15);
  until GetTickCount64-t>=QWord(ms);
  Application.ProcessMessages;
end;

//The window as Windows paints it, with its frame
procedure SaveForm(F: TCustomForm; const FileName: string);
var bmp: Graphics.TBitmap;
  png: TPortableNetworkGraphic;
  {$IFDEF MSWINDOWS}
  R: TRect;
  ScreenDC, MemDC: HDC;
  hBmp, hOld: HBITMAP;
  {$ENDIF}
begin
  bmp:=nil;
  png:=TPortableNetworkGraphic.Create;
  try
    {$IFDEF MSWINDOWS}
    bmp:=Graphics.TBitmap.Create;
    Windows.GetWindowRect(F.Handle, R);
    ScreenDC:=Windows.GetDC(0);
    MemDC:=Windows.CreateCompatibleDC(ScreenDC);
    hBmp:=Windows.CreateCompatibleBitmap(ScreenDC, R.Right-R.Left, R.Bottom-R.Top);
    hOld:=Windows.SelectObject(MemDC, hBmp);
    //2 = PW_RENDERFULLCONTENT
    PrintWindow(F.Handle, MemDC, 2);
    Windows.SelectObject(MemDC, hOld);
    Windows.DeleteDC(MemDC);
    Windows.ReleaseDC(0, ScreenDC);
    //the bitmap owns the handle from here
    bmp.Handle:=hBmp;
    {$ELSE}
    bmp:=F.GetFormImage;
    {$ENDIF}
    png.Assign(bmp);
    png.SaveToFile(FileName);
    Report.Add(ExtractFileName(FileName)+#9+F.ClassName+#9+
      IntToStr(bmp.Width)+'x'+IntToStr(bmp.Height));
  finally
    png.Free;
    bmp.Free;
  end;
end;

//One picture of the form, or one for every page of its page controls
procedure SaveFormPages(F: TCustomForm; const BaseName: string);
var PageControls: TList;
  i, p: integer;
  PC: TPageControl;
  Prev: TTabSheet;
begin
  PageControls:=TList.Create;
  try
    for i:=0 to F.ComponentCount-1 do
      if(F.Components[i] is TPageControl)then
        if(TPageControl(F.Components[i]).PageCount>1)then
          PageControls.Add(F.Components[i]);

    SaveForm(F, OutDir+BaseName+'.png');

    for i:=0 to PageControls.Count-1 do
    begin
      PC:=TPageControl(PageControls[i]);
      Prev:=PC.ActivePage;
      for p:=0 to PC.PageCount-1 do
        if(PC.Pages[p]<>Prev)then
        begin
          PC.ActivePage:=PC.Pages[p];
          Pump(120);
          SaveForm(F, OutDir+BaseName+'_'+PC.Pages[p].Name+'.png');
        end;
      PC.ActivePage:=Prev;
      Pump(60);
    end;
  finally
    PageControls.Free;
  end;
end;

//Save every form the current action has opened, then close it
procedure TShooter.OnTimer(Sender: TObject);
var i, n: integer;
  F: TCustomForm;
  Shown: TList;
begin
  ShotTimer.Enabled:=False;
  if(ShotFired)then
    Exit;
  ShotFired:=True;

  Shown:=TList.Create;
  try
    for i:=0 to Screen.CustomFormCount-1 do
    begin
      F:=Screen.CustomForms[i];
      if(F.Visible)and(F<>Application.MainForm)and(Baseline.IndexOf(F)=-1)and
        (Not(F is TEERForm))then
        Shown.Add(F);
    end;

    if(Shown.Count=0)then
      Report.Add(ShotName+#9'NO FORM SHOWN');

    n:=0;
    for i:=0 to Shown.Count-1 do
    begin
      F:=TCustomForm(Shown[i]);
      try
        if(n=0)then
          SaveFormPages(F, ShotName)
        else
          SaveFormPages(F, ShotName+'_'+F.ClassName);
        inc(n);
      except
        on x: Exception do
          Report.Add(ShotName+#9'ERROR saving '+F.ClassName+': '+x.Message);
      end;
    end;

    //the last one opened first
    for i:=Shown.Count-1 downto 0 do
    begin
      F:=TCustomForm(Shown[i]);
      try
        if(fsModal in F.FormState)then
          F.ModalResult:=mrCancel
        else
          F.Close;
      except
      end;
    end;
  finally
    Shown.Free;
  end;
end;

function FirstObject(ObjType: TEERObject; const PreferName: string = ''): TEERObj;
var theList: TList;
  i: integer;
begin
  Result:=nil;
  theList:=TList.Create;
  try
    Model.GetEERObjectList([ObjType], theList);
    if(theList.Count>0)then
      Result:=TEERObj(theList[0]);
    for i:=0 to theList.Count-1 do
      if(CompareText(TEERObj(theList[i]).ObjName, PreferName)=0)then
        Result:=TEERObj(theList[i]);
  finally
    theList.Free;
  end;
end;

//The dialogs. False when there is no action with this index
function DoAction(Index: integer; var AName: string; Run: Boolean): Boolean;
var F: TForm;
  Obj: TEERObj;
  theList: TList;

  procedure Modal(theForm: TForm);
  begin
    try
      theForm.ShowModal;
    finally
      theForm.Free;
    end;
  end;

begin
  Result:=True;
  F:=nil;
  case Index of
    0: begin
      AName:='Options';
      if(Run)then
        Modal(TOptionsForm.Create(Application.MainForm));
    end;
    1: begin
      AName:='OptionsModel';
      if(Run)then
      begin
        F:=TOptionsModelForm.Create(Application.MainForm);
        TOptionsModelForm(F).SetModel(Model);
        Modal(F);
      end;
    end;
    2: begin
      AName:='ExportSQLScript';
      if(Run)then
      begin
        F:=TEERExportSQLScriptFrom.Create(Application.MainForm);
        TEERExportSQLScriptFrom(F).SetModel(Model);
        Modal(F);
      end;
    end;
    3: begin
      AName:='PageSetup';
      if(Run)then
      begin
        F:=TEERPageSetupForm.Create(Application.MainForm);
        TEERPageSetupForm(F).SetModel(Model);
        Modal(F);
      end;
    end;
    4: begin
      AName:='ReplaceDatatypes';
      if(Run)then
      begin
        F:=TPaletteDataTypesReplaceForm.Create(Application.MainForm);
        TPaletteDataTypesReplaceForm(F).SetModel(Model);
        Modal(F);
      end;
    end;
    5: begin
      AName:='ZoomSel';
      if(Run)then
        Modal(TZoomSelForm.Create(Application.MainForm));
    end;
    6: begin
      AName:='DBConnSelect';
      if(Run)then
      begin
        DBConnSelectForm:=TDBConnSelectForm.Create(Application.MainForm);
        try
          DBConnSelectForm.SetData(DMDB.DBConnections, nil);
          DBConnSelectForm.ShowModal;
        finally
          FreeAndNil(DBConnSelectForm);
        end;
      end;
    end;
    7: begin
      AName:='DBConnEditor';
      if(Run)then
      begin
        theList:=TList.Create;
        DBConnEditorForm:=TDBConnEditorForm.Create(Application.MainForm);
        try
          DBConnEditorForm.SetData(nil, theList, 'Firebird');
          DBConnEditorForm.ShowModal;
        finally
          FreeAndNil(DBConnEditorForm);
          theList.Free;
        end;
      end;
    end;
    8: begin
      AName:='DBConnLogin';
      if(Run)then
      begin
        F:=TDBConnLoginForm.Create(Application.MainForm);
        TDBConnLoginForm(F).SetData('SYSDBA');
        Modal(F);
      end;
    end;
    9: begin
      AName:='ReverseEngineering';
      if(Run)then
      begin
        F:=TEERReverseEngineeringForm.Create(Application.MainForm);
        //SetData asks for a connection, which nobody answers here, and
        //leaves the program disconnected
        TEERReverseEngineeringForm(F).SetData(Model);
        DMDB.ConnectToDB(Conn);
        Modal(F);
      end;
    end;
    10: begin
      AName:='Synchronisation';
      if(Run)then
      begin
        F:=TEERSynchronisationForm.Create(Application.MainForm);
        TEERSynchronisationForm(F).SetData(Model);
        DMDB.ConnectToDB(Conn);
        Modal(F);
      end;
    end;
    11: begin
      AName:='StoreInDatabase';
      if(Run)then
        Modal(TEERStoreInDatabaseForm.Create(Application.MainForm));
    end;
    12: begin
      //Empty: its content is the model that is placed
      AName:='PlaceModel';
      if(Run)then
        Modal(TEERPlaceModelForm.Create(Application.MainForm));
    end;
    13: begin
      AName:='EditorString';
      if(Run)then
      begin
        F:=TEditorStringForm.Create(Application.MainForm);
        TEditorStringForm(F).SetParams('Rename', 'Name:', 'product');
        Modal(F);
      end;
    end;
    14: begin
      AName:='EditorDatatype';
      if(Run)then
      begin
        F:=TEditorDatatypeForm.Create(Application.MainForm);
        TEditorDatatypeForm(F).SetDataType(Model,
          TEERDatatype(Model.GetDataType(Model.DefaultDataType)));
        Modal(F);
      end;
    end;
    15: begin
      AName:='EditorTableFieldParam';
      if(Run)then
      begin
        F:=TEditorTableFieldParamForm.Create(Application.MainForm);
        TEditorTableFieldParamForm(F).SetData(
          TEERDatatype(Model.GetDataTypeByName('DECIMAL')), '(10,2)');
        Modal(F);
      end;
    end;
    16: begin
      AName:='Tips';
      if(Run)then
        TTipsForm.Create(Application.MainForm).Show;
    end;
    17: begin
      AName:='EditorQueryDragTarget';
      if(Run)then
        TEditorQueryDragTargetForm.Create(Application.MainForm).Show;
    end;
    18: begin
      AName:='Splash';
      if(Run)then
        TSplashForm.Create(Application.MainForm).Show;
    end;
    19: begin
      AName:='EditorTable';
      if(Run)then
      begin
        Obj:=FirstObject(EERTable, 'product');
        if(Obj<>nil)then
          Obj.ShowEditor(nil);
      end;
    end;
    20: begin
      AName:='EditorRelation';
      if(Run)then
      begin
        Obj:=FirstObject(EERRelation, 'OnlineorderRel');
        if(Obj<>nil)then
          Obj.ShowEditor(nil);
      end;
    end;
    21: begin
      AName:='EditorRegion';
      if(Run)then
      begin
        Obj:=FirstObject(EERRegion);
        if(Obj<>nil)then
          Obj.ShowEditor(nil);
      end;
    end;
    22: begin
      AName:='EditorNote';
      if(Run)then
      begin
        Obj:=FirstObject(EERNote);
        if(Obj<>nil)then
          Obj.ShowEditor(nil);
      end;
    end;
    23: begin
      AName:='EditorImage';
      if(Run)then
      begin
        F:=TEditorImageForm.Create(Application.MainForm);
        TEditorImageForm(F).SetImage(TEERImage(Model.NewImage(50, 50, 100, 100, True)));
        Modal(F);
      end;
    end;
  else
    Result:=False;
  end;
end;

procedure SaveDialogScreenshots(AMainForm: TForm);
var i, k, Open: integer;
  AName, TestFile, DBFile: string;
  EERFrm: TEERForm;
  t: QWord;
begin
  OutDir:=ScreenshotDir;
  ForceDirectories(OutDir);

  Report:=TStringList.Create;
  Baseline:=TList.Create;
  Existing:=TList.Create;
  Shooter:=TShooter.Create;
  ShotTimer:=TTimer.Create(nil);
  ShotTimer.Enabled:=False;
  ShotTimer.OnTimer:=Shooter.OnTimer;
  try
    //Close the tips window of the start
    for i:=Screen.FormCount-1 downto 0 do
      if(Screen.Forms[i]<>AMainForm)and(Screen.Forms[i].Visible)and
        (Screen.Forms[i] is TTipsForm)then
        Screen.Forms[i].Close;

    //The order example
    TestFile:=ExtractFilePath(Application.ExeName)+'Examples'+PathDelim+'order.xml';
    EERFrm:=TEERForm.Create(AMainForm);
    EERFrm.EERModel.LoadFromFile(TestFile, True, False, True, False);
    EERFrm.WindowState:=wsMaximized;
    Model:=EERFrm.EERModel;
    Pump(800);

    SaveForm(AMainForm, OutDir+'MainForm.png');

    //A SQLite database with two tables for the dialogs that need a
    //connection (reverse engineering, synchronisation)
    DBFile:=GetTempDir+'dbdesigner_screenshots.db';
    if(FileExists(DBFile))then
      SysUtils.DeleteFile(DBFile);
    Conn:=TDBConn.Create;
    Conn.Name:='Screenshots';
    Conn.DriverName:='SQLite';
    Conn.Params.Values['Database']:=DBFile;
    try
      DMDB.ConnectToDB(Conn);
      DMDB.ExecSQL('CREATE TABLE customer (idcustomer INTEGER PRIMARY KEY, name VARCHAR(45))');
      DMDB.ExecSQL('CREATE TABLE invoice (idinvoice INTEGER PRIMARY KEY, idcustomer INTEGER REFERENCES customer(idcustomer))');
    except
      on x: Exception do
        Report.Add('Database'#9'EXCEPTION '+x.Message);
    end;

    i:=0;
    while(DoAction(i, AName, False))do
    begin
      ShotName:=AName;
      ShotFired:=False;

      Baseline.Clear;
      Existing.Clear;
      for k:=0 to Screen.CustomFormCount-1 do
      begin
        Existing.Add(Screen.CustomForms[k]);
        if(Screen.CustomForms[k].Visible)then
          Baseline.Add(Screen.CustomForms[k]);
      end;

      ShotTimer.Interval:=700;
      ShotTimer.Enabled:=True;
      try
        DoAction(i, AName, True);
      except
        on x: Exception do
        begin
          Report.Add(AName+#9'EXCEPTION '+x.ClassName+': '+x.Message);
          Report.Add('   '+BackTraceStrFunc(ExceptAddr));
          for k:=0 to ExceptFrameCount-1 do
            if(k<12)then
              Report.Add('   '+BackTraceStrFunc(ExceptFrames[k]));
        end;
      end;

      //A dialog that is not modal: the action has returned at once
      t:=GetTickCount64;
      while(Not(ShotFired))and(GetTickCount64-t<5000)do
        Pump(30);
      ShotTimer.Enabled:=False;

      //Wait until the dialog is really gone (a form that frees itself on
      //close does so later). The next dialog would get it as its owner
      //window, and Windows destroys an owned window with its owner
      t:=GetTickCount64;
      repeat
        Pump(100);
        Open:=0;
        for k:=0 to Screen.CustomFormCount-1 do
          if(Existing.IndexOf(Screen.CustomForms[k])=-1)then
            inc(Open);
      until (Open=0)or(GetTickCount64-t>4000);
      if(Open>0)then
        Report.Add(AName+#9'STILL OPEN: '+IntToStr(Open)+' form(s)');
      AMainForm.SetFocus;
      Pump(100);

      inc(i);
    end;
  finally
    Report.SaveToFile(OutDir+'screenshots.txt');
    ShotTimer.Free;
    Shooter.Free;
    Baseline.Free;
    Existing.Free;
    Report.Free;
  end;
end;

end.
