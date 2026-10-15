unit UIDocImages;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit UIDocImages.pas
// --------------------
// Description
//   Makes the pictures of the HTML documentation (bin/Doc/images/docs):
//
//     DBDesignerFork --docimages <directory> --lang en
//
//   The program opens the order example and writes ui/, db/, editors/,
//   designmode/, querymode/ and fundamentals/ with the names the pages use
//   (as .png) into the directory, with a report docimages.txt, and ends.
//   Menus and popup menus are opened with the keyboard, dialogs are shown
//   modal and saved from a timer. Labels with arrows are drawn by the
//   program, cursors are painted onto the pictures. It runs with read-only
//   settings like --screenshots; the database connections and hosts shown
//   are made up for the pictures, the database is a SQLite file in the
//   temporary directory.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, Forms;

//--docimages <directory> on the command line
function HasDocImagesParam: Boolean;

procedure SaveDocImages(AMainForm: TForm; const ADir: string);

implementation

{$IFDEF MSWINDOWS}
uses
  Windows, Messages, LCLType, LCLIntf, Controls, Graphics, ExtCtrls, ComCtrls,
  StdCtrls, Grids, Menus, Buttons, Contnrs, FileUtil, Math,
  Main, MainDM, DBDM, EER, EERModel, EERDM, EERExportSQLScript,
  PaletteDataTypesReplace, PaletteDatatypes, PaletteModel, PaletteNav,
  PaletteTools, ZoomSel, DBConnSelect, DBConnEditor, EditorString,
  EditorTable, EditorRelation, EditorImage, EditorQuery,
  EditorQueryDragTarget, EERReverseEngineering, EERSynchronisation, TreeNodeSubItems;

function PrintWindow(hwnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';
function DwmGetWindowAttribute(hwnd: HWND; dwAttribute: DWORD;
  pvAttribute: Pointer; cbAttribute: DWORD): HRESULT; stdcall;
  external 'dwmapi.dll' name 'DwmGetWindowAttribute';

const
  DWMWA_EXTENDED_FRAME_BOUNDS = 9;
  PW_RENDERFULLCONTENT = 2;

type
  TNoteSide = (nsLeft, nsRight, nsTop, nsBottom);
  TNote = record
    Text: string;
    X, Y: integer;
    Side: TNoteSide;
  end;
  TNotes = array of TNote;

  //Called from a timer while a menu or a modal dialog is open,
  //True when it is done
  TDocStep = function(Phase: integer): Boolean of object;
  TDocAction = procedure of object;

  TStepRunner = class
    Timer: TTimer;
    Step: TDocStep;
    Phase: integer;
    Done: Boolean;
    procedure Tick(Sender: TObject);
  end;

  //Gives access to the mouse handling of the model objects
  TEERTableAccess = class(TEERTable);

  TDocMaker = class
  private
    OutDir: string;
    Report: TStringList;
    MainFrm: TMainForm;
    OrderForm, TutForm: TEERForm;
    Model: TEERModel;
    Conn: TDBConn;
    //what the current step works on
    CurForm: TForm;
    CurPopup: TPopupMenu;
    CurPopupPos: TPoint;
    CurMenuTop: integer;
    CurMenuSub: TMenuItem;
    CurMenuName: string;
    CurObj: TEERObj;
    CurName: string;
    CurClass: string;
    SampleConns: TObjectList;
    procedure Log(const s: string);
    procedure SavePNG(B: TBitmap; const RelName: string);
    function FindTable(const AName: string; M: TEERModel = nil): TEERTable;
    function FindObj(ObjType: TEERObject; const AName: string; M: TEERModel = nil): TEERObj;
    procedure ScrollHome(F: TEERForm);
    function ToolLabel(C: TControl): string;
    procedure AddToolNotes(Parent: TWinControl; var N: TNotes; Org: TPoint;
      Bounds: TRect; SideBySplit: integer);
    //the steps
    procedure OpenModal;
    procedure OpenMainMenu;
    procedure OpenPopup;
    procedure OpenEditor;
    function StepMainMenu(Phase: integer): Boolean;
    function StepPopupSub(Phase: integer): Boolean;
    function StepSaveDialog(Phase: integer): Boolean;
    function StepSaveDialogOfClass(Phase: integer): Boolean;
    function StepDBConnSelect(Phase: integer): Boolean;
    function StepHostPopup(Phase: integer): Boolean;
    function StepStatusBar(Phase: integer): Boolean;
    function StepTableEditor(Phase: integer): Boolean;
    function StepRelationEditor(Phase: integer): Boolean;
    function StepNewTableEditor(Phase: integer): Boolean;
    //the pictures
    procedure MakeGUI;
    procedure MakeMenus;
    procedure MakePalettes;
    procedure MakeToolPalettes;
    procedure MakeStatusBar;
    procedure MakeModelPictures;
    procedure MakeDialog(F: TForm; const RelName: string);
    procedure MakeDBPictures;
    procedure MakeEditorPictures;
    procedure MakeTutorial;
    procedure MakeQueryPictures;
  public
    procedure Run(AMainForm: TForm; const ADir: string);
  end;

var
  Maker: TDocMaker;

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

//----------------------------------------------------------------------------------------------------------------------
// Pictures of windows

//The window without the invisible frame Windows 10 puts around it
function VisibleRect(h: HWND): TRect;
begin
  if(DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, @Result, SizeOf(Result))<>S_OK)then
    Windows.GetWindowRect(h, Result);
end;

//The window as Windows paints it, at its place in the screen rectangle R
procedure PaintWindowInto(B: TBitmap; h: HWND; const R: TRect);
var WR, VR: TRect;
  ScreenDC, MemDC: HDC;
  hBmp, hOld: HBITMAP;
begin
  Windows.GetWindowRect(h, WR);
  ScreenDC:=Windows.GetDC(0);
  MemDC:=Windows.CreateCompatibleDC(ScreenDC);
  hBmp:=Windows.CreateCompatibleBitmap(ScreenDC, WR.Right-WR.Left, WR.Bottom-WR.Top);
  hOld:=Windows.SelectObject(MemDC, hBmp);
  try
    PrintWindow(h, MemDC, PW_RENDERFULLCONTENT);
    //only the visible part of the window
    VR:=VisibleRect(h);
    Windows.BitBlt(B.Canvas.Handle, VR.Left-R.Left, VR.Top-R.Top, VR.Right-VR.Left,
      VR.Bottom-VR.Top, MemDC, VR.Left-WR.Left, VR.Top-WR.Top, SRCCOPY);
  finally
    Windows.SelectObject(MemDC, hOld);
    Windows.DeleteObject(hBmp);
    Windows.DeleteDC(MemDC);
    Windows.ReleaseDC(0, ScreenDC);
  end;
end;

function NewBitmap(w, h: integer): TBitmap;
begin
  Result:=TBitmap.Create;
  Result.PixelFormat:=pf24bit;
  Result.SetSize(Math.Max(w, 1), Math.Max(h, 1));
  Result.Canvas.Brush.Color:=clWhite;
  Result.Canvas.FillRect(Classes.Rect(0, 0, Result.Width, Result.Height));
end;

//The screen rectangle R with the windows painted in this order
function CaptureRect(const R: TRect; const Wins: array of HWND): TBitmap;
var i: integer;
begin
  Result:=NewBitmap(R.Right-R.Left, R.Bottom-R.Top);
  for i:=0 to High(Wins) do
    if(Wins[i]<>0)then
      PaintWindowInto(Result, Wins[i], R);
end;

//One window; Org gets its screen position
function CaptureWindow(h: HWND; out Org: TPoint): TBitmap;
var R: TRect;
begin
  R:=VisibleRect(h);
  Org:=R.TopLeft;
  Result:=CaptureRect(R, [h]);
end;

function UnionRects(const A, B: TRect): TRect;
begin
  Result.Left:=Math.Min(A.Left, B.Left);
  Result.Top:=Math.Min(A.Top, B.Top);
  Result.Right:=Math.Max(A.Right, B.Right);
  Result.Bottom:=Math.Max(A.Bottom, B.Bottom);
end;

function ScreenRectOf(C: TControl): TRect;
var P: TPoint;
begin
  //the whole control, also of a group box with its caption
  if(C is TWinControl)and(TWinControl(C).HandleAllocated)then
  begin
    Windows.GetWindowRect(TWinControl(C).Handle, Result);
    Exit;
  end;
  if(C.Parent<>nil)then
    P:=C.Parent.ClientToScreen(Classes.Point(C.Left, C.Top))
  else
    P:=C.ClientToScreen(Classes.Point(0, 0));
  Result:=Classes.Rect(P.X, P.Y, P.X+C.Width, P.Y+C.Height);
end;

function RelRect(const R: TRect; const Org: TPoint): TRect;
begin
  Result:=R;
  OffsetRect(Result, -Org.X, -Org.Y);
end;

function CenterOf(const R: TRect): TPoint;
begin
  Result:=Classes.Point((R.Left+R.Right) div 2, (R.Top+R.Bottom) div 2);
end;

//A part of the picture, with a thin frame when Frame is set
function Crop(Src: TBitmap; R: TRect; Frame: Boolean = True): TBitmap;
begin
  R.Left:=Math.Max(R.Left, 0);
  R.Top:=Math.Max(R.Top, 0);
  R.Right:=Math.Min(R.Right, Src.Width);
  R.Bottom:=Math.Min(R.Bottom, Src.Height);
  Result:=NewBitmap(R.Right-R.Left, R.Bottom-R.Top);
  Result.Canvas.CopyRect(Classes.Rect(0, 0, Result.Width, Result.Height), Src.Canvas, R);
  if(Frame)then
  begin
    Result.Canvas.Brush.Style:=bsClear;
    Result.Canvas.Pen.Color:=$00A0A0A0;
    Result.Canvas.Rectangle(0, 0, Result.Width, Result.Height);
    Result.Canvas.Brush.Style:=bsSolid;
  end;
end;

function ScaleBmp(Src: TBitmap; w, h: integer): TBitmap;
begin
  Result:=NewBitmap(w, h);
  Windows.SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
  Windows.SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
  Windows.StretchBlt(Result.Canvas.Handle, 0, 0, w, h,
    Src.Canvas.Handle, 0, 0, Src.Width, Src.Height, SRCCOPY);
end;

//A mouse cursor with its hot spot at X, Y
procedure DrawCursor(B: TBitmap; X, Y: integer; Cur: TCursor = crDefault);
var Info: TIconInfo;
  h: HCURSOR;
begin
  if(Cur=crDefault)then
    h:=Windows.LoadCursor(0, IDC_ARROW)
  else
    h:=Screen.Cursors[Cur];
  if(Windows.GetIconInfo(h, @Info))then
  begin
    X:=X-integer(Info.xHotspot);
    Y:=Y-integer(Info.yHotspot);
    if(Info.hbmMask<>0)then
      Windows.DeleteObject(Info.hbmMask);
    if(Info.hbmColor<>0)then
      Windows.DeleteObject(Info.hbmColor);
  end;
  Windows.DrawIconEx(B.Canvas.Handle, X, Y, h, 0, 0, 0, 0, DI_NORMAL);
end;

procedure DrawArrow(C: TCanvas; x1, y1, x2, y2: integer);
var a: double;
  p: array[0..2] of TPoint;
const L = 9;
begin
  C.Pen.Color:=clBlack;
  C.Pen.Width:=1;
  C.Line(x1, y1, x2, y2);
  a:=ArcTan2(y2-y1, x2-x1);
  p[0]:=Classes.Point(x2, y2);
  p[1]:=Classes.Point(x2-Round(L*Cos(a-0.4)), y2-Round(L*Sin(a-0.4)));
  p[2]:=Classes.Point(x2-Round(L*Cos(a+0.4)), y2-Round(L*Sin(a+0.4)));
  C.Brush.Color:=clBlack;
  C.Polygon(p);
end;

procedure AddNote(var N: TNotes; const Text: string; X, Y: integer; Side: TNoteSide);
begin
  SetLength(N, Length(N)+1);
  N[High(N)].Text:=Text;
  N[High(N)].X:=X;
  N[High(N)].Y:=Y;
  N[High(N)].Side:=Side;
end;

procedure SetNoteFont(C: TCanvas);
begin
  C.Font.Name:='Segoe UI';
  C.Font.Size:=9;
  C.Font.Color:=clBlack;
  C.Font.Style:=[];
end;

//The picture with white margins that hold the notes, an arrow from every
//note to its point
function Annotate(Src: TBitmap; const N: TNotes): TBitmap;
const Gap = 40;
  Pad = 6;
var i, j, th, ML, MR, MT, MB, w, h: integer;
  Pos: array of TPoint;
  Order: array of integer;
  side: TNoteSide;
  Measure: TBitmap;
  y, x, last: integer;

  procedure SortBy(s: TNoteSide; ByX: Boolean);
  var a, b, t: integer;
  begin
    SetLength(Order, 0);
    for a:=0 to High(N) do
      if(N[a].Side=s)then
      begin
        SetLength(Order, Length(Order)+1);
        Order[High(Order)]:=a;
      end;
    for a:=0 to High(Order) do
      for b:=a+1 to High(Order) do
        if((ByX)and(N[Order[b]].X<N[Order[a]].X))or
          ((Not(ByX))and(N[Order[b]].Y<N[Order[a]].Y))then
        begin
          t:=Order[a];
          Order[a]:=Order[b];
          Order[b]:=t;
        end;
  end;

begin
  Measure:=NewBitmap(4, 4);
  try
    SetNoteFont(Measure.Canvas);
    th:=Measure.Canvas.TextHeight('Ag');
    ML:=0;
    MR:=0;
    MT:=0;
    MB:=0;
    for i:=0 to High(N) do
    begin
      w:=Measure.Canvas.TextWidth(N[i].Text);
      case N[i].Side of
        nsLeft: ML:=Math.Max(ML, w+Gap+Pad);
        nsRight: MR:=Math.Max(MR, w+Gap+Pad);
        nsTop: MT:=th+Gap;
        nsBottom: MB:=th+Gap;
      end;
    end;

    //Where the texts go (top left corner), relative to the picture
    SetLength(Pos, Length(N));
    h:=Src.Height;
    for side:=nsLeft to nsRight do
    begin
      SortBy(side, False);
      last:=-MaxInt;
      for j:=0 to High(Order) do
      begin
        y:=Math.Max(N[Order[j]].Y-th div 2, last+th+3);
        last:=y;
        if(side=nsLeft)then
          Pos[Order[j]]:=Classes.Point(-ML+Pad, y)
        else
          Pos[Order[j]]:=Classes.Point(Src.Width+Gap, y);
        h:=Math.Max(h, y+th+Pad);
      end;
    end;
    for side:=nsTop to nsBottom do
    begin
      SortBy(side, True);
      last:=-ML;
      for j:=0 to High(Order) do
      begin
        w:=Measure.Canvas.TextWidth(N[Order[j]].Text);
        x:=Math.Max(N[Order[j]].X-w div 2, last+12);
        x:=Math.Max(x, -ML+Pad);
        last:=x+w;
        if(side=nsTop)then
          Pos[Order[j]]:=Classes.Point(x, -MT+Pad div 2)
        else
          Pos[Order[j]]:=Classes.Point(x, Src.Height+Gap-Pad);
        MR:=Math.Max(MR, last+Pad-Src.Width);
      end;
    end;

    Result:=NewBitmap(ML+Src.Width+MR, MT+h+MB);
    Result.Canvas.Draw(ML, MT, Src);
    SetNoteFont(Result.Canvas);
    Result.Canvas.Brush.Style:=bsClear;
    for i:=0 to High(N) do
    begin
      x:=ML+Pos[i].X;
      y:=MT+Pos[i].Y;
      w:=Result.Canvas.TextWidth(N[i].Text);
      Result.Canvas.Brush.Style:=bsClear;
      Result.Canvas.TextOut(x, y, N[i].Text);
      case N[i].Side of
        nsLeft: DrawArrow(Result.Canvas, x+w+4, y+th div 2, ML+N[i].X, MT+N[i].Y);
        nsRight: DrawArrow(Result.Canvas, x-4, y+th div 2, ML+N[i].X, MT+N[i].Y);
        nsTop: DrawArrow(Result.Canvas, x+w div 2, y+th+2, ML+N[i].X, MT+N[i].Y);
        nsBottom: DrawArrow(Result.Canvas, x+w div 2, y-2, ML+N[i].X, MT+N[i].Y);
      end;
    end;
  finally
    Measure.Free;
  end;
end;

//Two pictures next to each other, aligned at the top
function SideBySide(A, B: TBitmap; Gap: integer = 24): TBitmap;
begin
  Result:=NewBitmap(A.Width+Gap+B.Width, Math.Max(A.Height, B.Height));
  Result.Canvas.Draw(0, 0, A);
  Result.Canvas.Draw(A.Width+Gap, 0, B);
end;

//The open menus of this program (#32768), the lowest first
function OpenMenuWindows: TList;
var h: HWND;
  pid: DWORD;
  cls: array[0..63] of char;
begin
  Result:=TList.Create;
  h:=Windows.GetTopWindow(0);
  while(h<>0)do
  begin
    Windows.GetWindowThreadProcessId(h, @pid);
    if(pid=Windows.GetCurrentProcessId)and(Windows.IsWindowVisible(h))then
    begin
      Windows.GetClassName(h, cls, SizeOf(cls));
      if(StrComp(cls, '#32768')=0)then
        Result.Insert(0, Pointer(h));
    end;
    h:=Windows.GetWindow(h, GW_HWNDNEXT);
  end;
end;

procedure PostKey(Key: Word; Count: integer = 1);
var i: integer;
begin
  for i:=1 to Count do
  begin
    Windows.PostMessage(Application.MainForm.Handle, WM_KEYDOWN, Key, 0);
    Windows.PostMessage(Application.MainForm.Handle, WM_KEYUP, Key, LPARAM($C0000000));
  end;
end;

//Close what is left open after a step that failed
procedure EmergencyClose;
var i: integer;
begin
  Windows.EndMenu;
  for i:=Screen.CustomFormCount-1 downto 0 do
    if(fsModal in Screen.CustomForms[i].FormState)then
      Screen.CustomForms[i].ModalResult:=mrCancel;
end;

procedure TStepRunner.Tick(Sender: TObject);
begin
  Timer.Enabled:=False;
  if(Done)then
    Exit;
  try
    Done:=Step(Phase);
  except
    on x: Exception do
    begin
      Maker.Log('STEP EXCEPTION '+x.ClassName+': '+x.Message);
      EmergencyClose;
      Done:=True;
    end;
  end;
  inc(Phase);
  if(Not(Done))then
    Timer.Enabled:=True;
end;

//Open (a menu, a modal dialog) and let Step work while it is open
procedure RunSteps(Open: TDocAction; Step: TDocStep; Interval: integer = 400);
var R: TStepRunner;
  t: QWord;
begin
  R:=TStepRunner.Create;
  R.Step:=Step;
  R.Timer:=TTimer.Create(nil);
  R.Timer.Interval:=Interval;
  R.Timer.OnTimer:=R.Tick;
  R.Timer.Enabled:=True;
  try
    try
      Open;
    except
      on x: Exception do
        Maker.Log('OPEN EXCEPTION '+x.ClassName+': '+x.Message);
    end;
    t:=GetTickCount64;
    while(Not(R.Done))and(GetTickCount64-t<30000)do
      Pump(30);
    if(Not(R.Done))then
    begin
      Maker.Log('TIMEOUT');
      R.Done:=True;
      EmergencyClose;
      Pump(300);
    end;
  finally
    R.Timer.Free;
    R.Free;
  end;
end;

//----------------------------------------------------------------------------------------------------------------------
// TDocMaker

procedure TDocMaker.Log(const s: string);
begin
  Report.Add(s);
end;

procedure TDocMaker.SavePNG(B: TBitmap; const RelName: string);
var png: TPortableNetworkGraphic;
  fname: string;
begin
  fname:=OutDir+StringReplace(RelName, '/', PathDelim, [rfReplaceAll])+'.png';
  ForceDirectories(ExtractFilePath(fname));
  png:=TPortableNetworkGraphic.Create;
  try
    png.Assign(B);
    png.SaveToFile(fname);
  finally
    png.Free;
  end;
  Log(RelName+'.png'#9+IntToStr(B.Width)+#9+IntToStr(B.Height));
end;

function TDocMaker.FindObj(ObjType: TEERObject; const AName: string; M: TEERModel = nil): TEERObj;
var theList: TList;
  i: integer;
begin
  Result:=nil;
  if(M=nil)then
    M:=Model;
  theList:=TList.Create;
  try
    M.GetEERObjectList([ObjType], theList);
    for i:=0 to theList.Count-1 do
      if(AName='')or(CompareText(TEERObj(theList[i]).ObjName, AName)=0)then
      begin
        Result:=TEERObj(theList[i]);
        Exit;
      end;
  finally
    theList.Free;
  end;
end;

function TDocMaker.FindTable(const AName: string; M: TEERModel = nil): TEERTable;
begin
  Result:=TEERTable(FindObj(EERTable, AName, M));
end;

procedure TDocMaker.ScrollHome(F: TEERForm);
begin
  F.ScrollBox.HorzScrollBar.Position:=0;
  F.ScrollBox.VertScrollBar.Position:=0;
  Pump(200);
end;

//The name of a tool button, as the status bar shows it, without the help
function TDocMaker.ToolLabel(C: TControl): string;
const Tools: array[1..17] of string = ('wtPointer', 'wtMove', 'wtTable',
  'wtRel1n', 'wtRel1nSub', 'wtRel11', 'wtRegion', 'wtNote', 'wtHand',
  'wtZoom', '', 'wtRelnm', 'wtDelete', 'wtSize', 'wtRel11Sub', 'wtImage',
  'wtRel11NonId');
  //the buttons and pictures without such a text
  Others: array[0..16, 0..1] of string = (
    ('wtSQLSelectSBtn', 'Add Field to SELECT Clause [Ctrl + S]'),
    ('wtSQLFromSBtn', 'Add Field to FROM Clause [Ctrl + F]'),
    ('wtSQLWhereSBtn', 'Add Field to WHERE Clause [Ctrl + W]'),
    ('wtSQLGroupSBtn', 'Add Field to GROUP Clause [Ctrl + G]'),
    ('wtSQLHavingSBtn', 'Add Field to HAVING Clause [Ctrl + H]'),
    ('wtSQLOrderSBtn', 'Add Field to ORDER Clause [Ctrl + O]'),
    ('wtSQLSetSBtn', 'Add Field to SET Clause [Ctrl + E]'),
    ('wtPointerQrySBtn', ''), ('wtMoveQrySBtn', ''), ('wtHandQrySBtn', ''),
    ('wtZoomQrySBtn', ''),
    ('RevImg', 'Reverse Engineering'),
    ('SyncImg', 'Database Synchronisation'),
    ('CreatesImg', 'SQL Create Script'),
    ('SnapToGridBtn', 'Snap to Grid'),
    ('Designimg', 'Switch Design/Query Mode'),
    ('QueryImg', 'Switch Design/Query Mode'));
var i: integer;
  n: string;
begin
  Result:='';
  n:=C.Name;
  //the tools of the query mode are those of the design mode
  n:=StringReplace(n, 'QrySBtn', 'SBtn', []);
  for i:=Low(Tools) to High(Tools) do
    if(Tools[i]<>'')and(CompareText(n, Tools[i]+'SBtn')=0)and
      (i<=DMEER.WorkToolLabelTexts.Count)then
      Result:=DMEER.WorkToolLabelTexts[i-1];
  if(Result='')then
    Result:=C.Hint;
  if(Result='')then
    for i:=0 to High(Others) do
      if(CompareText(C.Name, Others[i, 0])=0)then
        Result:=Others[i, 1];
  if(Pos(' (', Result)>0)then
    Result:=Copy(Result, 1, Pos(' (', Result)-1);
  Result:=Trim(StringReplace(Result, ' []', '', [rfReplaceAll]));
  Result:=StringReplace(Result, ';', '', [rfReplaceAll]);
end;

//A note for every tool button within Bounds (screen) below Parent; on the
//left side when it is left of SideBySplit (screen x), else on the right
procedure TDocMaker.AddToolNotes(Parent: TWinControl; var N: TNotes; Org: TPoint;
  Bounds: TRect; SideBySplit: integer);
var i, k: integer;
  dup: Boolean;
  C: TControl;
  R: TRect;
  P: TPoint;
  s: string;
begin
  for i:=0 to Parent.ControlCount-1 do
  begin
    C:=Parent.Controls[i];
    if(Not(C.Visible))then
      Continue;
    if(C is TWinControl)then
      AddToolNotes(TWinControl(C), N, Org, Bounds, SideBySplit)
    else if((C is TSpeedButton)or(C is TImage))and(C.Width<80)and(C.Height<60)then
    begin
      R:=ScreenRectOf(C);
      P:=CenterOf(R);
      if(Not(PtInRect(Bounds, P)))then
        Continue;
      s:=ToolLabel(C);
      if(s='')then
        Continue;
      //two pictures at the same place (the mode switch): one note
      dup:=False;
      for k:=0 to High(N) do
        if(N[k].Text=s)then
          dup:=True;
      if(dup)then
        Continue;
      if(P.X<SideBySplit)then
        AddNote(N, s, R.Left-Org.X+2, P.Y-Org.Y, nsLeft)
      else
        AddNote(N, s, R.Right-Org.X-2, P.Y-Org.Y, nsRight);
    end;
  end;
end;

//--- steps ------------------------------------------------------------------------------------------------------------

procedure TDocMaker.OpenModal;
begin
  CurForm.ShowModal;
end;

procedure TDocMaker.OpenMainMenu;
begin
  //Alt: the menu bar with its first item
  Windows.PostMessage(MainFrm.Handle, WM_SYSCOMMAND, SC_KEYMENU, 0);
end;

procedure TDocMaker.OpenPopup;
begin
  CurPopup.Popup(CurPopupPos.X, CurPopupPos.Y);
end;

procedure TDocMaker.OpenEditor;
begin
  CurObj.ShowEditor(nil);
end;

//The number of keyboard steps from the first item of a menu to Item
function KeySteps(Item: TMenuItem): integer;
var i: integer;
begin
  Result:=0;
  for i:=0 to Item.Parent.Count-1 do
  begin
    if(Item.Parent.Items[i]=Item)then
      Exit;
    if(Item.Parent.Items[i].Visible)and(Item.Parent.Items[i].Caption<>'-')then
      inc(Result);
  end;
end;

//The menus with what lies below them, from the left of the window
function CaptureMenus(Below: HWND; const Around: TRect; MinLeft: integer): TBitmap;
var Menus: TList;
  R, WR: TRect;
  i: integer;
  Wins: array of HWND;
begin
  Menus:=OpenMenuWindows;
  try
    R:=Around;
    for i:=0 to Menus.Count-1 do
    begin
      Windows.GetWindowRect(HWND(Menus[i]), WR);
      R:=UnionRects(R, WR);
    end;
    R.Right:=R.Right+6;
    R.Bottom:=R.Bottom+6;
    R.Left:=Math.Max(R.Left-6, MinLeft);
    SetLength(Wins, Menus.Count+1);
    Wins[0]:=Below;
    for i:=0 to Menus.Count-1 do
      Wins[i+1]:=HWND(Menus[i]);
    Result:=CaptureRect(R, Wins);
    //a shadow right and below the menus
    for i:=0 to Menus.Count-1 do
    begin
      Windows.GetWindowRect(HWND(Menus[i]), WR);
      Result.Canvas.Brush.Color:=$00B0B0B0;
      Result.Canvas.FillRect(Classes.Rect(WR.Right-R.Left, WR.Top-R.Top+4,
        WR.Right-R.Left+3, WR.Bottom-R.Top+3));
      Result.Canvas.FillRect(Classes.Rect(WR.Left-R.Left+4, WR.Bottom-R.Top,
        WR.Right-R.Left+3, WR.Bottom-R.Top+3));
    end;
  finally
    Menus.Free;
  end;
end;

function TDocMaker.StepMainMenu(Phase: integer): Boolean;
var VR, ItemR: TRect;
  B: TBitmap;
begin
  Result:=False;
  case Phase of
    0: begin
      PostKey(VK_RIGHT, CurMenuTop);
      PostKey(VK_DOWN);
    end;
    1: if(CurMenuSub<>nil)then
      begin
        PostKey(VK_DOWN, KeySteps(CurMenuSub));
        PostKey(VK_RIGHT);
      end;
    2: begin
      VR:=VisibleRect(MainFrm.Handle);
      //the title bar and the menu bar down to the client area
      ItemR:=Classes.Rect(VR.Left, VR.Top, VR.Left+20, MainFrm.ClientToScreen(Classes.Point(0, 0)).Y);
      Windows.GetMenuItemRect(MainFrm.Handle, Windows.GetMenu(MainFrm.Handle), CurMenuTop, ItemR);
      ItemR.Top:=VR.Top;
      if(ItemR.Left-VR.Left<300)then
        ItemR.Left:=VR.Left
      else
        ItemR.Left:=ItemR.Left-120;
      B:=CaptureMenus(MainFrm.Handle, ItemR, VR.Left);
      try
        SavePNG(B, 'ui/'+CurMenuName);
      finally
        B.Free;
      end;
      Windows.EndMenu;
      Result:=True;
    end;
  end;
end;

//A popup menu, with the submenu CurMenuSub open; the picture is saved by the
//caller's routine through CurName
function TDocMaker.StepPopupSub(Phase: integer): Boolean;
var B: TBitmap;
  R: TRect;
begin
  Result:=False;
  case Phase of
    0: if(CurMenuSub<>nil)then
      begin
        PostKey(VK_DOWN, KeySteps(CurMenuSub)+1);
        PostKey(VK_RIGHT);
      end;
    1: begin
      R:=ScreenRectOf(TControl(CurObj));
      InflateRect(R, 8, 8);
      B:=CaptureMenus(Windows.GetAncestor(TControl(CurObj).Parent.Handle, GA_ROOT), R, -MaxInt);
      try
        SavePNG(B, CurName);
      finally
        B.Free;
      end;
      Windows.EndMenu;
      Result:=True;
    end;
  end;
end;

//The dialog CurForm as it is, saved as CurName
function TDocMaker.StepSaveDialog(Phase: integer): Boolean;
var B: TBitmap;
  Org: TPoint;
begin
  Result:=False;
  if(Phase<2)then
    Exit;
  B:=CaptureWindow(CurForm.Handle, Org);
  try
    SavePNG(B, CurName);
  finally
    B.Free;
  end;
  CurForm.ModalResult:=mrCancel;
  Result:=True;
end;

//--- the main window ------------------------------------------------------------------------------------------------

procedure TDocMaker.MakeGUI;
var B, S, A: TBitmap;
  Org, P: TPoint;
  f: double;
  N: TNotes;
  R: TRect;

  function Sc(const Q: TPoint): TPoint;
  begin
    Result:=Classes.Point(Round((Q.X-Org.X)*f), Round((Q.Y-Org.Y)*f));
  end;

begin
  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    f:=640/B.Width;
    S:=ScaleBmp(B, 640, Round(B.Height*f));
    try
      SetLength(N, 0);
      P:=MainFrm.ClientToScreen(Classes.Point(0, 0));
      P:=Sc(Classes.Point(P.X+160, P.Y-9));
      AddNote(N, 'Main Menu', P.X, P.Y, nsTop);
      P:=Sc(CenterOf(ScreenRectOf(MainFrm.ToolsPnl)));
      AddNote(N, 'Toolbar', P.X, P.Y, nsLeft);
      P:=Sc(CenterOf(ScreenRectOf(MainFrm.PaletteDockPnl)));
      AddNote(N, 'Palettes', P.X, P.Y, nsRight);
      R:=ScreenRectOf(MainFrm.StatusPnl);
      P:=Sc(Classes.Point(R.Left+(R.Right-R.Left) div 5, (R.Top+R.Bottom) div 2));
      AddNote(N, 'Status Bar', P.X, P.Y, nsBottom);
      R:=ScreenRectOf(TEERForm(MainFrm.FActiveEERForm));
      P:=Sc(Classes.Point((R.Left+R.Right) div 2, R.Bottom-60));
      AddNote(N, 'The Model', P.X, P.Y, nsBottom);
      A:=Annotate(S, N);
      try
        SavePNG(A, 'fundamentals/gui');
      finally
        A.Free;
      end;
    finally
      S.Free;
    end;
  finally
    B.Free;
  end;
end;

procedure TDocMaker.MakeMenus;
const Names: array[0..7] of string = ('mainmenufile', 'mainmenuedit',
  'mainmenudisplay', 'mainmenudatabase', 'mainmenuplugins', 'mainmenuoptions',
  'mainmenuwindows', 'mainmenuhelp');
var i, k: integer;
  Item: TMenuItem;
begin
  for i:=0 to High(Names) do
  begin
    case i of
      0: Item:=MainFrm.FileMI;
      1: Item:=MainFrm.EditMI;
      2: Item:=MainFrm.DisplayMI;
      3: Item:=MainFrm.DatabaseMI;
      4: Item:=MainFrm.PluginsMI;
      5: Item:=MainFrm.OptionsMI;
      6: Item:=MainFrm.WindowsMI;
    else
      Item:=MainFrm.HelpMI;
    end;
    //the position among the visible items of the menu bar
    CurMenuTop:=0;
    for k:=0 to MainFrm.MainMenu.Items.Count-1 do
    begin
      if(MainFrm.MainMenu.Items[k]=Item)then
        Break;
      if(MainFrm.MainMenu.Items[k].Visible)then
        inc(CurMenuTop);
    end;
    CurMenuName:=Names[i];
    CurMenuSub:=nil;
    if(i=0)then
      CurMenuSub:=MainFrm.ExportMI;
    if(i=2)then
      CurMenuSub:=MainFrm.NotationMI;
    RunSteps(OpenMainMenu, StepMainMenu, 500);
    Pump(400);
  end;
end;

procedure TDocMaker.MakePalettes;
var B, C: TBitmap;
  Org: TPoint;
  R: TRect;
  i: integer;
  Node: TTreeNode;
begin
  //the data types: all types, the date and time types opened
  try
    PaletteDataTypesForm.AllDatatypesPBoxClick(nil);
    PaletteDataTypesForm.AllDataTypesTV.FullCollapse;
    for i:=0 to PaletteDataTypesForm.AllDataTypesTV.Items.Count-1 do
    begin
      Node:=PaletteDataTypesForm.AllDataTypesTV.Items[i];
      if(Node.Level=0)and(Pos('Date', Node.Text)>0)then
        Node.Expanded:=True;
    end;
  except
    on x: Exception do
      Log('palettedatatypes: '+x.Message);
  end;

  //the model: one table opened
  try
    PaletteModelFrom.TablesTreeView.FullCollapse;
    for i:=0 to PaletteModelFrom.TablesTreeView.Items.Count-1 do
    begin
      Node:=PaletteModelFrom.TablesTreeView.Items[i];
      if(Node.Level=0)and(Node.Text='product')then
      begin
        Node.Expanded:=True;
        if(Node.Count>0)then
          Node.Items[0].Expanded:=True;
        if(Node.Count>2)then
          Node.Items[2].Expanded:=True;
        PaletteModelFrom.TablesTreeView.Selected:=Node;
      end;
    end;
  except
    on x: Exception do
      Log('palettemodel: '+x.Message);
  end;
  Pump(500);

  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    C:=Crop(B, RelRect(ScreenRectOf(MainFrm.NavPnl), Org));
    SavePNG(C, 'ui/palettenav');
    C.Free;
    C:=Crop(B, RelRect(ScreenRectOf(MainFrm.DatatypesPnl), Org));
    SavePNG(C, 'ui/palettedatatypes');
    C.Free;
    R:=RelRect(ScreenRectOf(MainFrm.ModelPnl), Org);
    R.Bottom:=Math.Min(R.Bottom, R.Top+420);
    C:=Crop(B, R);
    SavePNG(C, 'ui/palettemodel');
    C.Free;
  finally
    B.Free;
  end;

  PaletteDataTypesForm.CommonDatatypesPBoxClick(nil);
  PaletteModelFrom.TablesTreeView.FullCollapse;
  Pump(200);
end;

procedure TDocMaker.MakeToolPalettes;
var B, C, D, Q, A: TBitmap;
  Org: TPoint;
  R: TRect;
  N: TNotes;
  i: integer;

  //the strip of the toolbar down to its last visible button
  //the lowest visible button below P
  function LowestBottom(P: TWinControl): integer;
  var j: integer;
  begin
    Result:=ScreenRectOf(P).Top;
    for j:=0 to P.ControlCount-1 do
      if(P.Controls[j].Visible)then
      begin
        if(P.Controls[j] is TWinControl)then
          Result:=Math.Max(Result, LowestBottom(TWinControl(P.Controls[j])))
        else if((P.Controls[j] is TSpeedButton)or(P.Controls[j] is TImage))and
          (P.Controls[j].Width<80)and(P.Controls[j].Height<60)then
          Result:=Math.Max(Result, ScreenRectOf(P.Controls[j]).Bottom);
      end;
  end;

  //the strip of the toolbar down to its last visible button
  function ToolStrip(P: TWinControl): TRect;
  begin
    Result:=ScreenRectOf(P);
    Result.Bottom:=LowestBottom(P)+6;
  end;

begin
  //the floating palette
  try
    PaletteToolsForm.Show;
    Pump(500);
    B:=CaptureWindow(PaletteToolsForm.Handle, Org);
    try
      SetLength(N, 0);
      R:=VisibleRect(PaletteToolsForm.Handle);
      AddToolNotes(PaletteToolsForm, N, Org, R, (R.Left+R.Right) div 2);
      A:=Annotate(B, N);
      SavePNG(A, 'ui/palettetools');
      A.Free;
    finally
      B.Free;
    end;
    PaletteToolsForm.Hide;
    Pump(300);
  except
    on x: Exception do
      Log('palettetools: '+x.Message);
  end;

  //the docked toolbar in both modes
  D:=nil;
  Q:=nil;
  try
    for i:=0 to 1 do
    begin
      if(i=1)then
        MainFrm.SetWorkMode(wmQuery);
      Pump(600);
      B:=CaptureWindow(MainFrm.Handle, Org);
      try
        R:=ToolStrip(MainFrm.ToolsPnl);
        SetLength(N, 0);
        AddToolNotes(MainFrm.ToolsPnl, N, Classes.Point(R.Left, R.Top), R, -MaxInt);
        C:=Crop(B, RelRect(R, Org));
        try
          if(i=0)then
            D:=Annotate(C, N)
          else
            Q:=Annotate(C, N);
        finally
          C.Free;
        end;
      finally
        B.Free;
      end;
    end;
    MainFrm.SetWorkMode(wmDesign);
    Pump(400);
    A:=SideBySide(D, Q, 40);
    try
      SetNoteFont(A.Canvas);
      SavePNG(A, 'ui/palettetoolsdocked');
    finally
      A.Free;
    end;
  finally
    D.Free;
    Q.Free;
  end;
end;

function TDocMaker.StepStatusBar(Phase: integer): Boolean;
var B, A: TBitmap;
  R, ZR: TRect;
  N: TNotes;
  Org, P: TPoint;
begin
  Result:=False;
  if(Phase<1)then
    Exit;
  ZR:=VisibleRect(CurForm.Handle);
  R:=ScreenRectOf(MainFrm.StatusPnl);
  R.Top:=Math.Min(R.Top, ZR.Top)-4;
  R.Left:=VisibleRect(MainFrm.Handle).Left;
  R.Right:=R.Left+380;
  B:=CaptureRect(R, [MainFrm.Handle, CurForm.Handle]);
  try
    Org:=R.TopLeft;
    SetLength(N, 0);
    if(MainFrm.NotSavedImg.Visible)then
      P:=CenterOf(ScreenRectOf(MainFrm.NotSavedImg))
    else
      P:=CenterOf(ScreenRectOf(MainFrm.SavedImg));
    AddNote(N, 'Model has been changed indicator', P.X-Org.X, P.Y-Org.Y-6, nsRight);
    P:=CenterOf(ScreenRectOf(MainFrm.Save2DiskImg));
    AddNote(N, 'Save to Disk file', P.X-Org.X, P.Y-Org.Y-6, nsRight);
    P:=CenterOf(ScreenRectOf(MainFrm.Save2DBImg));
    AddNote(N, 'Save in Database', P.X-Org.X, P.Y-Org.Y-6, nsRight);
    P:=CenterOf(ScreenRectOf(MainFrm.ZoomLbl));
    AddNote(N, 'Zoom Factor', P.X-Org.X, P.Y-Org.Y, nsLeft);
    A:=Annotate(B, N);
    try
      SavePNG(A, 'ui/statusbar');
    finally
      A.Free;
    end;
  finally
    B.Free;
  end;
  CurForm.ModalResult:=mrCancel;
  Result:=True;
end;

procedure TDocMaker.MakeStatusBar;
begin
  Model.ModelHasChanged;
  Pump(200);
  CurForm:=TZoomSelForm.Create(MainFrm);
  try
    CurForm.Left:=MainFrm.Left+6;
    CurForm.Top:=MainFrm.Top+MainFrm.Height-CurForm.Height+15;
    TZoomSelForm(CurForm).FocusZoom(Model.GetZoomFac);
    RunSteps(OpenModal, StepStatusBar);
  finally
    CurForm.Free;
  end;
  Model.IsChanged:=False;
  MainFrm.DisableSaveImgs;
end;

//The parts of a model: image, region, table, note, relation
procedure TDocMaker.MakeModelPictures;
var B, C, A: TBitmap;
  k, best: integer;
  Notes: TList;
  Org, P: TPoint;
  Img, Reg, Note, Tbl, Rel: TEERObj;
  R, CR: TRect;
  N: TNotes;
begin
  ScrollHome(OrderForm);
  Img:=FindObj(EERImage, '');
  Reg:=FindObj(EERRegion, 'OnlineStore');
  Tbl:=FindObj(EERTable, 'onlinecustomer');
  Rel:=FindObj(EERRelation, 'CreditCardRel');
  //the note nearest to the table
  Note:=nil;
  if(Tbl<>nil)then
  begin
    Notes:=TList.Create;
    try
      Model.GetEERObjectList([EERNote], Notes);
      best:=MaxInt;
      for k:=0 to Notes.Count-1 do
        if(Abs(TEERObj(Notes[k]).Left-Tbl.Left)+Abs(TEERObj(Notes[k]).Top-Tbl.Top)<best)then
        begin
          best:=Abs(TEERObj(Notes[k]).Left-Tbl.Left)+Abs(TEERObj(Notes[k]).Top-Tbl.Top);
          Note:=TEERObj(Notes[k]);
        end;
    finally
      Notes.Free;
    end;
  end;
  if(Img=nil)or(Reg=nil)or(Tbl=nil)or(Rel=nil)then
  begin
    Log('modelwhatis: objects not found');
    Exit;
  end;

  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    CR:=UnionRects(ScreenRectOf(Img), ScreenRectOf(Tbl));
    CR:=UnionRects(CR, ScreenRectOf(TEERRel(Rel).RelMiddle));
    CR:=UnionRects(CR, ScreenRectOf(FindObj(EERTable, 'creditcard')));
    if(Note<>nil)then
      CR:=UnionRects(CR, ScreenRectOf(Note));
    InflateRect(CR, 10, 10);
    CR:=RelRect(CR, Org);
    C:=Crop(B, CR);
    try
      SetLength(N, 0);
      Org:=Classes.Point(Org.X+CR.Left, Org.Y+CR.Top);
      R:=ScreenRectOf(Img);
      AddNote(N, 'Image', R.Left+40-Org.X, R.Top+8-Org.Y, nsTop);
      R:=ScreenRectOf(Reg);
      AddNote(N, 'Region', R.Left+(R.Right-R.Left) div 2-Org.X, R.Top+4-Org.Y, nsTop);
      R:=ScreenRectOf(Tbl);
      AddNote(N, 'Table', R.Left+30-Org.X, R.Bottom-4-Org.Y, nsBottom);
      P:=CenterOf(ScreenRectOf(TEERRel(Rel).RelMiddle));
      AddNote(N, '1:n Relation', P.X-Org.X, P.Y-Org.Y, nsRight);
      if(Note<>nil)then
      begin
        P:=CenterOf(ScreenRectOf(Note));
        if(P.X-Org.X<C.Width)and(P.Y-Org.Y<C.Height)then
          AddNote(N, 'Note', P.X-Org.X, P.Y-Org.Y, nsRight);
      end;
      A:=Annotate(C, N);
      SavePNG(A, 'fundamentals/modelwhatis');
      A.Free;
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;

  //the popup menu of a table with the Align submenu
  try
    Tbl:=FindObj(EERTable, 'product');
    CurObj:=Tbl;
    OrderForm.ShowObject(Tbl);
    Pump(400);
    Tbl.SetSelected(True);
    CurPopup:=Tbl.PopupMenu;
    CurPopup.PopupComponent:=Tbl;
    R:=ScreenRectOf(Tbl);
    CurPopupPos:=Classes.Point(R.Left+R.Right div 2-R.Left div 2, R.Top+(R.Bottom-R.Top) div 2);
    CurMenuSub:=nil;
    for k:=0 to CurPopup.Items.Count-1 do
      if(CurPopup.Items[k].Count>0)and(CurMenuSub=nil)then
        CurMenuSub:=CurPopup.Items[k];
    CurName:='fundamentals/popupmenutable';
    RunSteps(OpenPopup, StepPopupSub, 500);
    Tbl.SetSelected(False);
    Pump(300);
  except
    on x: Exception do
      Log('popupmenutable: '+x.Message);
  end;
end;

procedure TDocMaker.MakeDialog(F: TForm; const RelName: string);
begin
  CurForm:=F;
  CurName:=RelName;
  try
    RunSteps(OpenModal, StepSaveDialog);
  finally
    F.Free;
  end;
  Pump(300);
end;

//--- databases --------------------------------------------------------------------------------------------------------

function NewConn(const AName, ADriver, AHost, ADatabase, AUser, ADesc: string): TDBConn;
begin
  Result:=DMDB.GetNewDBConn(AName, False, ADriver);
  Result.Name:=AName;
  Result.Description:=ADesc;
  Result.Params.Values['HostName']:=AHost;
  Result.Params.Values['Database']:=ADatabase;
  Result.Params.Values['User_Name']:=AUser;
end;

function TDocMaker.StepDBConnSelect(Phase: integer): Boolean;
var F: TDBConnSelectForm;
  i: integer;
  NH, Node, Dots: TTreeNode;
  B: TBitmap;
  Org: TPoint;
  R: TRect;
begin
  Result:=False;
  F:=TDBConnSelectForm(CurForm);
  case Phase of
    0: begin
      //made-up network hosts instead of the user's
      NH:=nil;
      for i:=0 to F.DBConnTV.Items.Count-1 do
        if(F.DBConnTV.Items[i].Text='Network Hosts')then
          NH:=F.DBConnTV.Items[i];
      if(NH<>nil)then
      begin
        while(NH.Count>1)do
          NH.Items[0].Delete;
        Dots:=NH.Items[0];
        for i:=0 to 2 do
        begin
          case i of
            0: Node:=F.DBConnTV.Items.Insert(Dots, 'Production');
            1: Node:=F.DBConnTV.Items.Insert(Dots, 'WebServer');
          else
            Node:=F.DBConnTV.Items.Insert(Dots, 'DBServer');
          end;
          Node.ImageIndex:=4;
          Node.SelectedIndex:=4;
          Node.SubItems.Add('HOST');
          Node.SubItems.Add('192.168.1.'+IntToStr(5+i));
          Node.SubItems.Add('root');
          Node.SubItems.Add('');
          F.DBConnTV.Items.AddChild(Node, '...').ImageIndex:=7;
        end;
        NH.Expanded:=True;
      end;
      F.DBConnTV.Selected:=F.DBConnTV.Items[0];
    end;
    1: begin
      B:=CaptureWindow(F.Handle, Org);
      try
        SavePNG(B, 'db/dbconndlg');
      finally
        B.Free;
      end;

      //the popup menu of a host
      for i:=0 to F.DBConnTV.Items.Count-1 do
        if(F.DBConnTV.Items[i].Text='DBServer')then
        begin
          Node:=F.DBConnTV.Items[i];
          F.DBConnTV.Selected:=Node;
          R:=Node.DisplayRect(True);
          CurPopupPos:=F.DBConnTV.ClientToScreen(Classes.Point(R.Left+20, R.Bottom-3));
          CurPopup:=F.HostsPopupMenu;
          CurPopup.PopupComponent:=F.DBConnTV;
          RunSteps(OpenPopup, StepHostPopup, 500);
          Break;
        end;

      F.ModalResult:=mrCancel;
      Result:=True;
    end;
  end;
end;

function TDocMaker.StepHostPopup(Phase: integer): Boolean;
var B: TBitmap;
  R: TRect;
begin
  Result:=False;
  if(Phase<1)then
    Exit;
  //the left part of the dialog with the menu
  R:=VisibleRect(CurForm.Handle);
  R.Right:=ScreenRectOf(TDBConnSelectForm(CurForm).DBConnTV).Right+40;
  R.Bottom:=ScreenRectOf(TDBConnSelectForm(CurForm).DBConnTV).Top+
    (ScreenRectOf(TDBConnSelectForm(CurForm).DBConnTV).Bottom-ScreenRectOf(TDBConnSelectForm(CurForm).DBConnTV).Top) div 2;
  B:=CaptureMenus(CurForm.Handle, R, R.Left);
  try
    SavePNG(B, 'db/dbconnhostpopup');
  finally
    B.Free;
  end;
  Windows.EndMenu;
  Result:=True;
end;

procedure TDocMaker.MakeDBPictures;
var F: TForm;
  Hosts: TList;
  Shop: TDBConn;
begin
  SampleConns:=TObjectList.Create(True);
  try
    Shop:=NewConn('shop', 'MySQL', '127.0.0.1', 'shop', 'root', 'The online shop');
    SampleConns.Add(Shop);
    SampleConns.Add(NewConn('shop_test', 'MySQL', '192.168.1.5', 'shop_test', 'root', 'Test database'));
    SampleConns.Add(NewConn('order_example', 'SQLite', '', 'C:\Data\order.sqlite', '', 'The order example'));
    SampleConns.Add(NewConn('employee', 'Firebird', 'localhost', 'employee', 'SYSDBA', ''));

    //the connections
    DBConnSelectForm:=TDBConnSelectForm.Create(MainFrm);
    try
      DBConnSelectForm.SetData(SampleConns, Shop);
      CurForm:=DBConnSelectForm;
      RunSteps(OpenModal, StepDBConnSelect, 500);
    finally
      FreeAndNil(DBConnSelectForm);
    end;
    Pump(300);

    //a new host
    F:=TEditorStringForm.Create(MainFrm);
    TEditorStringForm(F).SetParams(DMMain.GetTranslatedMessage('Add new Host', 117),
      DMMain.GetTranslatedMessage('Hostname/IP:', 118), 'DBServer/192.168.1.7');
    MakeDialog(F, 'db/dbconnaddnewhost');

    //the parameters of a connection
    Hosts:=TList.Create;
    DBConnEditorForm:=TDBConnEditorForm.Create(MainFrm);
    try
      DBConnEditorForm.SetData(Shop, Hosts, 'MySQL');
      CurForm:=DBConnEditorForm;
      CurName:='db/dbconnparams';
      RunSteps(OpenModal, StepSaveDialog);
    finally
      FreeAndNil(DBConnEditorForm);
      Hosts.Free;
    end;
    Pump(300);
  finally
    SampleConns.Free;
  end;

  //the SQL scripts
  F:=TEERExportSQLScriptFrom.Create(MainFrm);
  TEERExportSQLScriptFrom(F).SetModel(Model);
  MakeDialog(F, 'db/exportsqlscript');
  F:=TEERExportSQLScriptFrom.Create(MainFrm);
  TEERExportSQLScriptFrom(F).SetModel(Model, 1);
  MakeDialog(F, 'db/exportsqlscriptdrops');

  //reverse engineering and synchronisation with the SQLite database
  try
    F:=TEERReverseEngineeringForm.Create(MainFrm);
    //connected first, so the dialog shows the tables of the database
    DMDB.ConnectToDB(Conn);
    TEERReverseEngineeringForm(F).SetData(Model);
    MakeDialog(F, 'db/reverseeng');
  except
    on x: Exception do
      Log('reverseeng: '+x.Message);
  end;
  try
    F:=TEERSynchronisationForm.Create(MainFrm);
    DMDB.ConnectToDB(Conn);
    TEERSynchronisationForm(F).SetData(Model);
    MakeDialog(F, 'db/dbsync');
  except
    on x: Exception do
      Log('dbsync: '+x.Message);
  end;
end;

//--- editors ----------------------------------------------------------------------------------------------------------

function TDocMaker.StepTableEditor(Phase: integer): Boolean;
var F: TEditorTableForm;
  B, C, A, P, S, E: TBitmap;
  Org, Q, Q2, PalOrg: TPoint;
  R, R2: TRect;
  N: TNotes;
  i: integer;

  function Cell(ACol, ARow: integer): TRect;
  begin
    Result:=F.ColumnGrid.CellRect(ACol, ARow);
    OffsetRect(Result, F.ColumnGrid.ClientToScreen(Classes.Point(0, 0)).X-Org.X,
      F.ColumnGrid.ClientToScreen(Classes.Point(0, 0)).Y-Org.Y);
  end;

  function Rel(Ctrl: TControl): TRect;
  begin
    Result:=RelRect(ScreenRectOf(Ctrl), Org);
  end;

  procedure ShowPage(Index: integer);
  begin
    F.PageControlTreeView.Selected:=F.PageControlTreeView.Items[Index];
    F.PageControlTreeViewChange(nil, F.PageControlTreeView.Selected);
    Pump(300);
  end;

  procedure SaveCrop(const R: TRect; const Name: string);
  var X: TBitmap;
  begin
    X:=Crop(B, R);
    try
      SavePNG(X, Name);
    finally
      X.Free;
    end;
  end;

  procedure SaveCropCursor(const R: TRect; const At: TPoint; const Name: string);
  var X: TBitmap;
  begin
    X:=Crop(B, R);
    try
      DrawCursor(X, At.X-R.Left, At.Y-R.Top);
      SavePNG(X, Name);
    finally
      X.Free;
    end;
  end;

begin
  Result:=False;
  if(Phase<1)then
    Exit;
  F:=TEditorTableForm(Screen.FindForm('EditorTableForm'));
  if(F=nil)then
    for i:=0 to Screen.FormCount-1 do
      if(Screen.Forms[i] is TEditorTableForm)then
        F:=TEditorTableForm(Screen.Forms[i]);
  if(F=nil)then
  begin
    Log('table editor not found');
    Exit(True);
  end;

  ShowPage(0);
  B:=CaptureWindow(F.Handle, Org);
  try
    SavePNG(B, 'editors/editortable');

    //the columns
    R:=Cell(0, 0);
    R:=Classes.Rect(R.Left, R.Top, Cell(6, 0).Right, Cell(0, 6).Bottom);
    SaveCrop(R, 'editors/editortablecolumns');

    //the start of the grid for the tutorial
    R:=Cell(0, 0);
    R:=Classes.Rect(R.Left-2, R.Top-18, Cell(6, 0).Left+40, Cell(0, 5).Bottom);
    SaveCropCursor(R, CenterOf(Cell(5, 1)), 'designmode/set_autoinc');
    Q:=CenterOf(Cell(3, 3));
    SaveCropCursor(R, Classes.Point(Q.X+10, Q.Y), 'designmode/setting_datatype_params');
    R:=Classes.Rect(Cell(5, 0).Left, Cell(5, 0).Top, Cell(7, 0).Right, Cell(0, 6).Bottom);
    SaveCropCursor(R, CenterOf(Cell(7, 4)), 'designmode/flags_defaultval');
    R:=Classes.Rect(Cell(7, 0).Left, Cell(7, 0).Top, Math.Min(Cell(8, 0).Left+120, Rel(F.ColumnGrid).Right),
      Cell(0, 6).Bottom);
    SaveCropCursor(R, Classes.Point(Cell(8, 3).Left+30, CenterOf(Cell(8, 3)).Y), 'designmode/column_comments');

    //the list of the indices
    R:=UnionRects(Rel(F.PageControlTreeView), Rel(F.IndexListBox));
    R:=UnionRects(R, Rel(F.NewIndexBtn));
    R.Right:=R.Right+8;
    InflateRect(R, 4, 4);
    C:=Crop(B, R);
    try
      SetLength(N, 0);
      Q:=CenterOf(Rel(F.PageControlTreeView));
      AddNote(N, 'Page Selection', Q.X-R.Left, Rel(F.PageControlTreeView).Top+8-R.Top, nsTop);
      Q:=CenterOf(Rel(F.NewIndexBtn));
      AddNote(N, 'Add New Index', Q.X-R.Left+6, Q.Y-R.Top, nsRight);
      Q:=CenterOf(Rel(F.DelIndexBtn));
      AddNote(N, 'Delete Selected Index', Q.X-R.Left+6, Q.Y-R.Top, nsRight);
      Q:=CenterOf(Rel(F.IndexListBox));
      AddNote(N, 'List of the Table''s Indices', Q.X-R.Left, Rel(F.IndexListBox).Bottom-10-R.Top, nsBottom);
      A:=Annotate(C, N);
      SavePNG(A, 'editors/editortableindexlist');
      A.Free;
    finally
      C.Free;
    end;
    R:=Classes.Rect(Rel(F.PageControlTreeView).Left, Rel(F.OptionsPnl).Top, Rel(F.IndexListBox).Right+60,
      Rel(F.IndexListBox).Top+90);
    SaveCropCursor(R, CenterOf(Rel(F.NewIndexBtn)), 'designmode/create_table_index');
  finally
    B.Free;
  end;

  //an index with its columns
  if(F.IndexListBox.Items.Count>1)then
  begin
    F.IndexListBox.ItemIndex:=1;
    F.IndexListBoxClick(nil);
    Pump(300);
  end;
  B:=CaptureWindow(F.Handle, Org);
  try
    SaveCrop(Rel(F.IndexGroupbox), 'editors/editortableindex');
    //a column dragged onto the columns of the index
    A:=Crop(B, Classes.Rect(0, 0, B.Width, B.Height), False);
    try
      Q:=CenterOf(Cell(1, 6));
      Q2:=CenterOf(Rel(F.IndexColListBox));
      A.Canvas.Pen.Width:=2;
      DrawArrow(A.Canvas, Q.X, Q.Y, Q2.X, Q2.Y);
      DrawCursor(A, Q2.X+2, Q2.Y+2);
      SavePNG(A, 'designmode/add_column_to_index');
    finally
      A.Free;
    end;

    //a data type dragged from the palette onto a column
    S:=CaptureWindow(MainFrm.Handle, PalOrg);
    try
      //the palette as far as its names go, the editor down to its columns
      R2:=RelRect(ScreenRectOf(MainFrm.DatatypesPnl), PalOrg);
      R2.Right:=Math.Min(R2.Right, R2.Left+200);
      P:=Crop(S, R2);
      E:=Crop(B, Classes.Rect(0, 0, Cell(6, 0).Right+8, Rel(F.ColumnGrid).Bottom+8), False);
      try
        A:=SideBySide(E, P, 60);
        try
          Q:=Classes.Point(E.Width+60+40, 0);
          //the VARCHAR item of the common data types
          with PaletteDataTypesForm.CommonDataTypesListView do
            for i:=0 to Items.Count-1 do
              if(Pos('VARCHAR', UpperCase(Items[i].Caption))=1)and(Q.Y=0)then
              begin
                R:=Items[i].DisplayRect(drLabel);
                Q2:=ClientToScreen(Classes.Point(R.Left+12, (R.Top+R.Bottom) div 2));
                Q:=Classes.Point(E.Width+60+Q2.X-PalOrg.X-R2.Left, Q2.Y-PalOrg.Y-R2.Top);
              end;
          if(Q.Y=0)then
            Q.Y:=P.Height div 3;
          Q2:=CenterOf(Cell(3, 3));
          A.Canvas.Pen.Width:=2;
          DrawArrow(A.Canvas, Q.X, Q.Y, Q2.X, Q2.Y);
          DrawCursor(A, Q2.X+2, Q2.Y+2);
          SavePNG(A, 'designmode/assign_datatypes');
        finally
          A.Free;
        end;
      finally
        P.Free;
        E.Free;
      end;
    finally
      S.Free;
    end;
  finally
    B.Free;
  end;

  //the other pages
  for i:=1 to F.PageControlTreeView.Items.Count-1 do
  begin
    ShowPage(i);
    B:=CaptureWindow(F.Handle, Org);
    try
      R:=UnionRects(Rel(F.PageControlTreeView), Rel(F.TablePageControl));
      R:=UnionRects(R, Rel(F.PageControlTitlePnl));
      InflateRect(R, 3, 3);
      case F.TablePageControl.ActivePageIndex of
        1: SaveCrop(R, 'editors/editortableoptions');
        2: SaveCrop(R, 'editors/editortableadvoptions');
        3: SaveCrop(R, 'editors/editortablestdinserts');
        4: SaveCrop(R, 'editors/editortablecomments');
      end;
    finally
      B.Free;
    end;
  end;
  ShowPage(0);

  F.ModalResult:=mrCancel;
  Result:=True;
end;

function TDocMaker.StepRelationEditor(Phase: integer): Boolean;
var F: TForm;
  i: integer;
  B, C: TBitmap;
  Org, Q: TPoint;
  R: TRect;
begin
  Result:=False;
  if(Phase<1)then
    Exit;
  F:=nil;
  for i:=0 to Screen.FormCount-1 do
    if(Screen.Forms[i] is TEditorRelationForm)then
      F:=Screen.Forms[i];
  if(F=nil)then
  begin
    Log('relation editor not found');
    Exit(True);
  end;
  B:=CaptureWindow(F.Handle, Org);
  try
    SavePNG(B, 'editors/editorrelation');
    R:=RelRect(ScreenRectOf(TEditorRelationForm(F).FKGrid), Org);
    R:=Classes.Rect(0, 0, Math.Min(B.Width, 330), R.Top+50);
    C:=Crop(B, R);
    try
      Q:=CenterOf(RelRect(ScreenRectOf(TEditorRelationForm(F).RelationNameEd), Org));
      DrawCursor(C, Q.X+30, Q.Y+4);
      SavePNG(C, 'designmode/rel_name');
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;
  F.ModalResult:=mrCancel;
  Result:=True;
end;

procedure TDocMaker.MakeEditorPictures;
var Obj: TEERObj;
  F: TForm;
begin
  //the table editor and its parts
  CurObj:=FindObj(EERTable, 'product');
  if(CurObj<>nil)then
    RunSteps(OpenEditor, StepTableEditor, 600);
  Pump(400);

  CurObj:=FindObj(EERRelation, 'ProductgroupRel');
  if(CurObj<>nil)then
    RunSteps(OpenEditor, StepRelationEditor, 600);
  Pump(400);

  CurObj:=FindObj(EERRegion, 'OnlineStore');
  CurName:='editors/editorregion';
  CurClass:='TEditorRegionForm';
  CurForm:=nil;
  if(CurObj<>nil)then
    RunSteps(OpenEditor, StepSaveDialogOfClass, 600);
  Pump(400);

  CurObj:=FindObj(EERNote, '');
  CurName:='editors/editornote';
  CurClass:='TEditorNoteForm';
  if(CurObj<>nil)then
    RunSteps(OpenEditor, StepSaveDialogOfClass, 600);
  Pump(400);

  //a new image
  F:=TEditorImageForm.Create(MainFrm);
  Obj:=TEERObj(Model.NewImage(50, 50, 100, 100, True));
  TEditorImageForm(F).SetImage(TEERImage(Obj));
  MakeDialog(F, 'editors/editorimage');
  try
    Obj.DeleteObj;
  except
  end;
end;

//The modal dialog an object has opened, saved as CurName
function TDocMaker.StepSaveDialogOfClass(Phase: integer): Boolean;
var i: integer;
  F: TCustomForm;
  B: TBitmap;
  Org: TPoint;
begin
  Result:=False;
  if(Phase<1)then
    Exit;
  F:=nil;
  for i:=0 to Screen.CustomFormCount-1 do
    if(F=nil)and(fsModal in Screen.CustomForms[i].FormState)then
      F:=Screen.CustomForms[i];
  //an editor that is not modal
  for i:=0 to Screen.CustomFormCount-1 do
    if(F=nil)and(Screen.CustomForms[i].Visible)and(Screen.CustomForms[i].ClassNameIs(CurClass))then
      F:=Screen.CustomForms[i];
  if(F=nil)then
  begin
    Log(CurName+': no dialog');
    Exit(True);
  end;
  B:=CaptureWindow(F.Handle, Org);
  try
    SavePNG(B, CurName);
  finally
    B.Free;
  end;
  if(fsModal in F.FormState)then
    F.ModalResult:=mrCancel
  else
    F.Close;
  Result:=True;
end;

//--- the tutorial -----------------------------------------------------------------------------------------------------

//A new table with its editor, next to it on the model
function TDocMaker.StepNewTableEditor(Phase: integer): Boolean;
var i: integer;
  F: TForm;
  VR, R: TRect;
  B: TBitmap;
begin
  Result:=False;
  F:=nil;
  for i:=0 to Screen.FormCount-1 do
    if(Screen.Forms[i] is TEditorTableForm)then
      F:=Screen.Forms[i];
  if(F=nil)then
  begin
    if(Phase>3)then
    begin
      Log('edit_table: no editor');
      Result:=True;
    end;
    Exit;
  end;
  case Phase of
    0, 1: begin
      R:=ScreenRectOf(TControl(CurObj));
      F.Left:=R.Right+120;
      F.Top:=R.Top-40;
    end;
    2: begin
      VR:=VisibleRect(MainFrm.Handle);
      R:=Classes.Rect(VR.Left, VR.Top, VR.Left+640, VR.Top+430);
      B:=CaptureRect(R, [MainFrm.Handle, F.Handle]);
      try
        SavePNG(B, 'designmode/edit_table');
      finally
        B.Free;
      end;
      F.ModalResult:=mrCancel;
      Result:=True;
    end;
  end;
end;

procedure TDocMaker.MakeTutorial;
var M: TEERModel;
  Prod, Grp: TEERTable;
  Rel: TEERObj;
  i: integer;
  B, C: TBitmap;
  Org, P: TPoint;
  R, TR: TRect;
  Btn: TSpeedButton;
begin
  //the order example with the two tables of the tutorial only
  TutForm:=TEERForm(MainFrm.NewEERModel);
  M:=TutForm.EERModel;
  M.LoadFromFile(ExtractFilePath(Application.ExeName)+'Examples'+PathDelim+'order.xml',
    True, False, True, False);
  Pump(500);
  Prod:=FindTable('product', M);
  Grp:=FindTable('productgroup', M);
  Rel:=FindObj(EERRelation, 'ProductgroupRel', M);
  if(Prod=nil)or(Grp=nil)or(Rel=nil)then
  begin
    Log('tutorial: tables not found');
    Exit;
  end;
  for i:=0 to M.ComponentCount-1 do
    if(M.Components[i] is TEERObj)then
      TEERObj(M.Components[i]).SetSelected(
        (M.Components[i]<>Prod)and(M.Components[i]<>Grp)and(M.Components[i]<>Rel));
  M.DeleteSelectedObjs(False);
  M.DeSelectAllObjs(nil);
  Prod.Obj_X:=20;
  Prod.Obj_Y:=60;
  Prod.RefreshObj;
  Grp.Obj_X:=390;
  Grp.Obj_Y:=20;
  Grp.RefreshObj;
  Prod.RefreshRelations;
  Grp.RefreshRelations;
  M.SetZoomFac(100);
  ScrollHome(TutForm);
  Pump(500);

  //the relation
  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    R:=UnionRects(ScreenRectOf(Prod), ScreenRectOf(Grp));
    if(TEERRel(Rel).RelMiddle<>nil)then
      R:=UnionRects(R, ScreenRectOf(TEERRel(Rel).RelMiddle));
    InflateRect(R, 10, 10);
    C:=Crop(B, RelRect(R, Org));
    SavePNG(C, 'designmode/1n_rel');
    C.Free;
  finally
    B.Free;
  end;

  //without the relation, the relation tool chosen
  Rel.SetSelected(True);
  M.DeleteSelectedObjs(False);
  M.DeSelectAllObjs(nil);
  DMEER.SetWorkTool(wtRel1nSub);
  MainFrm.wtRel1nSubSBtn.Down:=True;
  Pump(500);
  Btn:=MainFrm.wtRel1nSubSBtn;
  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    TR:=ScreenRectOf(Btn);
    R:=UnionRects(ScreenRectOf(Prod), ScreenRectOf(Grp));
    R.Left:=ScreenRectOf(MainFrm.ToolsPnl).Left;
    R.Top:=Math.Min(R.Top-10, TR.Top-120);
    R.Bottom:=Math.Max(R.Bottom+10, TR.Bottom+50);
    R.Right:=R.Right+10;
    C:=Crop(B, RelRect(R, Org));
    try
      P:=CenterOf(TR);
      DrawCursor(C, P.X-R.Left+2, P.Y-R.Top+2);
      SavePNG(C, 'designmode/select_rel_1n_tool');
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;

  //the table tool
  Btn:=MainFrm.wtTableSBtn;
  DMEER.SetWorkTool(wtTable);
  Btn.Down:=True;
  Pump(400);
  B:=CaptureWindow(MainFrm.Handle, Org);
  try
    TR:=ScreenRectOf(Btn);
    R:=ScreenRectOf(MainFrm.ToolsPnl);
    R:=Classes.Rect(R.Left, TR.Top-110, R.Left+90, TR.Bottom+60);
    C:=Crop(B, RelRect(R, Org));
    try
      P:=CenterOf(TR);
      DrawCursor(C, P.X-R.Left+2, P.Y-R.Top+2);
      SavePNG(C, 'designmode/select_table_tool');
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;
  DMEER.SetWorkTool(wtPointer);
  MainFrm.wtPointerSBtn.Down:=True;
  Pump(300);

  //a new table with its editor, in a new model
  M.IsChanged:=False;
  TutForm.Close;
  Pump(600);
  TutForm:=TEERForm(MainFrm.NewEERModel);
  M:=TutForm.EERModel;
  Pump(400);
  CurObj:=TEERObj(M.NewTable(140, 60, False));
  Pump(400);
  CurObj.SetSelected(True);
  Pump(300);
  RunSteps(OpenEditor, StepNewTableEditor, 400);
  Pump(300);

  M.IsChanged:=False;
  TutForm.Close;
  Pump(600);
  MainFrm.ActivateEERForm(OrderForm);
  Pump(400);
end;

//--- the query mode ---------------------------------------------------------------------------------------------------

procedure TDocMaker.MakeQueryPictures;
var Q: TEditorQueryForm;
  Prod, Grp: TEERTable;
  B, C: TBitmap;
  Org, P, OldPos: TPoint;
  R: TRect;
  y: integer;
  DT: TForm;
begin
  Prod:=FindTable('product');
  Grp:=FindTable('productgroup');
  if(Prod=nil)or(Grp=nil)then
    Exit;
  MainFrm.SetWorkMode(wmQuery);
  Pump(600);
  OrderForm.ShowObject(Prod);
  Pump(500);
  Q:=TEditorQueryForm(MainFrm.DockedEditorQueryForm);

  //a join of two tables
  try
    Q.SetSQLMemoText('');
    Q.AddTableToSQLCommand(Grp, SQLctSELECT, SQLjtNONE);
    Q.AddTableToSQLCommand(Prod, SQLctSELECT, SQLjtINNER);
    Pump(400);
    B:=CaptureWindow(MainFrm.Handle, Org);
    try
      R:=ScreenRectOf(Q.SQLMemo);
      R.Right:=Math.Min(R.Right, R.Left+420);
      R.Bottom:=Math.Min(R.Bottom, R.Top+110);
      C:=Crop(B, RelRect(R, Org));
      SavePNG(C, 'querymode/querymodejoin2tablessql');
      C.Free;
    finally
      B.Free;
    end;
  except
    on x: Exception do
      Log('querymodejoin2tablessql: '+x.Message);
  end;

  //the query editor with the rows of a table
  try
    DMDB.ConnectToDB(Conn);
    Q.SetSQLMemoText('SELECT * FROM product');
    Q.ExecSQLBtnClick(nil);
    Pump(800);
    B:=CaptureWindow(MainFrm.Handle, Org);
    try
      C:=Crop(B, RelRect(ScreenRectOf(MainFrm.QueryPnl), Org));
      SavePNG(C, 'editors/editorquery');
      C.Free;
    finally
      B.Free;
    end;
  except
    on x: Exception do
      Log('editorquery: '+x.Message);
  end;

  //the menu shown while a table is dragged
  DT:=nil;
  for y:=0 to Screen.FormCount-1 do
    if(Screen.Forms[y] is TEditorQueryDragTargetForm)then
      DT:=Screen.Forms[y];
  if(DT=nil)then
    Exit;
  OldPos:=Mouse.CursorPos;
  try
    R:=ScreenRectOf(Prod);
    P:=Classes.Point(R.Left+(R.Right-R.Left) div 2, R.Top+30);
    Windows.SetCursorPos(P.X, P.Y+50);
    TEditorQueryDragTargetForm(DT).SetModel(Model, 0);
    DT.Show;
    Pump(600);
    R:=UnionRects(R, VisibleRect(DT.Handle));
    InflateRect(R, 10, 10);
    B:=CaptureRect(R, [MainFrm.Handle, DT.Handle]);
    try
      DrawCursor(B, P.X-R.Left, P.Y+50-R.Top, crDrag);
      SavePNG(B, 'querymode/querymodedragdrop');
    finally
      B.Free;
    end;
  except
    on x: Exception do
      Log('querymodedragdrop: '+x.Message);
  end;
  DT.Hide;
  Windows.SetCursorPos(OldPos.X, OldPos.Y);
  Pump(300);

  //a column chosen with the SELECT tool
  try
    DMEER.SetWorkTool(wtSQLSelect);
    MainFrm.wtSQLSelectSBtn.Down:=True;
    Pump(300);
    P:=Classes.Point(-1, -1);
    for y:=10 to Prod.Height-4 do
    begin
      TEERTableAccess(Prod).DoMouseMove(Prod, [], Prod.Width div 2, y);
      if(Model.GetMouseOverSubObj<>nil)and(TObject(Model.GetMouseOverSubObj) is TEERColumn)and
        (TEERColumn(Model.GetMouseOverSubObj).ColName='name')then
      begin
        P:=Classes.Point(Prod.Width div 2, y+4);
        TEERTableAccess(Prod).DoMouseMove(Prod, [], P.X, P.Y);
        Break;
      end;
    end;
    Pump(400);
    B:=CaptureWindow(MainFrm.Handle, Org);
    try
      R:=ScreenRectOf(Prod);
      InflateRect(R, 12, 12);
      R.Bottom:=Math.Min(R.Bottom, R.Top+200);
      C:=Crop(B, RelRect(R, Org));
      try
        if(P.X>=0)then
        begin
          P:=Prod.ClientToScreen(P);
          DrawCursor(C, P.X-R.Left, P.Y-R.Top, crSQLSelectCursor);
        end;
        SavePNG(C, 'querymode/querymodeselectfield');
      finally
        C.Free;
      end;
    finally
      B.Free;
    end;
  except
    on x: Exception do
      Log('querymodeselectfield: '+x.Message);
  end;
  DMEER.SetWorkTool(wtPointer);
  MainFrm.SetWorkMode(wmDesign);
  Pump(500);
end;

//--- the run ----------------------------------------------------------------------------------------------------------

procedure TDocMaker.Run(AMainForm: TForm; const ADir: string);
var i: integer;
  DBFile, TestFile: string;
  F: TForm;

  procedure Part(const AName: string; Proc: TDocAction);
  begin
    try
      Proc;
    except
      on x: Exception do
        Log(AName+#9'EXCEPTION '+x.ClassName+': '+x.Message);
    end;
    EmergencyClose;
    Pump(300);
  end;

begin
  OutDir:=ADir;
  ForceDirectories(OutDir);
  MainFrm:=TMainForm(AMainForm);
  Report:=TStringList.Create;
  try
    //Close the tips window of the start
    for i:=Screen.FormCount-1 downto 0 do
      if(Screen.Forms[i]<>AMainForm)and(Screen.Forms[i].Visible)and
        (Screen.Forms[i].ClassNameIs('TTipsForm'))then
        Screen.Forms[i].Close;

    //A window of a size that reads well in the pages
    AMainForm.WindowState:=wsNormal;
    AMainForm.SetBounds(0, 0, 1024, 720);
    Pump(500);

    //Only the models of the pictures
    for i:=Screen.FormCount-1 downto 0 do
      if(Screen.Forms[i] is TEERForm)then
      begin
        TEERForm(Screen.Forms[i]).EERModel.IsChanged:=False;
        Screen.Forms[i].Close;
      end;
    Pump(500);

    //The order example
    TestFile:=ExtractFilePath(Application.ExeName)+'Examples'+PathDelim+'order.xml';
    OrderForm:=TEERForm(MainFrm.NewEERModel);
    OrderForm.EERModel.LoadFromFile(TestFile, True, False, True, False);
    Model:=OrderForm.EERModel;
    Model.SetZoomFac(100);
    Pump(800);
    ScrollHome(OrderForm);

    //A SQLite database with the tables of the tutorial, in the temporary
    //directory, named without its path (the dialogs show the name)
    SetCurrentDir(GetTempDir);
    DBFile:='order_example.sqlite';
    if(FileExists(DBFile))then
      SysUtils.DeleteFile(DBFile);
    Conn:=TDBConn.Create;
    Conn.Name:='order_example';
    Conn.DriverName:='SQLite';
    Conn.Params.Values['Database']:=DBFile;
    //the dialogs that ask for a connection get this one
    PresetDBConn:=Conn;
    try
      DMDB.ConnectToDB(Conn);
      DMDB.ExecSQL('CREATE TABLE productgroup (idproductgroup INTEGER PRIMARY KEY, groupname VARCHAR(45))');
      DMDB.ExecSQL('CREATE TABLE product (idproduct INTEGER PRIMARY KEY, idproductgroup INTEGER REFERENCES productgroup(idproductgroup), '+
        'name VARCHAR(45), ean VARCHAR(20), price DECIMAL(10,2))');
      DMDB.ExecSQL('INSERT INTO productgroup VALUES (1, ''Books'')');
      DMDB.ExecSQL('INSERT INTO productgroup VALUES (2, ''Music'')');
      DMDB.ExecSQL('INSERT INTO product VALUES (1, 1, ''Database Design'', ''9780000000011'', 39.90)');
      DMDB.ExecSQL('INSERT INTO product VALUES (2, 1, ''SQL for Beginners'', ''9780000000028'', 24.50)');
      DMDB.ExecSQL('INSERT INTO product VALUES (3, 1, ''Modelling with EER Diagrams'', ''9780000000035'', 45.00)');
      DMDB.ExecSQL('INSERT INTO product VALUES (4, 2, ''Classical Piano'', ''4000000000013'', 12.99)');
      DMDB.ExecSQL('INSERT INTO product VALUES (5, 2, ''Jazz Standards'', ''4000000000020'', 14.99)');
      DMDB.DisconnectFromDB;
    except
      on x: Exception do
        Log('Database'#9'EXCEPTION '+x.Message);
    end;

    //the tables, not the picture at the top of the example
    OrderForm.ScrollBox.VertScrollBar.Position:=130;
    Pump(300);
    Part('gui', MakeGUI);
    Part('menus', MakeMenus);
    Part('palettes', MakePalettes);
    Part('tools', MakeToolPalettes);
    Part('statusbar', MakeStatusBar);
    Part('model', MakeModelPictures);

    F:=TPaletteDataTypesReplaceForm.Create(MainFrm);
    TPaletteDataTypesReplaceForm(F).SetModel(Model);
    MakeDialog(F, 'ui/replacedatatype');

    Part('db', MakeDBPictures);
    Part('editors', MakeEditorPictures);
    Part('tutorial', MakeTutorial);
    Part('query', MakeQueryPictures);
  finally
    Report.SaveToFile(OutDir+'docimages.txt');
    Report.Free;
  end;
end;

procedure SaveDocImages(AMainForm: TForm; const ADir: string);
begin
  Maker:=TDocMaker.Create;
  try
    Maker.Run(AMainForm, ADir);
  finally
    FreeAndNil(Maker);
  end;
end;

{$ELSE}

procedure SaveDocImages(AMainForm: TForm; const ADir: string);
begin
  //The pictures are made with the functions of Windows (PrintWindow)
end;

{$ENDIF}

function HasDocImagesParam: Boolean;
var i: integer;
begin
  Result:=False;
  for i:=1 to ParamCount-1 do
    if(CompareText(ParamStr(i), '--docimages')=0)then
      Result:=True;
end;

end.
