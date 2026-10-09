unit MainDM;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of fabFORCE DBDesigner4.
// Copyright (C) 2002, 2003 Michael G. Zinner, www.fabFORCE.net
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
// Unit MainDM.pas
// ---------------
// Version 1.6, 06.05.2003, Mike
// Description
//   Contains all global used functions to CopyDir and CopyDirRecursive
//
// Changes:
//   Version 1.6, 06.05.2003, Mike
//     added GetGlobalSettingsPath
//   Version 1.5, 18.04.2003, Mike
//     fixed bug in EncodeText4XML causing special chars to be saved invalid to XML file
//   Version 1.4, 07.04.2003, Mike
//     Responde to new -disablePersonalSettings parameter (Windows only)
//   Version 1.3, 04.04.2003, Ulli
//     fixed bug in CopyDirRecursive when using PromptBeforeOverwrite flag
//   Version 1.2, 01.04.2003, Ulli
//     added PromptBeforeOverwrite parameter to
//   Version 1.1, 25.03.2003, Mike
//     2 procedures EncodeStreamForXML, DecodeStreamFromXML added to
//     support encoding and decoding for XML from streams
//   Version 1.0, 13.03.2003, Mike
//     initial version, Mike
//
//----------------------------------------------------------------------------------------------------------------------


{$I DBDesigner4.inc}

interface

uses
  {$IFDEF MSWINDOWS}
  Windows, Messages,
  ActiveX, ShellAPI, ShlObj, // for SHGetSpecialFolderLocation() und SHGetPathFromIDList()
  {$ENDIF}
  SysUtils, Classes, DBXpress, DB, SqlExpr, Provider, DBClient,
  DBLocal, Dialogs, ComCtrls, IniFiles, Forms, Qt,
  Buttons, Controls, Menus,
  {$IFDEF USE_IXMLDBMODELType}
  xmldom, XMLIntf, XMLDoc,
  {$ENDIF}
  LCLType, ExtCtrls, Types, Math, StdCtrls, Graphics,
  GlobalSysFunctions;

type
  TFormDPIChangedEvent = procedure(theForm: TCustomForm; OldDPI, NewDPI: integer) of object;

  TDMMain = class(TDataModule)  // SQLDataSet to get Schema Info.

    //Constructor of the DataModule
    procedure DataModuleCreate(Sender: TObject);
    //Destructor of the DataModule
    procedure DataModuleDestroy(Sender: TObject);


    //Initialze a form by setting the default font
    procedure InitForm(theForm: TForm; SetFloatOnTop: Boolean = False; Translate: Boolean = True);
    //Fit the layout of a dialog to the application font, see InitForm
    procedure FitFormLayout(theForm: TForm);
    //A number of pixels of the dialog design in the scale of FitFormLayout
    //With a form: in the DPI the form has now (after its creation)
    function ScaleForFont(Value: integer; theForm: TCustomForm = nil): integer;
    //A form whose controls live in another window (a docked palette) has
    //been scaled with that window: its bitmaps and its own size follow
    procedure FollowDPI(theForm: TCustomForm; NewDPI: integer);

    procedure LoadApplicationFont;
    //The file of the translations, see LoadTranslatedMessages
    function TranslationsFile: string;

    //Get language
    procedure LoadLanguageFromIniFile;
    procedure SaveLanguageToIniFile;

    //Reads a section from a text file that is organized like an ini file
    procedure GetSectionFromTxtFile(filename, section: string; theStringList: TStringList; GetOnlyValues: Boolean = False);
    //Translate Form
    procedure TranslateForm(theForm: TForm);
    //Get Translated strings  #
    procedure GetFormResourceStrings(theForm: TForm; name: string; theStrings: TStringList);
    procedure LoadTranslatedMessages;
    function GetTranslatedMessage(OriginalMsg: string; MsgNr: integer; StrToInsert: string = ''; StrToInsert2: string = ''): string;
    procedure ResetProgramLanguage;
    function GetLanguageCode: string;
    procedure SetLanguageCode(LanguageCode: string);

    //Font combo boxes (Model Options / DBDesigner Options)
    procedure FillFontCBox(CBox: TComboBox; const CurrentFont: string);
    function GetFontCBoxSelection(CBox: TComboBox; const DefaultFont: string): string;

    //Copies a file
    procedure CopyDiskFile(sourcefile, destinationfile: string; PromtBeforeOverwrite: Boolean = True);

    //delete all files from a directory
    procedure DelFilesFromDir(dirname, fname: string);
    // Delete Directory
    procedure DelDir(name: string);
    // Delete Directory
    procedure DelDirRecursive(name: string);
    // Copy Directory with subdirs
    procedure CopyDir(fromdir, todir: string; PromptBeforeOverwrite: Boolean = True);
    // Copy Directory with subdirs
    procedure CopyDirRecursive(fromdir, todir: string; PromptBeforeOverwrite: Boolean = True);



    //Loads a cursor from bmp files
    procedure LoadACursor(crNumber: integer; fname, fname_mask: string; XSpot, YSpot: integer);

    //Not Case Sensitive MiKe = mike
    function ReplaceText(txt, such, ers: string): string;
    //Case Sensitive MiKe <> mike
    function ReplaceString(txt, such, ers: string): string;

    //Subfunktionen
    function ReplaceText2(txt, such, ers: string): string;
    function ReplaceString2(txt, such, ers: string): string;

    //Get an ID which is unique in the application
    function GetNextGlobalID: integer;
    procedure SetGlobalID(i: integer);

    //Show the String Editor modal
    function ShowStringEditor(ATitle, APromt: string; var value: string; SelectionStart: integer = 0; LimitChars: integer = 0): Boolean;

    //Encode normal text for the use in XML files
    function EncodeText4XML(s: string): string;
    //Decode normal text which was encoded with EncodeText4XML
    function DecodeXMLText(s: string): string;


    //Saves Windowposition into INI File
    procedure SaveWinPos(win: TForm; DoSize: Boolean);
    //Recalls Windowposition from INI File
    procedure RestoreWinPos(win: TForm; DoSize: Boolean);
    //True when an (EWMH) window manager runs on the display. Without one
    //(e.g. bare Xvfb) a maximize request is never answered and LCL/GTK2 end
    //up in an endless resize loop, so callers must not use wsMaximized then.
    function HasWindowManager: Boolean;


    //Create prozess
    procedure CreateProz(command, workingdir: string; show, wait4proz: integer);
    //Kill prozess
    procedure KillProz;

    //Start a webbrowser and browse the given webpage
    procedure BrowsePage(s: string);

    //Format text for the use in an SQL Command, text will be enclosed by '
    function FormatText4SQL(s: string): string;

    //Display the online help web pages
    procedure ShowHelp(page, name: string);
    //The start page of the documentation for a page and an anchor in it,
    //written to the settings directory. Returns its file name
    function CreateHelpIndex(page, name: string): string;

    //Get the pointer to a form with the passed name
    function GetFormByName(name: string): TForm;

    //for data import
    function GetSubStringCountInString(txt, such: string): integer;
    function FixLength(s: string; l: integer; alignLeft: boolean = True; FillChar: char = ' '): string;

    function GetColumnCountFromSepString(s, sep, delim: string): integer;
    function GetColumnFromSepString(s: string; colnr: integer; sep, delim: string): string;
    function GetColumnFromFixLengthString(s: string;
      colnr: integer; SList: TStringList): string;

    //analizes an SQL insert command
    function GetValueFromSQLInsert(FieldName, InsertStr: string): string;


    //Reverses a TList
    procedure ReverseList(ObjList: TList);

    {$IFDEF MSWINDOWS}
    {$IFNDEF FPC}
    function GetWindowHandle(wTitle: String): HWnd;
    procedure SetWinPos(Handle, x, y, w, h: integer);
    {$ENDIF}

    //This procedure is used as a workaround of a CLX bug (no-op under the LCL)
    procedure OnOpenSaveDlgShow(Sender: TObject);
    {$ENDIF}

    //Save Bitmap als PNG, JPG or BMP
    //FPC: takes the TBitmap itself (never wrap a handle owned by another
    //TBitmap - under the LCL both objects would delete the same GDI handle)
    procedure SaveBitmap(Bmp: {$IFDEF FPC}TBitmap{$ELSE}QPixmapH{$ENDIF}; FileName: string; FileType: string; JPGQuality: integer = 75);

    function GetFileSize(fname: string): string;
    function GetFileDate(fname: string): TDateTime;

    function LoadValueFromSettingsIniFile(section, name, default: string): string;
    procedure SaveValueInSettingsIniFile(section, name, value: string);

    function RGB(r, g, b: BYTE): integer;
    function HexStringToInt(s: string): integer;


    //-----------------------------------------
    //Workaround Code because of Delphi BUG
    procedure NormalizeStayOnTopForms;
    procedure RestoreStayOnTopForms;

    procedure NormalizeStayOnTopForm(theForm: TForm);
    procedure MakeFormStayOnTop(theForm: TForm);
    function IsFormStayingOnTop(theForm: TForm): Boolean;
    //Workaround Code because of Delphi BUG END
    //-----------------------------------------

{$IFDEF LINUX}
    procedure LinuxCorrectWinPos(Sender: TObject);
{$ENDIF}

    function EncodeStreamForXML(theStream: TStream): string;
    function DecodeStreamFromXML(XMLData: string; theStream: TStream): string;

    function CheckIniFileVersion(IniFileName: string; neededVersion: integer): Boolean;

    function GetValidObjectName(name: string): string;
  private
    { Private declarations }
    GlobalIDSequ: integer;

    WinPosCorrection: Array[0..5] of TPoint;

    //-----------------------------------------
    //Workaround Code because of Delphi BUG
    StayOnTopForms: TList;
    TopMostForm: TForm;
    ApplicationIsActive: Boolean;
    //Workaround Code because of Delphi BUG END
    //-----------------------------------------

    {$IFDEF MSWINDOWS}
    ProcessInfo : TProcessInformation;
    {$ENDIF}

    LanguageCode: String;
    MessageCaptions: TStringList;
  public
    { Public declarations }
    ProgName: string;

    SettingsPath: string;

    NormalizeEditorForms: Boolean;

    LockFormDeactivateTracking: Boolean;

{$IFDEF MSWINDOWS}
    disablePersonalSettings: Boolean;
{$ENDIF}

    HTMLBrowserAppl: string;

    //The dialogs are laid out for a font of 8 points. The main program sets
    //this to have InitForm scale them to the application font
    FitDialogsToFont: Boolean;
    //A plugin sets this too: its main window is a dialog like the others
    MainFormIsDialog: Boolean;
    //A form has come to a display with another DPI; the LCL has scaled its
    //bounds and fonts and its bitmaps are scaled too
    OnFormDPIChanged: TFormDPIChangedEvent;

    ApplicationFontName: string;
    ApplicationFontSize: integer;
    ApplicationFontStyle: TFontStyles;
  end;



  TCmdExecThread = class(TThread)
  private
    { Private declarations }
  protected
    FOnComplete: TNotifyEvent;
    FCommand: String;
    FReturnValue: Integer;
    //FDone is used instead of Terminated because Terminated is
    // false in the OnComplete event handler.
    FDone: Boolean;
    procedure Execute; override;
    procedure FireCompleteEvent;
  public
    constructor Create;
    property OnComplete: TNotifyEvent read FOnComplete write FOnComplete;
    property Command: String read FCommand write FCommand;
    property ReturnValue: Integer read FReturnValue;
    property Done: Boolean read FDone write FDone;
  end;

  function sendCLXEvent(receiver: QObjectH; event: QEventH): Boolean;

const
  DIGIT = ['0'..'9'];
  ALPHA_UC = ['A'..'Z'];
  ALPHA_LC = ['a'..'z'];
  ALPHANUMERIC = DIGIT + ALPHA_UC + ALPHA_LC;
  VALID_OBJECTNAME_CHARS = ALPHANUMERIC + ['_'];

var
  DMMain: TDMMain;
  // True when started with --selftest: every settings/ini writer must skip
  // UpdateFile so an automated run never persists its state (WorkMode,
  // window positions, recent files...) into the user's ~/.DBDesigner4.
  SettingsReadOnly: Boolean = False;

// Flush a settings/ini writer. With SettingsReadOnly the file is redirected to
// a throw-away copy in the temp dir first: TMemIniFile.Destroy flushes dirty
// contents on its own (FPC sets CacheUpdates), so merely skipping UpdateFile
// would not prevent the write.
procedure UpdateIniFile(theIni: TMemIniFile);
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var
  global_winname: string;

type
  PHWnd = ^HWnd;
{$IFEND}

implementation

uses {$IFDEF LINUX}BaseUnix, Unix, {$ENDIF}
  {$IFDEF LCLGTK2}glib2, gdk2, {$ENDIF}
  EditorString, StrUtils, LazUTF8, LConvEncoding, UIScale, LMessages, URIParser;

type
  //Font and ParentFont are protected in TControl
  TLayoutControl = class(TControl);

  //Marks a form whose layout FitFormLayout has done and keeps the size the
  //design has in that scale
  TLayoutMarker = class(TComponent)
  public
    DesignWidth, DesignHeight: integer;
    //The DPI the form is scaled to; the LCL changes PixelsPerInch of the
    //form when it comes to another display
    DPI: integer;
    Form: TCustomForm;
    OldWndProc: TWndMethod;
    InChange: Boolean;
    destructor Destroy; override;
    procedure Watch(theForm: TCustomForm; theDPI: integer);
    procedure WndProc(var TheMessage: TLMessage);
  end;

const
  //Marks a form whose layout FitFormLayout has done
  LayoutDoneName = 'DBDLayoutDone';
  //Height of a line of text in the font the dialogs are designed with
  //(8 points at 96 DPI)
  DesignTextHeight = 13;


var
  WMChecked: Boolean = False;
  WMPresent: Boolean = True;

function TDMMain.HasWindowManager: Boolean;
{$IFDEF LCLGTK2}
const
  XA_WINDOW = 33;
var
  AtomType: TGdkAtom;
  AFormat, ALength: gint;
  Data: Pointer;
{$ENDIF}
begin
  if(Not(WMChecked))then
  begin
    WMChecked:=True;
{$IFDEF LCLGTK2}
    Data:=nil;
    WMPresent:=gdk_property_get(gdk_get_default_root_window,
      gdk_atom_intern('_NET_SUPPORTING_WM_CHECK', False), XA_WINDOW,
      0, 4, 0, @AtomType, @AFormat, @ALength, @Data);
    if(Data<>nil)then
      g_free(Data);
{$ENDIF}
  end;
  Result:=WMPresent;
end;

{$R *.lfm}

procedure TDMMain.DataModuleCreate(Sender: TObject);
var i: integer;
begin
  GlobalIDSequ:=1000;

  //Get the program name
  ProgName:=Copy(ExtractFileName(Application.ExeName), 1,
    Length(ExtractFileName(Application.ExeName))-
    Length(ExtractFileExt(Application.ExeName)));

  //Get the global Settings Path
  SettingsPath:=GetGlobalSettingsPath;

  for i:=0 to 5 do
    WinPosCorrection[i]:=Point(0, 0);


  //-----------------------------------------
  //Workaround Code because of Delphi BUG
  ApplicationIsActive:=True;
  LockFormDeactivateTracking:=False;
  StayOnTopForms:=TList.Create;
  TopMostForm:=nil;
  //Workaround Code because of Delphi BUG END
  //-----------------------------------------


  //Translation
  MessageCaptions:=TStringList.Create;

  HTMLBrowserAppl:='';

  LoadApplicationFont;

  Screen.SystemFont.Name:=ApplicationFontName;
  Screen.SystemFont.Size:=ApplicationFontSize;
  Screen.SystemFont.Style:=ApplicationFontStyle;
end;

//Destructor of the DataModule
procedure TDMMain.DataModuleDestroy(Sender: TObject);
begin
  SaveLanguageToIniFile;

  StayOnTopForms.Free;
  MessageCaptions.Free;
end;


procedure TDMMain.CopyDiskFile(sourcefile, destinationfile: string; PromtBeforeOverwrite: Boolean);
var NewFile: TFileStream;
  OldFile: TFileStream;
begin
  if(FileExists(sourcefile))then
  begin
    if(FileExists(destinationfile))and(PromtBeforeOverwrite)then
    begin
      if(MessageDlg(GetTranslatedMessage('The destination file %s does already exist. '+
        'Do you want to overwrite this file?', 22, destinationfile), mtCustom, [mbYes, mbNo], 0) = 3)then
        DeleteFile(destinationfile)
      else
        Exit;
    end;

    OldFile := TFileStream.Create(sourcefile, fmOpenRead or fmShareDenyWrite);
    try
      NewFile := TFileStream.Create(destinationfile, fmCreate{or fmShareDenyRead});

      try
        NewFile.CopyFrom(OldFile, OldFile.Size);
      finally
        FreeAndNil(NewFile);
      end;
    finally
      FreeAndNil(OldFile);
    end;
  end
  else
    MessageDlg(GetTranslatedMessage('The source file %s does not exist.', 23, sourcefile), mtError, [mbOK], 0);
end;

{$IFDEF MSWINDOWS}
type
  TCursorIconInfo = record
    fIcon: LongBool;
    xHotspot: LongWord;
    yHotspot: LongWord;
    hbmMask: PtrUInt;
    hbmColor: PtrUInt;
  end;

function CursorCreateBitmap(nWidth, nHeight: LongInt; nPlanes, nBitCount: LongWord;
  lpBits: Pointer): PtrUInt; stdcall; external 'gdi32.dll' name 'CreateBitmap';
function CursorDeleteObject(h: PtrUInt): LongBool; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
function CursorCreateIconIndirect(var Info: TCursorIconInfo): PtrUInt; stdcall;
  external 'user32.dll' name 'CreateIconIndirect';

//A monochrome cursor in the scale of the display. CurBits and MaskBits are
//the rows of the two bitmaps (bottom up, RowBytes each): a set bit of the
//mask is a pixel of the cursor, which is black where the bit of the cursor
//bitmap is set and white elsewhere.
//Windows takes one bitmap of twice the height: the AND mask above the XOR
//mask (AND 1 / XOR 0 = the screen, AND 0 / XOR 0 = black, AND 0 / XOR 1 =
//white). A cursor that is built as a .cur file with the bitmap as it is
//has XOR 1 outside the mask too and inverts the screen in a square.
function CreateMonoCursor(const CurBits, MaskBits: TBytes; W, H, RowBytes: integer;
  XSpot, YSpot: integer): PtrUInt;
var NW, NH, DstRow, x, y, sx, sy: integer;
  Bits: TBytes;
  Info: TCursorIconInfo;
  hBmp: PtrUInt;

  function SrcBit(const B: TBytes): Boolean;
  begin
    Result:=(B[(H-1-sy)*RowBytes+sx div 8] and ($80 shr (sx mod 8)))<>0;
  end;

begin
  Result:=0;
  NW:=ScaleCur(W);
  NH:=ScaleCur(H);
  //the rows of a device dependent bitmap are aligned to words
  DstRow:=((NW+15) div 16)*2;

  SetLength(Bits, DstRow*NH*2);
  FillChar(Bits[0], DstRow*NH, $FF);
  FillChar(Bits[DstRow*NH], DstRow*NH, 0);

  for y:=0 to NH-1 do
  begin
    sy:=y*H div NH;
    for x:=0 to NW-1 do
    begin
      sx:=x*W div NW;
      if(SrcBit(MaskBits))then
      begin
        Bits[y*DstRow+x div 8]:=Bits[y*DstRow+x div 8] and not($80 shr (x mod 8));
        if(Not(SrcBit(CurBits)))then
          Bits[(NH+y)*DstRow+x div 8]:=Bits[(NH+y)*DstRow+x div 8] or ($80 shr (x mod 8));
      end;
    end;
  end;

  hBmp:=CursorCreateBitmap(NW, NH*2, 1, 1, @Bits[0]);
  if(hBmp=0)then
    Exit;
  try
    Info.fIcon:=False;
    Info.xHotspot:=ScaleCur(XSpot);
    Info.yHotspot:=ScaleCur(YSpot);
    Info.hbmMask:=hBmp;
    Info.hbmColor:=0;
    Result:=CursorCreateIconIndirect(Info);
  finally
    CursorDeleteObject(hBmp);
  end;
end;
{$ENDIF}

procedure TDMMain.LoadACursor(crNumber: integer; fname, fname_mask: string; XSpot, YSpot: integer);
{$IFDEF FPC}
// Build a .cur in memory from the raw bytes of two 1-bit Windows BMP files.
// The BMP files are already in the exact layout the CUR format expects
// (BITMAPINFOHEADER + 2-color palette + bottom-up packed pixel data), so we
// read them as raw bytes — never decoding through TBitmap, which would
// expand the data to 32bpp and corrupt the cursor.
var
  CurFile, MaskFile: TFileStream;
  CurStream: TMemoryStream;
  CurImg: TCursorImage;
  CurInfo, MaskInfo: packed record
    biSize: LongWord;
    biWidth: LongInt;
    biHeight: LongInt;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: LongWord;
    biSizeImage: LongWord;
    biXPelsPerMeter: LongInt;
    biYPelsPerMeter: LongInt;
    biClrUsed: LongWord;
    biClrImportant: LongWord;
  end;
  RowBytes, XorSize, AndSize, DataOffset, FileHdrSize: LongWord;
  XorData, AndData: TBytes;
  k: LongWord;
  {$IFDEF MSWINDOWS}hCur: PtrUInt;{$ENDIF}
  IconDir: packed record
    idReserved: Word;
    idType: Word;
    idCount: Word;
  end;
  IconEntry: packed record
    bWidth: Byte;
    bHeight: Byte;
    bColorCount: Byte;
    bReserved: Byte;
    wXHotspot: Word;
    wYHotspot: Word;
    dwBytesInRes: LongWord;
    dwImageOffset: LongWord;
  end;
begin
  if not FileExists(fname) then Exit;
  if not FileExists(fname_mask) then Exit;

  FileHdrSize := 14; // BITMAPFILEHEADER size
  CurFile := nil;
  MaskFile := nil;
  CurStream := TMemoryStream.Create;
  try
    try
      CurFile := TFileStream.Create(fname, fmOpenRead or fmShareDenyWrite);
      MaskFile := TFileStream.Create(fname_mask, fmOpenRead or fmShareDenyWrite);

      // Skip the 14-byte file header and read BITMAPINFOHEADER from each.
      CurFile.Position := FileHdrSize;
      CurFile.ReadBuffer(CurInfo, SizeOf(CurInfo));
      MaskFile.Position := FileHdrSize;
      MaskFile.ReadBuffer(MaskInfo, SizeOf(MaskInfo));

      // Only handle 1-bit cursors — that's what DBDesigner ships.
      if (CurInfo.biBitCount <> 1) or (MaskInfo.biBitCount <> 1) then
        Exit;
      if (CurInfo.biWidth <> MaskInfo.biWidth) or
         (CurInfo.biHeight <> MaskInfo.biHeight) then
        Exit;

      RowBytes := ((LongWord(CurInfo.biWidth) + 31) div 32) * 4;
      XorSize := RowBytes * LongWord(CurInfo.biHeight);
      AndSize := XorSize;

      // Pixel data sits at: file header + info header + 2-entry palette.
      DataOffset := FileHdrSize + CurInfo.biSize + 2 * 4;

      SetLength(XorData, XorSize);
      SetLength(AndData, AndSize);
      CurFile.Position := DataOffset;
      CurFile.ReadBuffer(XorData[0], XorSize);
      MaskFile.Position := FileHdrSize + MaskInfo.biSize + 2 * 4;
      MaskFile.ReadBuffer(AndData[0], AndSize);

      {$IFDEF MSWINDOWS}
      hCur:=CreateMonoCursor(XorData, AndData, CurInfo.biWidth, CurInfo.biHeight,
        RowBytes, XSpot, YSpot);
      if(hCur<>0)then
      begin
        Screen.Cursors[crNumber]:=hCur;
        Exit;
      end;
      {$ENDIF}

      // ICONDIR (6 bytes), type=2 means cursor.
      IconDir.idReserved := 0;
      IconDir.idType := NtoLE(Word(2));
      IconDir.idCount := NtoLE(Word(1));
      CurStream.Write(IconDir, 6);

      // ICONDIRENTRY (16 bytes).
      IconEntry.bWidth := Byte(CurInfo.biWidth);
      IconEntry.bHeight := Byte(CurInfo.biHeight);
      IconEntry.bColorCount := 2;
      IconEntry.bReserved := 0;
      IconEntry.wXHotspot := NtoLE(Word(XSpot));
      IconEntry.wYHotspot := NtoLE(Word(YSpot));
      IconEntry.dwBytesInRes := NtoLE(LongWord(40 + 8 + XorSize + AndSize));
      IconEntry.dwImageOffset := NtoLE(LongWord(22));
      CurStream.Write(IconEntry, 16);

      // BITMAPINFOHEADER — height is doubled to cover XOR + AND masks.
      CurStream.WriteDWord(NtoLE(LongWord(40)));
      CurStream.WriteDWord(NtoLE(LongWord(CurInfo.biWidth)));
      CurStream.WriteDWord(NtoLE(LongWord(CurInfo.biHeight * 2)));
      CurStream.WriteWord(NtoLE(Word(1)));   // biPlanes
      CurStream.WriteWord(NtoLE(Word(1)));   // biBitCount
      CurStream.WriteDWord(0);  // biCompression = BI_RGB
      CurStream.WriteDWord(0);  // biSizeImage
      CurStream.WriteDWord(0);  // biXPelsPerMeter
      CurStream.WriteDWord(0);  // biYPelsPerMeter
      CurStream.WriteDWord(NtoLE(LongWord(2)));  // biClrUsed
      CurStream.WriteDWord(0);  // biClrImportant

      // Source BMP palette: index 0 = white, index 1 = black.
      // Cursor body pixels are bit=1 → render black via this palette.
      CurStream.WriteDWord($00FFFFFF);
      CurStream.WriteDWord(0);

      // AND mask: Windows CUR expects bit=0 to mean "opaque" (show XOR pixel).
      // DBDesigner's mask BMPs use the inverse convention (bit=1 marks the
      // cursor body as opaque, Kylix-style), so flip every AND byte.
      for k := 0 to AndSize - 1 do
        AndData[k] := not AndData[k];

      CurStream.Write(XorData[0], XorSize);
      CurStream.Write(AndData[0], AndSize);

      CurStream.Position := 0;
      CurImg := TCursorImage.Create;
      try
        CurImg.LoadFromStream(CurStream);
        CurImg.HotSpot := Point(XSpot, YSpot);
        Screen.Cursors[crNumber] := CurImg.ReleaseHandle;
      finally
        CurImg.Free;
      end;
    except
      // Failed to load custom cursor — non-fatal, app works with default cursors.
    end;
  finally
    CurFile.Free;
    MaskFile.Free;
    CurStream.Free;
  end;
end;
{$ELSE}
var BMap, BMask: QBitMapH;
  FN : WideString;
  format: string;
begin
  if(Not(FileExists(fname)))then
    raise EInOutError.Create(GetTranslatedMessage('File %s does not exist.', 24, fname));
  if(Not(FileExists(fname_mask)))then
    raise EInOutError.Create(GetTranslatedMessage('File %s does not exist.', 24, fname_mask));
  FN:=fname;
  BMap:=QBitmap_create(@FN, PChar(Format));
  FN:=fname_mask;
  BMask:=QBitmap_create(@FN, PChar(Format));
  Screen.Cursors[crNumber]:=QCursor_create(BMap, BMask, XSpot, YSpot);
  QBitmap_destroy(BMap);
  QBitmap_destroy(BMask);
end;
{$ENDIF}

function TDMMain.ReplaceText(txt, such, ers: string): string;
begin
  ReplaceText:=ReplaceText2(ReplaceText2(txt, such, '¢'), '¢', ers);
end;

function TDMMain.ReplaceText2(txt, such, ers: string): string;
begin
  while(Pos(UpperCase(such), UpperCase(txt))>0)do
    txt:=Copy(txt, 1, Pos(UpperCase(such), UpperCase(txt))-1)+ers+
      Copy(txt, Pos(UpperCase(such), UpperCase(txt))+Length(such), Length(txt));

  ReplaceText2:=txt;
end;

function TDMMain.ReplaceString(txt, such, ers: string): string;
begin
  ReplaceString:=ReplaceString2(ReplaceString2(txt, such, ''), '', ers);
end;

function TDMMain.ReplaceString2(txt, such, ers: string): string;
begin
  while(Pos(such, txt)>0)do
    txt:=Copy(txt, 1, Pos(such, txt)-1)+ers+
      Copy(txt, Pos(such, txt)+Length(such), Length(txt));

  ReplaceString2:=txt;
end;

function TDMMain.GetNextGlobalID: integer;
begin
  GetNextGlobalID:=GlobalIDSequ;
  inc(GlobalIDSequ);
end;

procedure TDMMain.SetGlobalID(i: integer);
begin
  if(i>GlobalIDSequ)then
    GlobalIDSequ:=i;
end;

function TDMMain.ShowStringEditor(ATitle, APromt: string; var value: string; SelectionStart: integer = 0; LimitChars: integer = 0): Boolean;
begin
  EditorStringForm:=TEditorStringForm.Create(self);
  try
    EditorStringForm.SetParams(ATitle, APromt, Value, SelectionStart, LimitChars);

    ShowStringEditor:=(EditorStringForm.ShowModal=mrOK);
    value:=EditorStringForm.ValueEd.Text;
  finally
    EditorStringForm.Free;
  end;
end;

function TDMMain.EncodeText4XML(s: string): string;
var i,j,k: integer;
    rs : String;  //our result string
    newTxt :String;
    replace : Boolean;
    ansi : String;
begin
  //A character above 126 is written as the number of its byte. DBDesigner 4
  //wrote the Windows code page (ª for u umlaut), the LCL has UTF-8. Write
  //the code page byte as well, so that the file stays readable for
  //DBDesigner 4; a text with characters outside of the code page keeps its
  //UTF-8 bytes. DecodeXMLText reads both
  if(FindInvalidUTF8Codepoint(PChar(s), Length(s))<0)then
  begin
    ansi:=UTF8ToCP1252(s);
    if(CP1252ToUTF8(ansi)=s)then
      s:=ansi;
  end;

  //theoretically each char could be of ord() > 126
  SetLength(rs, Length(s)* 4);

  //Encode special Chars
  i:=1; //the index of the source-string
  j:=1; //the index of the result-string

  while (i<= Length(s)) do
  begin
    Replace := true;

    if(Ord(s[i])>126)then newTxt:= '\'+IntToStr(Ord(s[i]))
    else if (s[i] = '\') then newTxt := '\\'
    else if (s[i] = #13) then newTxt := ''
    else if (s[i] = #10) then newTxt := '\n'
    else if (s[i] = '"') then newTxt := '\A'
    else if (s[i] = '''') then newTxt := '\a'
    else if (s[i] = '&') then newTxt := '\+'
    else if (s[i] = '<') then newTxt := '\k'
    else if (s[i] = '>') then newTxt := '\g'
    else     { nothing should be replaced }
    begin
      rs[j] := s[i];
      inc(j);
      Replace := false;
    end;
    if (Replace) then    //we have to replace s[i] with newTxt
    begin
       k:= 1;
       while (k <= length(newTxt) ) do
       begin
         rs[j] := newTxt[k];
         inc(j);
         inc(k);
       end;
    end;

    inc(i);
  end;

  EncodeText4XML:=AnsiLeftStr(rs,j-1);
end;


function TDMMain.DecodeXMLText(s: string): string;
var i,j: integer;
    rs : String;
begin
  //our optimizatin can only insert single characters
  s:=ReplaceString(s, '\n', #13#10);
  
  SetLength(rs, Length(s));

  //Decode special Chars
  i:=1;
  j:= 1;
  while(i <= Length(s))do
  begin
    if(s[i]='\') then
    begin
      if (Ord(s[i+1])>=Ord('0'))and(Ord(s[i+1])<=Ord('9'))then
      begin
        rs[j] :=  Chr(StrToInt(Copy(s, i+1, 3)));
        i := i+2;
      end
      else if (s[i+1] = 'A') then rs[j] := '"'
      else if (s[i+1] = 'a') then rs[j] := ''''
      else if (s[i+1] = '+') then rs[j] := '&'
      else if (s[i+1] = 'k') then rs[j] := '<'
      else if (s[i+1] = 'g') then rs[j] := '>'
      else if (s[i+1] = '\') then rs[j] := '\'
      else
      begin
        rs[j]:= s[i];
        dec(i);
      end;
      inc(i);
    end
    else
    begin
      rs[j] := s[i];
    end;

    inc(i);
    inc(j);
  end;

  //DecodeXMLText:=AnsiLeftStr(rs,j-1);
  rs:=Copy(rs, 0, j-1);

  //The bytes are those of the Windows code page (a file of DBDesigner 4, or
  //one written by EncodeText4XML) unless they are valid UTF-8 (a text with
  //characters outside of the code page). The LCL needs UTF-8: a code page
  //byte handed on as it is was shown as "?"
  if(FindInvalidUTF8Codepoint(PChar(rs), Length(rs))>=0)then
    rs:=CP1252ToUTF8(rs);

  DecodeXMLText:=rs;
end;

procedure TDMMain.SaveWinPos(win: TForm; DoSize: Boolean);
var winname: string;
 theIni: TMemIniFile;
 P: TPoint;
begin
  winname:=win.name;

{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  P:=win.ClientToScreen(Point(0, 0));
{$ELSE}
  P.X:=win.Left;
  P.Y:=win.Top;
{$IFEND}

  //Write IniFile
  theIni:=TMemIniFile.Create(SettingsPath+ProgName+'_Settings.ini');
  try
    if(win.WindowState = wsMaximized)then
      theIni.WriteInteger('WindowPositions', winname+'State', 1)
    else
    begin
      theIni.WriteInteger('WindowPositions', winname+'State', 0);

      if(P.X>0)then
        theIni.WriteInteger('WindowPositions', winname+'Left', UnscaleDPI(P.X))
      else
        theIni.WriteInteger('WindowPositions', winname+'Left', 15);

      if(P.Y>0)then
        theIni.WriteInteger('WindowPositions', winname+'Top', UnscaleDPI(P.Y))
      else
        theIni.WriteInteger('WindowPositions', winname+'Top', 15);

      if(DoSize)then
      begin
        theIni.WriteInteger('WindowPositions', winname+'Width', MulDiv(win.Width, DesignDPI, FormDPI(win)));

        theIni.WriteInteger('WindowPositions', winname+'Height', MulDiv(win.Height, DesignDPI, FormDPI(win)));
      end;
    end;

    UpdateIniFile(theIni);
  finally
    theIni.Free;
  end;
end;

procedure TDMMain.RestoreWinPos(win: TForm; DoSize: Boolean);
var theIni: TMemIniFile;
  winname: string;
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  P: TPoint;
{$IFEND}
{$IFDEF LINUX}
  theTimer: TTimer;
{$ENDIF}
{$IFDEF MSWINDOWS}
  WasMaximized: Boolean;
{$ENDIF}
  WinPos, WinSize: TPoint;
begin
  winname:=win.name;

  //Read IniFile
  theIni:=TMemIniFile.Create(SettingsPath+ProgName+'_Settings.ini');
  try
    try
{$IFDEF MSWINDOWS}
      //A form designed maximized (the main form) stayed maximized whatever
      //was saved, and the position and size below were applied to the
      //maximized window. Leave that state first; it is set again below when
      //it was saved (or, without a saved state, designed).
      WasMaximized:=(DoSize)and(win.WindowState=wsMaximized);
      if(WasMaximized)then
        win.WindowState:=wsNormal;
{$ENDIF}

      WinPos.X:=ScaleDPI(theIni.ReadInteger('WindowPositions', winname+'Left', 80));
      WinPos.Y:=ScaleDPI(theIni.ReadInteger('WindowPositions', winname+'Top', 140));
      if(WinPos.X>Screen.Width)then
        WinPos.X:=Screen.Width-50;
      if(WinPos.Y>Screen.Height)then
        WinPos.Y:=Screen.Height-50;

{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
      win.Left:=WinPos.X-WinPosCorrection[Ord(win.BorderStyle)].X;
      win.Top:=WinPos.Y-WinPosCorrection[Ord(win.BorderStyle)].Y;

      P:=win.ClientToScreen(Point(0, 0));
      if(P.X<>WinPos.X)or(P.Y<>WinPos.Y)then
      begin
        WinPosCorrection[Ord(win.BorderStyle)].X:=P.X-WinPos.X;
        WinPosCorrection[Ord(win.BorderStyle)].Y:=P.Y-WinPos.Y;

        win.Left:=WinPos.X-WinPosCorrection[Ord(win.BorderStyle)].X;
        win.Top:=WinPos.Y-WinPosCorrection[Ord(win.BorderStyle)].Y;
      end;

      if(win.Top<0)then
        win.Top:=0;
{$IFEND}
{$IFDEF FPC}
      win.Left:=WinPos.X;
      if(WinPos.Y>0)then
        win.Top:=WinPos.Y
      else
        win.Top:=0;
{$ENDIF}
{$IFDEF LINUX}

      //Workaround from Linux bug
      //A Form has wrong Left/Top Coordinates after it is shown
      //Create a timer to correct them
      theTimer:=TTimer.Create(win);
      theTimer.Enabled:=False;
      theTimer.Interval:=200;
      theTimer.OnTimer:=LinuxCorrectWinPos;
      theTimer.Tag:=WinPos.X*10000+WinPos.Y;
      theTimer.Enabled:=True;
{$ENDIF}

      if(DoSize)then
      begin
        // Default to the form's design size (not 140x140, which is smaller
        // than the docked content) and never restore a size that does not fit
        // the current screen: the geometry was saved on another display and a
        // window larger than the screen makes LCL/GTK2 fight over the size
        // (endless resize loop, see docs/ui-bug-catalog.md #5).
        //the size in the DPI the window has now, the position in that of
        //the primary display as it is stored
        WinSize.X:=MulDiv(theIni.ReadInteger('WindowPositions', winname+'Width',
          MulDiv(win.Width, DesignDPI, FormDPI(win))), FormDPI(win), DesignDPI);
        WinSize.Y:=MulDiv(theIni.ReadInteger('WindowPositions', winname+'Height',
          MulDiv(win.Height, DesignDPI, FormDPI(win))), FormDPI(win), DesignDPI);
        if(WinSize.X>Screen.Width-win.Left)then
          WinSize.X:=Screen.Width-win.Left;
        if(WinSize.Y>Screen.Height-win.Top)then
          WinSize.Y:=Screen.Height-win.Top;
        if(WinSize.X<win.Constraints.MinWidth)then
          WinSize.X:=win.Constraints.MinWidth;
        if(WinSize.Y<win.Constraints.MinHeight)then
          WinSize.Y:=win.Constraints.MinHeight;
        //A size stored with a smaller application font cuts off the dialog
        //that FitFormLayout has scaled since
        if(win.FindComponent(LayoutDoneName) is TLayoutMarker)then
          with TLayoutMarker(win.FindComponent(LayoutDoneName)) do
          begin
            if(WinSize.X<DesignWidth)then
              WinSize.X:=DesignWidth;
            if(WinSize.Y<DesignHeight)then
              WinSize.Y:=DesignHeight;
          end;
        win.Width:=WinSize.X;
        win.Height:=WinSize.Y;
        //Only maximize when a window manager can actually do it
{$IFDEF MSWINDOWS}
        if(theIni.ReadInteger('WindowPositions', winname+'State', Ord(WasMaximized))=1)then
          win.WindowState:=wsMaximized;
{$ELSE}
        if(theIni.ReadInteger('WindowPositions', winname+'State', 0)=1)and
          (HasWindowManager)then
          win.WindowState:=wsMaximized;
{$ENDIF}
      end;
    except
      win.Left:=((Application.MainForm.Left+Application.MainForm.Width)-win.Width) div 2-40;
      win.Top:=((Application.MainForm.Top+Application.MainForm.Height)-win.Height) div 2;

    end;
  finally
    theIni.Free;
  end;
end;

{$IFDEF LINUX}
procedure TDMMain.LinuxCorrectWinPos(Sender: TObject);
begin
  TTimer(Sender).Enabled:=False;
  TForm(TTimer(Sender).Owner).Left:=TTimer(Sender).Tag div 10000;
  TForm(TTimer(Sender).Owner).Top:=TTimer(Sender).Tag-(TTimer(Sender).Tag div 10000*10000);
  TTimer(Sender).Free;
end;
{$ENDIF}

procedure TDMMain.CreateProz(command, workingdir: string; show, wait4proz: integer);
var
  {$IFDEF MSWINDOWS}
  StartupInfo : TStartupInfo;
  wdir: pchar;
  {$ENDIF}

  {$IFDEF LINUX}
  FCmdThread: TCmdExecThread;
  {$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if(workingdir<>'')then
    wdir:=PChar(workingdir)
  else
    wdir:=nil;

  FillChar(StartupInfo, SizeOf(TStartupInfo), 0);
  StartupInfo.cb := Sizeof(TStartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  if(show=1)then
    StartupInfo.wShowWindow := SW_Show
  else
    StartupInfo.wShowWindow := SW_Hide;

  if(Not(CreateProcess(nil, pchar(command), nil, nil,
    true, Normal_PRIORITY_CLASS and CREATE_DEFAULT_ERROR_MODE,
    nil, wdir, StartupInfo, ProcessInfo)))then
    Raise Exception.Create(command+': '+#13#10+
      GetTranslatedMessage('The Program could not be launched. Error code: %s', 25, IntToStr(GetLastError)));


  //If requested, wait for the programm to end
  if(wait4proz=1)then
  begin
    While(WaitForSingleObject(ProcessInfo.hProcess, 0) = WAIT_TIMEOUT)Do
      Application.ProcessMessages;

    ProcessInfo.hProcess:=0;
  end;
  {$ENDIF}

  {$IFDEF LINUX}
  {if FCmdThread <> nil then
  begin
    if not FCmdThread.Done
      then raise Exception.Create('A command is already running')
    else FCmdThread.Free;
  end;}
  FCmdThread := TCmdExecThread.Create;
  //FCmdThread.OnComplete := InternalComplete;
  FCmdThread.Command := command;
  FCmdThread.Start;

  //Wenn erwünscht, warten bis Programm beendet wird.
  if(wait4proz=1)then
  begin
    while(Not(FCmdThread.Done))do
    begin
      Sleep(500);
      //Do drawing and stuff
      Application.ProcessMessages;
    end;
  end;
  {$ENDIF}
end;

procedure TDMMain.KillProz;
begin
  {$IFDEF MSWINDOWS}
  if(ProcessInfo.hProcess<>0)then
    TerminateProcess(ProcessInfo.hProcess, 0);
  {$ENDIF}
end;

//------------------------------------------
// Code for Linux Lics System call Thread

constructor TCmdExecThread.Create;
begin
  Inherited Create(True);
  FDone := False;
end;

procedure TCmdExecThread.Execute;
begin
  {$IFDEF LINUX}
  {$IFDEF FPC}if FCommand <> '' then FReturnValue := fpSystem(FCommand);{$ELSE}if FCommand <> '' then FReturnValue := Libc.System(PChar(FCommand));{$ENDIF}
  {$ENDIF}
  FDone := True;
  Synchronize(FireCompleteEvent);
end;

procedure TCmdExecThread.FireCompleteEvent;
begin
  if Assigned(FOnComplete) then FOnComplete(Self);
end;

//------------------------------------------

procedure TDMMain.BrowsePage(s: string);
begin
  if(HTMLBrowserAppl='')then
  begin
{$IFDEF MSWINDOWS}
    DMMain.CreateProz('explorer '+s, '', 1, 0);
{$ENDIF}
{$IFDEF LINUX}
    DMMain.CreateProz('xdg-open '+s, '', 1, 0);
{$ENDIF}
  end
  else
    DMMain.CreateProz(HTMLBrowserAppl+' '+s, '', 1, 0);
end;

function TDMMain.FormatText4SQL(s: string): string;
begin
  s:=''''+ReplaceText(s, '''', '''''')+'''';

  FormatText4SQL:=s;
end;

function TDMMain.CreateHelpIndex(page, name: string): string;
var Template: TStringList;
  DocDir, Link: string;
  sr: TSearchRec;
begin
  Result:='';
  DocDir:=ExtractFilePath(Application.ExeName)+'Doc'+PathDelim;

  //The pages of earlier calls
  if(FindFirst(SettingsPath+'tmpindex*.html', faAnyFile, sr)=0)then
  begin
    repeat
      SysUtils.DeleteFile(SettingsPath+sr.Name);
    until FindNext(sr)<>0;
    SysUtils.FindClose(sr);
  end;

  Template:=TStringList.Create;
  try
    Template.LoadFromFile(DocDir+'template.html');

    //The frames need URLs. With the plain file names (C:\...\header.html) a
    //browser takes "C:" for a protocol and leaves the frames empty
    Link:=page+'.html';
    if(name<>'')then
      Link:=Link+'#'+name;
    Template.Text:=ReplaceText(Template.Text, '$helpdir$', FilenameToURI(DocDir));
    Template.Text:=ReplaceText(Template.Text, '$helplink$', Link);

    Result:=SettingsPath+'tmpindex'+FormatDateTime('hhnnsszzz', now)+'.html';
    Template.SaveToFile(Result);
  finally
    Template.Free;
  end;
end;

procedure TDMMain.ShowHelp(page, name: string);
var fname: string;
begin
  fname:=CreateHelpIndex(page, name);
  if(fname<>'')then
    BrowsePage(fname);
end;

function TDMMain.GetFormByName(name: string): TForm;
var i: integer;
begin
  GetFormByName:=nil;

  for i:=0 to Screen.FormCount-1 do
    if(Screen.Forms[i].Name=name)then
    begin
      GetFormByName:=Screen.Forms[i];
      break;
    end;
end;

function TDMMain.GetSubStringCountInString(txt, such: string): integer;
var strCount: integer;
  ers: string;
begin
  strCount:=0;
  ers:='';

  while(Pos(such, txt)>0)do
  begin
    txt:=Copy(txt, 1, Pos(such, txt)-1)+ers+
      Copy(txt, Pos(such, txt)+Length(such), Length(txt));

    inc(strCount);
  end;

  GetSubStringCountInString:=strCount;
end;

function TDMMain.FixLength(s: string; l: integer; alignLeft: boolean = True; FillChar: char = ' '): string;
begin
  if(Length(s)>l)then
    s:=copy(s, 1, l);

  if(Length(s)<l)then
    if(alignLeft)then
      s:=s+StringOfChar(FillChar, l-Length(s))
    else
      s:=StringOfChar(FillChar, l-Length(s))+s;

  FixLength:=s;
end;

function TDMMain.GetColumnCountFromSepString(s,
  sep, delim: string): integer;
var theCount: integer;
  s1: string;
begin
  GetColumnCountFromSepString:=0;

  if(Trim(s)='')then
    Exit;

  if(sep='_tab')then
    sep:=Chr(9);

  s1:=s;

  //Ignore double-delims this time
  s1:=ReplaceString(s1, delim+delim+delim, delim+'¦¦');
  s1:=ReplaceString(s1, delim+delim, '¦¦');

  if(Copy(s1, Length(s1), 1)<>sep)then
    s1:=s1+sep;

  theCount:=0;
  while(Pos(sep, s1)>0)do
  begin
    //if sep is found, check if there is a delim before the sep
    if(DMMain.GetSubStringCountInString(Copy(s1, 1, Pos(sep, s1)-1), delim) mod 2=0)then
      inc(theCount);

    s1:=Copy(s1, Pos(sep, s1)+1, Length(s1));
  end;

  GetColumnCountFromSepString:=theCount;
end;

function TDMMain.GetColumnFromSepString(s: string;
  colnr: integer; sep, delim: string): string;
var theCount, p1, p2: integer;
  s1: string;
begin
  s1:=s;

  if(sep='_tab')then
    sep:=Chr(9);

  //Ignore double-delims this time
  s1:=ReplaceString(s1, delim+delim+delim, delim+'¦¦');
  s1:=ReplaceString(s1, delim+delim, '¦¦');

  if(Copy(s1, Length(s1), 1)<>sep)then
    s1:=s1+sep;

  theCount:=0;
  p2:=1;
  p1:=1;
  while(Pos(sep, s1)>0)and(theCount<=colnr)do
  begin
    //if sep is found, check if there is a delim before the sep
    if(DMMain.GetSubStringCountInString(Copy(s1, 1, Pos(sep, s1)-1), delim) mod 2=0)then
    begin
      inc(theCount);
      p1:=p2;
      p2:=p2+Pos(sep, s1);
      s1:=Copy(s1, Pos(sep, s1)+1, Length(s1));
    end
    else
      Delete(s1, Pos(sep, s1), 1);
  end;

  s1:=Trim(Copy(s, p1, p2-p1-1));
  if(s1<>'')then
    if(s1[1]=delim)then
      s1:=Copy(s1, 2, Length(s1)-2);

  GetColumnFromSepString:=ReplaceString(s1, delim+delim, delim);
end;

function TDMMain.GetColumnFromFixLengthString(s: string;
  colnr: integer; SList: TStringList): string;
begin
  if(colnr>=0)and(colnr<SList.Count-1)then
    GetColumnFromFixLengthString:=Copy(s,
      StrToInt(SList[colnr]),
      StrToInt(SList[colnr+1])-StrToInt(SList[colnr]))
  else
    GetColumnFromFixLengthString:='';
end;

function TDMMain.GetValueFromSQLInsert(FieldName, InsertStr: string): string;
var fpos, valpos, i: integer;
  valstr, s: string;
begin
  InsertStr:=Uppercase(Copy(InsertStr, Pos('(', InsertStr)+1, Length(InsertStr)));
  FieldName:=Uppercase(FieldName);

  //the field could be at the very beginning
  if(Copy(InsertStr, 1, Length(FieldName))=FieldName)and
    ((Copy(InsertStr, Length(FieldName)+1, 1)=',')or
      (Copy(InsertStr, Length(FieldName)+1, 1)=' '))then
    fpos:=1
  else
    fpos:=0;

  //Find field, leading by , or space and followed by , or space
  if(fpos=0)then
    fpos:=Pos(' '+FieldName+',', UpperCase(InsertStr));
  if(fpos=0)then
    fpos:=Pos(','+FieldName+',', UpperCase(InsertStr));
  if(fpos=0)then
    fpos:=Pos(' '+FieldName+' ', UpperCase(InsertStr));
  if(fpos=0)then
    fpos:=Pos(','+FieldName+' ', UpperCase(InsertStr));
  if(fpos=0)then
    fpos:=Pos(' '+FieldName+')', UpperCase(InsertStr));
  if(fpos=0)then
    fpos:=Pos(','+FieldName+')', UpperCase(InsertStr));

  if(fpos>0)then
  begin
    //get position of field
    valpos:=GetSubStringCountInString(Copy(InsertStr, 1, fpos+1), ',');

    i:=Pos('VALUES(', UpperCase(InsertStr));
    if(i=0)then
      i:=Pos('VALUES ', UpperCase(InsertStr));

    //Get string of values and eliminate possible leading (
    valstr:=trim(Copy(InsertStr, i+7, Length(InsertStr)-7-i));
    if(Copy(valstr, 1, 1)='(')then
      valstr:=Copy(valstr, 2, Length(valstr));

    s:=GetColumnFromSepString(valstr, valpos, ',', '''');

    GetValueFromSQLInsert:=Trim(s);
  end
  else
    GetValueFromSQLInsert:='NOTININSERT';

end;

//The dialogs come from CLX forms that were laid out in fixed pixels for a
//font of 8 points. Two things do not fit the LCL:
// - Another application font (or a longer translation) does not fit the
//   fixed positions. The whole dialog is scaled by the ratio of the font
//   heights, the way a form is scaled to another DPI.
// - The controls in a group box are placed relative to its frame, in the LCL
//   they are placed relative to the area below the caption. They lie lower
//   by the height of the caption and the last ones are cut off.
//From now on the LCL scales the form to the display it is on
//(TCustomForm.Scaled); the marker follows with the bitmaps
procedure TLayoutMarker.Watch(theForm: TCustomForm; theDPI: integer);
begin
  DPI:=theDPI;
  Form:=theForm;
  if(Not(Application.Scaled))then
    Exit;

  TCustomDesignControl(theForm).PixelsPerInch:=theDPI;
  TCustomDesignControl(theForm).Scaled:=True;

  OldWndProc:=theForm.WindowProc;
  theForm.WindowProc:=WndProc;
end;

destructor TLayoutMarker.Destroy;
begin
  if(Form<>nil)and(Assigned(OldWndProc))then
    Form.WindowProc:=OldWndProc;
  inherited;
end;

procedure TLayoutMarker.WndProc(var TheMessage: TLMessage);
var OldDPI, NewDPI: integer;
begin
  OldWndProc(TheMessage);

  if(InChange)or(csDestroying in Form.ComponentState)then
    Exit;
  NewDPI:=TCustomDesignControl(Form).PixelsPerInch;
  if(NewDPI=DPI)or(NewDPI<=0)then
    Exit;

  InChange:=True;
  try
    OldDPI:=DPI;
    DPI:=NewDPI;
    DesignWidth:=MulDiv(DesignWidth, NewDPI, OldDPI);
    DesignHeight:=MulDiv(DesignHeight, NewDPI, OldDPI);

    RescaleFormGraphics(Form, NewDPI);

    if(Assigned(DMMain))and(Assigned(DMMain.OnFormDPIChanged))then
      DMMain.OnFormDPIChanged(Form, OldDPI, NewDPI);
  finally
    InChange:=False;
  end;
end;

procedure TDMMain.FollowDPI(theForm: TCustomForm; NewDPI: integer);
var Marker: TLayoutMarker;
begin
  if(theForm=nil)or(Not(theForm.FindComponent(LayoutDoneName) is TLayoutMarker))then
    Exit;
  Marker:=TLayoutMarker(theForm.FindComponent(LayoutDoneName));
  if(Marker.DPI=NewDPI)or(Marker.InChange)then
    Exit;

  Marker.InChange:=True;
  try
    RescaleFormGraphics(theForm, NewDPI);

    //the form itself is not shown
    theForm.SetBounds(theForm.Left, theForm.Top,
      MulDiv(theForm.Width, NewDPI, Marker.DPI), MulDiv(theForm.Height, NewDPI, Marker.DPI));
    Marker.DesignWidth:=MulDiv(Marker.DesignWidth, NewDPI, Marker.DPI);
    Marker.DesignHeight:=MulDiv(Marker.DesignHeight, NewDPI, Marker.DPI);
    Marker.DPI:=NewDPI;
    if(TCustomDesignControl(theForm).Scaled)then
      TCustomDesignControl(theForm).PixelsPerInch:=NewDPI;
  finally
    Marker.InChange:=False;
  end;
end;

//Height of a line of text in the application font
function ApplicationTextHeight: integer;
var bmp: Graphics.TBitmap;
begin
  bmp:=Graphics.TBitmap.Create;
  try
    bmp.Canvas.Font.Name:=DMMain.ApplicationFontName;
    bmp.Canvas.Font.Size:=DMMain.ApplicationFontSize;
    bmp.Canvas.Font.Style:=DMMain.ApplicationFontStyle;
    Result:=bmp.Canvas.TextHeight('Ag');
  finally
    bmp.Free;
  end;
end;

function TDMMain.ScaleForFont(Value: integer; theForm: TCustomForm = nil): integer;
var TextH: integer;
begin
  Result:=Value;
  if(FitDialogsToFont)then
  begin
    TextH:=ApplicationTextHeight;
    if(TextH>0)then
      Result:=MulDiv(Value, TextH, DesignTextHeight);

    //the text height is that of the primary display
    if(theForm<>nil)then
      Result:=MulDiv(Result, FormDPI(theForm), UIDPI);
  end;
end;

//A label that is right justified or centred keeps its position in CLX. In
//the LCL it is sized to its text from the left and the text ends up at the
//left of the place it was designed for, i.e. below the control before it:
//such labels keep the width of the design
procedure KeepAlignedLabels(theForm: TForm);
var i: integer;
begin
  for i:=0 to theForm.ComponentCount-1 do
    if(theForm.Components[i] is TLabel)then
      with TLabel(theForm.Components[i]) do
        if(Alignment<>taLeftJustify)and(AutoSize)then
        begin
          AutoSize:=False;
          //the form stores no height for a label that sizes itself
          if(Height<DesignTextHeight)then
            Height:=DesignTextHeight;
        end;
end;

//... and grow to the side the text starts from when a translation is longer
procedure WidenAlignedLabels(theForm: TForm);
var i, w: integer;
  bmp: Graphics.TBitmap;
begin
  bmp:=Graphics.TBitmap.Create;
  try
    for i:=0 to theForm.ComponentCount-1 do
      if(theForm.Components[i] is TLabel)then
        with TLabel(theForm.Components[i]) do
          if(Alignment<>taLeftJustify)and(Not(AutoSize))and(Not(WordWrap))and
            (Align=alNone)then
          begin
            bmp.Canvas.Font.Assign(Font);
            w:=bmp.Canvas.TextHeight('Ag');
            if(w>Height)then
              Height:=w;
            w:=bmp.Canvas.TextWidth(Caption);
            if(w>Width)then
            begin
              if(Alignment=taRightJustify)then
                SetBounds(Left-(w-Width), Top, w, Height)
              else
                SetBounds(Left-(w-Width) div 2, Top, w, Height);
            end;
          end;
  finally
    bmp.Free;
  end;
end;

procedure TDMMain.FitFormLayout(theForm: TForm);
var TextH, i, k, delta, minTop: integer;
  Marker: TLayoutMarker;
  G: TGroupBox;

  //The fonts the forms carry for single controls are those of the CLX
  //design (Sans, 9 or 11 pixels): take the application font, keep the style
  procedure UnifyFonts(aControl: TControl);
  var n: integer;
  begin
    with TLayoutControl(aControl) do
      if(Not(ParentFont))then
        if(CompareText(Font.Name, 'Sans')=0)or(CompareText(Font.Name, 'default')=0)or
          (Font.Name='')then
        begin
          Font.Name:=ApplicationFontName;
          Font.Size:=ApplicationFontSize;
        end
        //another font (monospace, ...) keeps its proportion
        else if(Font.Height<>0)and(TextH<>DesignTextHeight)then
          Font.Height:=MulDiv(Font.Height, TextH, DesignTextHeight);

    if(aControl is TWinControl)then
      for n:=0 to TWinControl(aControl).ControlCount-1 do
        UnifyFonts(TWinControl(aControl).Controls[n]);
  end;

  //What TWinControl.AutoAdjustLayout does to scale a form to another DPI
  //(it knows the anchors), without its scaling of the fonts
  procedure ScaleLayout(aControl: TControl; Factor: double);
  var n: integer;
  begin
    if(aControl is TWinControl)then
      for n:=0 to TWinControl(aControl).ControlCount-1 do
        ScaleLayout(TWinControl(aControl).Controls[n], Factor);

    TLayoutControl(aControl).DoAutoAdjustLayout(lapAutoAdjustForDPI,
      Factor, Factor);
  end;

begin
  if(Not(FitDialogsToFont))or(theForm.FindComponent(LayoutDoneName)<>nil)then
    Exit;

  //The model windows hold nothing but the model
  if(theForm.ClassNameIs('TEERForm'))then
    Exit;

  //The main window, the palettes and the docked query editor fit themselves
  //to the font. They are laid out in the pixels of a display of 96 DPI
  if((theForm.ClassNameIs('TMainForm'))and(Not(MainFormIsDialog)))or
    (theForm.ClassNameIs('TPaletteNavForm'))or(theForm.ClassNameIs('TPaletteDataTypesForm'))or
    (theForm.ClassNameIs('TPaletteModelFrom'))or(theForm.ClassNameIs('TPaletteToolsForm'))or
    (theForm.ClassNameIs('TEditorQueryForm'))or(theForm.ClassNameIs('TSplashForm'))then
  begin
    Marker:=TLayoutMarker.Create(theForm);
    Marker.Name:=LayoutDoneName;

    //They live in the main window (the palettes, the query editor): in the
    //DPI of the display the main window is on now
    TextH:=CurrentDPI;
    if(TextH<>DesignDPI)then
    begin
      theForm.HandleNeeded;
      theForm.DisableAutoSizing;
      try
        ScaleLayout(theForm, TextH/DesignDPI);
      finally
        theForm.EnableAutoSizing;
      end;
    end;
    RescaleFormGraphics(theForm, TextH);

    Marker.DesignWidth:=theForm.Width;
    Marker.DesignHeight:=theForm.Height;
    Marker.Watch(theForm, TextH);
    Exit;
  end;

  //the application font is not known before the main window is there
  if(Application.MainForm=nil)and(Not(MainFormIsDialog))then
    Exit;

  Marker:=TLayoutMarker.Create(theForm);
  Marker.Name:=LayoutDoneName;

  TextH:=ApplicationTextHeight;

  //before the handle and with it the automatic sizes
  KeepAlignedLabels(theForm);

  //Without a handle a form reports a client area of 320x240, and the
  //controls that are anchored to its right or bottom edge are scaled
  //relative to that
  theForm.HandleNeeded;

  theForm.DisableAutoSizing;
  try
    //The fonts are set below
    if(TextH>0)and(TextH<>DesignTextHeight)then
      ScaleLayout(theForm, TextH/DesignTextHeight);

    theForm.Font.Name:=ApplicationFontName;
    theForm.Font.Size:=ApplicationFontSize;
    theForm.Font.Style:=ApplicationFontStyle;
    for i:=0 to theForm.ControlCount-1 do
      UnifyFonts(theForm.Controls[i]);

    //Group boxes: move the controls up by the height of the caption
    for i:=0 to theForm.ComponentCount-1 do
      if(theForm.Components[i] is TGroupBox)then
      begin
        G:=TGroupBox(theForm.Components[i]);
        if(G.ControlCount=0)then
          continue;

        //the caption is as high as the text
        delta:=TextH;

        minTop:=MaxInt;
        for k:=0 to G.ControlCount-1 do
          if(G.Controls[k].Align=alNone)and(G.Controls[k].Top<minTop)then
            minTop:=G.Controls[k].Top;

        //A box that is laid out for the LCL already has its first control
        //at the top
        if(minTop<>MaxInt)and(minTop>=delta-2)then
        begin
          if(delta>minTop-3)then
            delta:=minTop-3;
          for k:=0 to G.ControlCount-1 do
            if(G.Controls[k].Align=alNone)then
            begin
              if(Not(akBottom in G.Controls[k].Anchors))then
                G.Controls[k].Top:=G.Controls[k].Top-delta
              //A control that follows the height of the box: its top moves
              //up like the others. Its bottom has to come up by what the
              //client area is smaller than the box (the LCL does that for
              //the controls that are anchored to the bottom only, but
              //setting the bounds here makes them the new base of the anchor)
              else if(akTop in G.Controls[k].Anchors)then
                G.Controls[k].SetBounds(G.Controls[k].Left, G.Controls[k].Top-delta,
                  G.Controls[k].Width,
                  G.Controls[k].Height+delta-(G.Height-G.ClientHeight));
            end;
        end;
      end;
  finally
    theForm.EnableAutoSizing;
  end;

  //the bitmaps follow the DPI of the display
  ScaleFormGraphics(theForm);

  Marker.DesignWidth:=theForm.Width;
  Marker.DesignHeight:=theForm.Height;
  //laid out for the primary display; the LCL scales it when it is shown on
  //another one
  Marker.Watch(theForm, UIDPI);
end;

procedure TDMMain.InitForm(theForm: TForm; SetFloatOnTop: Boolean = False; Translate: Boolean = True);
begin
  //Once per form, before the font of the form is set
  FitFormLayout(theForm);

  theForm.Font.Name:=ApplicationFontName;
  theForm.Font.Size:=ApplicationFontSize;
  theForm.Font.Style:=ApplicationFontStyle;

  //Make Editors float on top if requested by the user
  if(SetFloatOnTop)then
    theForm.FormStyle:=fsStayOnTop;

  //Make Translation
  if(Translate)then
    TranslateForm(theForm);

  if(theForm.FindComponent(LayoutDoneName)<>nil)then
    WidenAlignedLabels(theForm);
end;

procedure TDMMain.LoadLanguageFromIniFile;
var theIni: TMemIniFile;
begin
  //Open IniFile
  theIni:=TMemIniFile.Create(SettingsPath+'Language.ini');
  try
    LanguageCode:=theIni.ReadString('GeneralSettings', 'Language', 'en');
    if(LanguageCode='')then
      LanguageCode:='en';
  finally
    theIni.Free;
  end;
end;

procedure TDMMain.SaveLanguageToIniFile;
var theIni: TMemIniFile;
begin
  //The language is loaded by the main form only. A program that never
  //loaded it (a plugin, a test program) must not store its empty language:
  //that reset the main program to English at its next start
  if(LanguageCode='')then
    Exit;

  //Open IniFile
  theIni:=TMemIniFile.Create(SettingsPath+'Language.ini');
  try
    theIni.WriteString('GeneralSettings', 'Language', LanguageCode);

    UpdateIniFile(theIni);
  finally
    theIni.Free;
  end;
end;

procedure TDMMain.GetSectionFromTxtFile(filename, section: string; theStringList: TStringList; GetOnlyValues: Boolean = False);
var tmpStringList: TStringList;
  i: integer;
  SectionReached: Boolean;
  s: string;
begin
  theStringList.Clear;

  tmpStringList:=TStringList.Create;
  try
    tmpStringList.LoadFromFile(filename);
    //The translation files are Latin-1; the LCL needs UTF-8
    s:=tmpStringList.Text;
    if(FindInvalidUTF8Codepoint(PChar(s), Length(s))>=0)then
      tmpStringList.Text:=CP1252ToUTF8(s);
    i:=0;
    SectionReached:=False;
    while(i<tmpStringList.Count)do
    begin
      if(Not(SectionReached))then
      begin
        if(tmpStringList[i]='['+section+']')then
          SectionReached:=True;
      end
      else
      begin
        if(Copy(tmpStringList[i], 1, 1)<>'[')then
        begin
          if(Copy(tmpStringList[i], 1, 2)=LanguageCode)then
            if(GetOnlyValues)then
              theStringList.Add(tmpStringList.ValueFromIndex[i])
            else
              theStringList.Add(tmpStringList[i]);
        end
        else
          break;
      end;

      inc(i);
    end;
  finally
    tmpStringList.Free;
  end;
end;

type
  //Caption is protected in TControl
  TTranslateControl = class(TControl);

procedure TDMMain.TranslateForm(theForm: TForm);
var theStringList: TStringList;
  i, j: integer;
  trans_caption, trans_hint, s1, s2: string;

  procedure TranslateItems(theItems: TStrings; const key: string);
  var k: integer;
    s: string;
  begin
    for k:=0 to theItems.Count-1 do
    begin
      s:=theStringList.Values[key+Format('%.2d', [k+1])];
      if(s<>'')then
        theItems[k]:=s;
    end;
  end;

begin
  if(Not(FileExists(TranslationsFile)))then
    Exit;

  //The main window of a plugin has the name of the main window of the
  //program, but not its controls
  if(MainFormIsDialog)and(theForm.ClassNameIs('TMainForm'))then
    Exit;

  theStringList:=TStringList.Create;
  try
    GetSectionFromTxtFile(TranslationsFile,
      theForm.Name, theStringList);

    //The caption of the form itself. Not the main window and the model
    //windows: their captions carry the name of the model
    if(Not(theForm.ClassNameIs('TMainForm')))and(Not(theForm.ClassNameIs('TEERForm')))then
    begin
      s2:=theStringList.Values[LanguageCode+'_'+theForm.ClassName+'_'+theForm.Name];
      if(s2<>'')then
        theForm.Caption:=s2;
    end;

    for i:=0 to theForm.ComponentCount-1 do
    begin
      s1:=LanguageCode+'_'+theForm.Components[i].ClassName+'_';
      s1:=s1+theForm.Components[i].Name;
      trans_caption:=ReplaceString(theStringList.Values[s1], '\039', '''');
      trans_hint:=ReplaceString(ReplaceString(theStringList.Values[s1+'_Hint'], '\039', ''''), '\n', #13#10);

      if(trans_caption<>'')then
      begin
        if(theForm.Components[i].ClassParent=TForm)then
          TForm(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TSpeedButton'))then
          TSpeedButton(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TBitBtn'))then
          TBitBtn(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TTabSheet'))then
          TTabSheet(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TLabel'))then
          TLabel(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TPanel'))then
          TPanel(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TGroupBox'))then
          TGroupBox(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TMenuItem'))then
          TMenuItem(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TCheckBox'))then
          TCheckBox(theForm.Components[i]).Caption:=trans_caption
        else if(theForm.Components[i].ClassNameIs('TRadioButton'))then
          TRadioButton(theForm.Components[i]).Caption:=trans_caption
        //Every other control with a caption (TButton, TRadioGroup, ...).
        //Not edits and combo boxes: their caption is their text
        else if(theForm.Components[i] is TControl)and
          (Not(theForm.Components[i] is TCustomEdit))and
          (Not(theForm.Components[i] is TCustomComboBox))then
          TTranslateControl(theForm.Components[i]).Caption:=trans_caption;
      end;

      if(trans_hint<>'')then
      begin
        if(theForm.Components[i].ClassParent=TForm)then
          TForm(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TSpeedButton'))then
          TSpeedButton(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TBitBtn'))then
          TBitBtn(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TTabSheet'))then
          TTabSheet(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TLabel'))then
          TLabel(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TPanel'))then
          TPanel(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TGroupBox'))then
          TGroupBox(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TMenuItem'))then
          TMenuItem(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TCheckBox'))then
          TCheckBox(theForm.Components[i]).Hint:=trans_hint
        else if(theForm.Components[i].ClassNameIs('TRadioButton'))then
          TRadioButton(theForm.Components[i]).Hint:=trans_hint
        //Every other control (TImage, TEdit, TButton, ...)
        else if(theForm.Components[i] is TControl)then
          TControl(theForm.Components[i]).Hint:=trans_hint;
      end;

      //The items of combo boxes, list boxes and radio groups
      //(..._Item01, ..._Item02, ...) and the columns of list views
      //(..._Column01, ...). Only the entries the file has are replaced
      if(theForm.Components[i] is TCustomComboBox)then
      begin
        j:=TCustomComboBox(theForm.Components[i]).ItemIndex;
        TranslateItems(TCustomComboBox(theForm.Components[i]).Items, s1+'_Item');
        TCustomComboBox(theForm.Components[i]).ItemIndex:=j;
      end
      else if(theForm.Components[i] is TCustomListBox)then
        TranslateItems(TCustomListBox(theForm.Components[i]).Items, s1+'_Item')
      else if(theForm.Components[i] is TCustomRadioGroup)then
        TranslateItems(TCustomRadioGroup(theForm.Components[i]).Items, s1+'_Item')
      else if(theForm.Components[i] is TListView)then
        for j:=0 to TListView(theForm.Components[i]).Columns.Count-1 do
        begin
          s2:=theStringList.Values[s1+'_Column'+Format('%.2d', [j+1])];
          if(s2<>'')then
            TListView(theForm.Components[i]).Columns[j].Caption:=s2;
        end;
    end;
  finally
    theStringList.Free;
  end;
end;

procedure TDMMain.GetFormResourceStrings(theForm: TForm; name: string; theStrings: TStringList);
var i: integer;
begin
  if(Not(FileExists(TranslationsFile)))then
    Exit;

  GetSectionFromTxtFile(TranslationsFile,
    theForm.Name+'_ResourceStrings', theStrings, False);

  //Filter ResourceStrings by provided name
  i:=0;
  while(i<theStrings.Count)do
  begin
    if(CompareText(Copy(theStrings[i], 4, Length(name)), name)<>0)then
      theStrings.Delete(i)
    else
    begin
      theStrings[i]:=theStrings.ValueFromIndex[i];
      inc(i);
    end;
  end;
end;

procedure TDMMain.LoadTranslatedMessages;
begin
  if(Not(FileExists(TranslationsFile)))then
    Exit;

  GetSectionFromTxtFile(TranslationsFile,
    'Messages', MessageCaptions, True);
end;

function TDMMain.TranslationsFile: string;
begin
  //A plugin has no translations of its own: the dialogs it shares with the
  //main program (database connections ...) take those of the main program
  Result:=SettingsPath+ProgName+'_Translations.txt';
  if(Not(FileExists(Result)))then
    Result:=SettingsPath+'DBDesignerFork_Translations.txt';
end;

function TDMMain.GetTranslatedMessage(OriginalMsg: string; MsgNr: integer; StrToInsert: string = ''; StrToInsert2: string = ''): string;
var s: string;
begin
  if(MsgNr>=0)and(MsgNr<=MessageCaptions.Count)then
    s:=MessageCaptions[MsgNr-1]
  else
    s:=OriginalMsg;

  //Insert first StrToInsert
  if(Pos('%s', s)>0)then
    s:=Copy(s, 1, Pos('%s', s)-1)+StrToInsert+Copy(s, Pos('%s', s)+2, Length(s));

  //Insert second StrToInsert
  if(Pos('%s', s)>0)then
    s:=Copy(s, 1, Pos('%s', s)-1)+StrToInsert2+Copy(s, Pos('%s', s)+2, Length(s));

  s:=ReplaceString(s, '\n', #13#10);
  s:=ReplaceString(s, '\039', '''');
  s:=ReplaceString(s, '\\', '\');

  GetTranslatedMessage:=s;
end;

procedure TDMMain.ResetProgramLanguage;
var i: integer;
begin
  LoadTranslatedMessages;

  for i:=0 to Screen.FormCount-1 do
    TranslateForm(Screen.Forms[i]);
end;

function TDMMain.GetLanguageCode: string;
begin
  GetLanguageCode:=LanguageCode;
end;

procedure TDMMain.SetLanguageCode(LanguageCode: string);
begin
  self.LanguageCode:=LanguageCode;
  ResetProgramLanguage;
end;

procedure TDMMain.DelFilesFromDir(dirname, fname: string);
var result: integer;
  SearchRec: TSearchRec;
begin
  //Check if dirname is ended with a PathDelim
  if(Copy(dirname, Length(dirname), 1)<>PathDelim)then
    dirname:=dirname+PathDelim;

  Result := FindFirst(dirname+fname, 0, SearchRec);
  if(Result<>0)then
    Exit;

  try
    while Result = 0 do
    begin
      DeleteFile(dirname+PathDelim+SearchRec.Name);

      Result := FindNext(SearchRec);
    end;
  finally
    FindClose(SearchRec);
  end;
end;


procedure TDMMain.DelDir(name: string);
var result: integer;
  SearchRec: TSearchRec;
begin
  if(copy(name, Length(name), 1)<>PathDelim)then
    name:=name+PathDelim;

  Result := FindFirst(name+'*.*', 0, SearchRec);
  if(Result<>0)then
    Exit;

  try
    while Result = 0 do
    begin
      DeleteFile(name+SearchRec.Name);

      Result := FindNext(SearchRec);
    end;
  finally
    FindClose(SearchRec);
  end;
end;

procedure TDMMain.DelDirRecursive(name: string);
var SearchRec: TSearchRec;
begin
  if(copy(name, Length(name), 1)<>PathDelim)then
    name:=name+PathDelim;

  if FindFirst(name+'*.*', faDirectory, SearchRec) = 0 then
  begin
    repeat
      if((SearchRec.Attr and faDirectory) = faDirectory)then
      begin
        //Ignore . and ..
        if(Copy(SearchRec.name, 1, 1)='.')then
          continue;

        //Copy the directory
        DelDir(name+SearchRec.name);

        //call recursive
        DelDirRecursive(name+SearchRec.name);
      end;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;

  //delCopy the directory
  DelDir(name);
  try
    rmdir(name);
  except
  end;
end;

procedure TDMMain.CopyDir(fromdir, todir: string; PromptBeforeOverwrite: Boolean);
var result: integer;
  Ergebnis: integer;
  SearchRec: TSearchRec;
begin
  Ergebnis:=0;

  ForceDirectories(todir);

  try
    //Copy directory
    Ergebnis := FindFirst(fromdir+'*.*', faAnyFile, SearchRec);
    result:=Ergebnis;
    while Result = 0 do
    begin
      if((SearchRec.Attr and faDirectory) <> faDirectory)then
        CopyDiskFile(fromdir+SearchRec.Name,
          todir+SearchRec.Name, PromptBeforeOverwrite);

      Result := FindNext(SearchRec);
    end;
  finally
    if(Ergebnis=0)then
      FindClose(SearchRec);
  end;
end;

procedure TDMMain.CopyDirRecursive(fromdir, todir: string; PromptBeforeOverwrite: Boolean);
var SearchRec: TSearchRec;
begin
  if(copy(fromdir, Length(fromdir), 1)<>PathDelim)then
    fromdir:=fromdir+PathDelim;

  if(copy(todir, Length(todir), 1)<>PathDelim)then
    todir:=todir+PathDelim;

  //Copy the directory
  CopyDir(fromdir, todir, PromptBeforeOverwrite);

  if FindFirst(fromdir+'*.*', faDirectory, SearchRec) = 0 then
  begin
    repeat
      if((SearchRec.Attr and faDirectory) = faDirectory)then
      begin
        //Ignore . and ..
        if(Copy(SearchRec.name, 1, 1)='.')then
          continue;

        //Copy the directory
        CopyDir(fromdir+SearchRec.name, todir+SearchRec.name, PromptBeforeOverwrite);

        //call recursive
        CopyDirRecursive(fromdir+SearchRec.name, todir+SearchRec.name, PromptBeforeOverwrite);
      end;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;
end;

procedure TDMMain.ReverseList(ObjList: TList);
var i: integer;
begin
  for i:=0 to (ObjList.Count-2) div 2 do
    ObjList.Exchange(i, ObjList.Count-1-i);
end;

//--------------------------------------------------
// Only Win32
// get a Window handle
// uses global global_winname

{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
function GetText(Wnd: HWND): string;
var
  textlength: Integer; 
  Text: PChar; 
begin 
  textlength := SendMessage(Wnd, WM_GETTEXTLENGTH, 0, 0);
  if textlength = 0 then Result := '' 
  else
  begin
    GetMem(Text, textlength + 1);
    SendMessage(Wnd, WM_GETTEXT, textlength + 1, Integer(Text));
    Result := Text;
    FreeMem(Text);
  end;
end;

function EnumWindowsProc(Wnd: HWND; lParam: lParam): BOOL; stdcall;
begin
  Result := True;
  //ShowMessage('Handle: ' + IntToStr(Wnd) + ',Text:  ' + GetText(Wnd));

  if(Pos(global_winname, GetText(Wnd))>0)then
  begin
    PHWnd(lParam)^:=Wnd;
    Result := false;
  end;
end;


function TDMMain.GetWindowHandle(wTitle: String): HWnd;
var theWnd: HWnd;
begin
  theWnd := 0;
  Result:=0;
  global_winname:=wTitle;

  EnumWindows(@EnumWindowsProc, LongInt(@theWnd));
  if(theWnd<>0)then
    Result:=theWnd;
end;

procedure TDMMain.SetWinPos(Handle, x, y, w, h: integer);
begin
  SetWindowPos(Handle, HWND_NOTOPMOST, x, y, w, h, SWP_SHOWWINDOW);
end;

{$IFEND}


{$IFDEF MSWINDOWS}
//Because of a Delphi Bug, the Open Dlg is always
//displayed on the left upper corner
//To fix this, catch OnShow Event and reposition the Dlg
{$IFDEF FPC}
//The LCL uses the native Win32 dialogs, which position themselves
procedure TDMMain.OnOpenSaveDlgShow(Sender: TObject);
begin
end;
{$ELSE}
procedure TDMMain.OnOpenSaveDlgShow(Sender: TObject);
var theWinHandle: integer;
  theTitle: string;
  dlg_width, dlg_height: integer;
begin
  theTitle:='';
  dlg_width:=0;
  dlg_height:=0;

  if(Sender.ClassNameIs('TOpenDialog'))then
  begin
    theTitle:=TOpenDialog(Sender).Title;
    if(TOpenDialog(Sender).Width=600)then
      TOpenDialog(Sender).Width:=660;
    if(TOpenDialog(Sender).Height=360)then
      TOpenDialog(Sender).Height:=430;
    dlg_width:=TOpenDialog(Sender).Width;
    dlg_height:=TOpenDialog(Sender).Height;
  end
  else if(Sender.ClassNameIs('TSaveDialog'))then
  begin
    theTitle:=TSaveDialog(Sender).Title;
    if(TSaveDialog(Sender).Width=600)then
      TSaveDialog(Sender).Width:=660;
    if(TSaveDialog(Sender).Height=360)then
      TSaveDialog(Sender).Height:=430;
    dlg_width:=TSaveDialog(Sender).Width;
    dlg_height:=TSaveDialog(Sender).Height;
  end;

  theWinHandle:=DMMain.GetWindowHandle(theTitle);
  if(theWinHandle<>0)then
    DMMain.SetWinPos(theWinHandle,
      Application.MainForm.Left+Application.MainForm.Width div 2-dlg_width div 2,
      Application.MainForm.Top+Application.MainForm.Height div 2-dlg_height div 2,
      dlg_width, dlg_height);
end;
{$ENDIF}
{$ENDIF}

procedure TDMMain.SaveBitmap(Bmp: {$IFDEF FPC}TBitmap{$ELSE}QPixmapH{$ENDIF}; FileName: string; FileType: string; JPGQuality: integer = 75);
{$IFDEF FPC}
var
  Png: TPortableNetworkGraphic;
  Jpg: TJPEGImage;
begin
  if(Copy(FileType, 1, 1)='.')then
    FileType:=Copy(FileType, 2, Length(FileType));

  //Work on the caller's TBitmap directly. The former code wrapped
  //Bmp.Handle in a second TBitmap; under the LCL the wrapper deleted the
  //shared GDI handle and the caller's Free then raised
  //"TGtk2WidgetSet.DeleteObject invalid GdiObject" (shown as "Division by
  //zero" because RaiseGDBException uses SIGFPE) - model-edit #39.
  if(Uppercase(FileType)='PNG')then
  begin
    Png := TPortableNetworkGraphic.Create;
    try
      Png.Assign(Bmp);
      Png.SaveToFile(FileName);
    finally
      Png.Free;
    end;
  end
  else if(Uppercase(FileType)='JPEG')or(Uppercase(FileType)='JPG')then
  begin
    Jpg := TJPEGImage.Create;
    try
      Jpg.Assign(Bmp);
      Jpg.CompressionQuality := JPGQuality;
      Jpg.SaveToFile(FileName);
    finally
      Jpg.Free;
    end;
  end
  else
    Bmp.SaveToFile(FileName);
end;
{$ELSE}
var lWideStr: WideString;
begin
  lWideStr:=FileName;
  if(Copy(FileType, 1, 1)='.')then
    FileType:=Copy(FileType, 2, Length(FileType));
  if(Uppercase(FileType)='PNG')or(Uppercase(FileType)='BMP')then
    QPixMap_save(Bmp, @lWideStr, PChar(Uppercase(FileType)))
  else if(FileType='JPEG')or(FileType='JPG')then
    QPixMap_save(Bmp, @lWideStr, PChar('JPEG'), JPGQuality);
end;
{$ENDIF}

function TDMMain.GetFileSize(fname: string): string;
var f: file of Byte;
begin
  try
    AssignFile(f, fname);
    Reset(f);
    GetFileSize:=IntToStr(FileSize(f));
    CloseFile(f);

  except
    GetFileSize:='0';
  end;
end;

function TDMMain.GetFileDate(fname: string): TDateTime;
begin
  GetFileDate:=FileDateToDateTime(FileAge(fname));
end;

function TDMMain.LoadValueFromSettingsIniFile(section, name, default: string): string;
var theIni: TMemIniFile;
begin
  //Read IniFile
  theIni:=TMemIniFile.Create(SettingsPath+ProgName+'_Settings.ini');
  try
    LoadValueFromSettingsIniFile:=
      theIni.ReadString(section, name, default);
  finally
    theIni.Free;
  end;
end;

procedure TDMMain.SaveValueInSettingsIniFile(section, name, value: string);
var theIni: TMemIniFile;
begin
  //Read IniFile
  theIni:=TMemIniFile.Create(SettingsPath+ProgName+'_Settings.ini');
  try
    theIni.WriteString(section, name, value);
    UpdateIniFile(theIni);
  finally
    theIni.Free;
  end;
end;

function TDMMain.RGB(r, g, b: BYTE): integer;
begin
  RGB:=(r OR (g SHL 8) OR (b SHL 16));
end;

function TDMMain.HexStringToInt(s: string): integer;
var val, i, ex, z: integer;
begin
  s:=UpperCase(s);
  val:=0;
  ex:=1;
  for i:=Length(s)-1 downto 0 do
  begin
    z:=Ord(s[i+1]);
    if(z>=65)then
      z:=z-65+10
    else
      z:=z-48;

    val:=val+z*ex;
    ex:=ex*16;
  end;

  HexStringToInt:=val;
end;

//-----------------------------------------
//Workaround Code because of Delphi BUG

procedure TDMMain.NormalizeStayOnTopForm(theForm: TForm);
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var P: TPoint;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  QOpenWidget_clearWFlags(QOpenWidgetH(theForm.Handle),
    Cardinal(WidgetFlags_WStyle_StaysOnTop));

  //Get Pos
  P.X := theForm.Left; P.Y := theForm.Top; // LCL replacement for QWidget_pos
  P.X:=P.X+WinPosCorrection[Ord(theForm.BorderStyle)].X;
  P.Y:=P.Y+WinPosCorrection[Ord(theForm.BorderStyle)].Y;

  if(theForm.ParentWidget<>nil)then
    QWidget_reparent(QOpenWidgetH(theForm.Handle),
      QOpenWidgetH(theForm.ParentWidget),
      QOpenWidget_getWFlags(QOpenWidgetH(theForm.Handle)),
      @P, True);
{$IFEND}
end;

procedure TDMMain.MakeFormStayOnTop(theForm: TForm);
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var P: TPoint;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  QOpenWidget_setWFlags(QOpenWidgetH(TForm(theForm).Handle),
    Cardinal(WidgetFlags_WStyle_StaysOnTop));

  //Get Pos
  P.X := theForm.Left; P.Y := theForm.Top; // LCL replacement for QWidget_pos
  P.X:=P.X+WinPosCorrection[Ord(theForm.BorderStyle)].X;
  P.Y:=P.Y+WinPosCorrection[Ord(theForm.BorderStyle)].Y;

  if(theForm.ParentWidget<>nil)then
    QWidget_reparent(QOpenWidgetH(TForm(theForm).Handle),
      QOpenWidgetH(TForm(theForm).ParentWidget),
      QOpenWidget_getWFlags(QOpenWidgetH(TForm(theForm).Handle)),
      @P, True);
{$IFEND}
end;

function TDMMain.IsFormStayingOnTop(theForm: TForm): Boolean;
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var theWFlags: Cardinal;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  theWFlags:=QOpenWidget_getWFlags(QOpenWidgetH(theForm.Handle));

  IsFormStayingOnTop:=(theWFlags and Cardinal(WidgetFlags_WStyle_StaysOnTop))=Cardinal(WidgetFlags_WStyle_StaysOnTop);
{$ELSE}
  IsFormStayingOnTop:=True;
{$IFEND}
end;

procedure TDMMain.NormalizeStayOnTopForms;
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var i: integer;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  LockFormDeactivateTracking:=True;

  TopMostForm:=Screen.ActiveForm;

  StayOnTopForms.Clear;
  for i:=Screen.FormCount-1 downto 0 do
    if(Screen.Forms[i].FormStyle=fsStayOnTop)and
      (Screen.Forms[i].Visible)then
    begin
      StayOnTopForms.Add(Screen.Forms[i]);
      DMMain.NormalizeStayOnTopForm(Screen.Forms[i]);

      Application.ProcessMessages;
    end;

  LockFormDeactivateTracking:=False;
{$IFEND}
end;

procedure TDMMain.RestoreStayOnTopForms;
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
var pos: integer;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS) AND NOT DEFINED(FPC)}
  for pos:=0 to StayOnTopForms.Count-1 do
    if(pos<StayOnTopForms.Count)then
      DMMain.MakeFormStayOnTop(StayOnTopForms[pos]);

  if(TopMostForm<>nil)then
  begin
    TopMostForm.BringToFront;
    TopMostForm.SetFocus;
  end;

  StayOnTopForms.Clear;
{$IFEND}
end;


//Workaround Code because of Delphi BUG END
//-----------------------------------------

function TDMMain.EncodeStreamForXML(theStream: TStream): string;
var s: string;
  theBuffer: Array [0..1024] of Char;
  BytesRead: integer;
  j: integer;
  s2: string;
  z1, z2: integer;
begin
  s:='';

  //Go back to Pos 0
  theStream.Position:=0;

  BytesRead:=1024;

  while(BytesRead=1024)do
  begin
    BytesRead:=theStream.Read(theBuffer, 1024);

    s2:='';
    for j:=0 to BytesRead-1 do
    begin
      z1:=Ord(theBuffer[j]) div 16;
      z2:=Ord(theBuffer[j])-z1*16;
      if(z1>9)then
        s2:=s2+Chr(Ord('A')+z1-10)
      else
        s2:=s2+Chr(Ord('0')+z1);

      if(z2>9)then
        s2:=s2+Chr(Ord('A')+z2-10)
      else
        s2:=s2+Chr(Ord('0')+z2);
    end;
    s:=s+s2;
  end;

  EncodeStreamForXML:=s;
end;


function TDMMain.DecodeStreamFromXML(XMLData: string; theStream: TStream): string;
var z1, z2: integer;
  theBuffer: Array [0..1024] of Char;
  Bytes2Write, BytesWritten: integer;
begin
  Result := '';
  BytesWritten:=0;
  Bytes2Write:=0;
  while(BytesWritten*2<Length(XMLData))do
  begin
    z1:=Ord(XMLData[BytesWritten*2+1]);
    z2:=Ord(XMLData[BytesWritten*2+2]);

    if(z1-Ord('0')>9)then
      z1:=z1-Ord('A')+10
    else
      z1:=z1-Ord('0');

    if(z2-Ord('0')>9)then
      z2:=z2-Ord('A')+10
    else
      z2:=z2-Ord('0');

    theBuffer[Bytes2Write]:=Chr(z1*16+z2);

    inc(Bytes2Write);
    inc(BytesWritten);

    if(Bytes2Write=1024)or(BytesWritten*2=Length(XMLData))then
    begin
      theStream.Write(theBuffer, Bytes2Write);
      Bytes2Write:=0;
    end;
  end;

  //Go back to Pos 0
  theStream.Position:=0;
end;

function TDMMain.CheckIniFileVersion(IniFileName: string; neededVersion: integer): Boolean;
var theIniFile: TMemIniFile;
  s: string;
  CopyNewVersion: Boolean;
begin
  CheckIniFileVersion:=True;

  theIniFile:=TMemIniFile.Create(SettingsPath+IniFileName);
  try
    CopyNewVersion:=False;

    s:=theIniFile.ReadString('GeneralSettings', 'IniFileVersion', '0');

    try
      if(StrToInt(s)<>neededVersion)then
        CopyNewVersion:=True;
    except
      CopyNewVersion:=True
    end;

    if(CopyNewVersion)then
    begin
      CopyDiskFile(ExtractFilepath(Application.ExeName)+'Data'+PathDelim+IniFileName,
        SettingsPath+IniFileName, False);

      CheckIniFileVersion:=False;
    end;

  finally
    theIniFile.Free;
  end;
end;

function TDMMain.GetValidObjectName(name: string): string;
var i, namelength: integer;
begin
  namelength:=Length(name);
  i:=1;
  while(i<=namelength)do
  begin
    if(not(name[i] in VALID_OBJECTNAME_CHARS))then
    begin
      name:=Copy(name, 1, i-1)+Copy(name, i+1, namelength);
      dec(namelength);
    end
    else
      inc(i);
  end;

  GetValidObjectName:=name;
end;


procedure TDMMain.LoadApplicationFont;
var theIni: TMemIniFile;
  s: string;
begin
  //Read IniFile. A plugin has no font setting of its own (its settings file,
  //if there is one, holds other things): it takes the font of the main
  //program
  s:=SettingsPath+ProgName+'_Settings.ini';
  theIni:=TMemIniFile.Create(s);
  if(Not(theIni.ValueExists('GeneralSettings', 'ApplicationFontName')))and
    (FileExists(SettingsPath+'DBDesignerFork_Settings.ini'))then
  begin
    theIni.Free;
    theIni:=TMemIniFile.Create(SettingsPath+'DBDesignerFork_Settings.ini');
  end;
  try
    try
{$IFDEF LINUX}
      ApplicationFontName:=theIni.ReadString('GeneralSettings', 'ApplicationFontName', 'Nimbus Sans L');
      ApplicationFontSize:=StrToInt(theIni.ReadString('GeneralSettings', 'ApplicationFontSize', '8'));
{$ELSE}
      ApplicationFontName:=theIni.ReadString('GeneralSettings', 'ApplicationFontName', 'MS Sans Serif');
      ApplicationFontSize:=StrToInt(theIni.ReadString('GeneralSettings', 'ApplicationFontSize', '8'));
{$ENDIF}
      s:=theIni.ReadString('GeneralSettings', 'ApplicationFontStyle', '');
      ApplicationFontStyle:=[];
      if(Pos('bold', lowercase(s))>0)then
        ApplicationFontStyle:=ApplicationFontStyle+[fsBold]
      else if(Pos('italic', lowercase(s))>0)then
        ApplicationFontStyle:=ApplicationFontStyle+[fsItalic]
      else if(Pos('underline', lowercase(s))>0)then
        ApplicationFontStyle:=ApplicationFontStyle+[fsUnderline]
      else if(Pos('strikeout', lowercase(s))>0)then
        ApplicationFontStyle:=ApplicationFontStyle+[fsStrikeOut];
    except
{$IFDEF LINUX}
      ApplicationFontName:='Nimbus Sans L';
      ApplicationFontSize:=8;
      ApplicationFontStyle:=[];
{$ELSE}
      ApplicationFontName:='MS Sans Serif';
      ApplicationFontSize:=8;
      ApplicationFontStyle:=[];
{$ENDIF}
    end;

    Screen.SystemFont.Name:=ApplicationFontName;
    Screen.SystemFont.Size:=ApplicationFontSize;
    Screen.SystemFont.Style:=ApplicationFontStyle;
  finally
    theIni.Free;
  end;
end;

function sendCLXEvent(receiver: QObjectH; event: QEventH): Boolean;
begin
  {$IFDEF FPC}
  try
    Result := QApplication_sendEvent(receiver, event);
  finally
    QEvent_destroy(event);
  end;
  {$ELSE}
  try
    Result := QApplication_sendEvent(receiver, event);
  finally
    QEvent_destroy(event);
  end;
  {$ENDIF}
end;

// Fill a font combo with the installed font families and select CurrentFont.
// A saved font name (e.g. "Tahoma" from a model created on Windows, or the
// old "Nimbus Sans L" name) is often not installed on this machine; it is
// then inserted at the top of the list so it remains visible and selectable
// instead of leaving the combo blank (or showing the design-time text).
procedure TDMMain.FillFontCBox(CBox: TComboBox; const CurrentFont: string);
var i: integer;
begin
  CBox.Items.BeginUpdate;
  try
    CBox.Items.Assign(Screen.Fonts);
    if(CurrentFont<>'')then
    begin
      i:=CBox.Items.IndexOf(CurrentFont);
      if(i=-1)then
      begin
        CBox.Items.Insert(0, CurrentFont);
        i:=0;
      end;
    end
    else
      i:=-1;
  finally
    CBox.Items.EndUpdate;
  end;
  CBox.ItemIndex:=i;
  CBox.Text:=CurrentFont;
end;

// Return the font chosen in a font combo. The user may pick a list entry
// or type a name; an empty text falls back to DefaultFont.
function TDMMain.GetFontCBoxSelection(CBox: TComboBox; const DefaultFont: string): string;
begin
  Result:=Trim(CBox.Text);
  if(Result='')and(CBox.ItemIndex>=0)then
    Result:=CBox.Items[CBox.ItemIndex];
  if(Result='')then
    Result:=DefaultFont;
end;

procedure UpdateIniFile(theIni: TMemIniFile);
begin
  if SettingsReadOnly then
    theIni.Rename(IncludeTrailingPathDelimiter(GetTempDir(False))+
      'DBDesignerFork_selftest_discard.ini', False);
  theIni.UpdateFile;
end;

function RunningSelfTest: Boolean;
var i: Integer;
begin
  Result:=False;
  for i:=1 to ParamCount do
    if (CompareText(ParamStr(i), '--selftest')=0) or
       (CompareText(ParamStr(i), '-selftest')=0) or
       //a picture of every dialog (UIScreenshots), nothing is to be stored
       (CompareText(ParamStr(i), '--screenshots')=0) then
      Exit(True);
end;

initialization
  SettingsReadOnly:=RunningSelfTest;

end.
