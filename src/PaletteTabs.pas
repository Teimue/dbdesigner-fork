unit PaletteTabs;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit PaletteTabs.pas
// --------------------
// Description
//   The tab strip of the palettes (Navigator, Datatypes, DB Model) and the
//   application font for the controls that carried a fixed pixel font.
//
//   The tab strips were bitmaps of 221x20 pixels in the colours of one
//   desktop theme, and the lists and the status bar had fonts of 9 and 11
//   pixels. So neither followed the application font of the options nor the
//   colours of the system, and the palettes could not get another width.
//   The strips are painted here instead: in the system colours, as high as
//   the application font and as wide as the palette.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, Graphics, Controls, ExtCtrls, ComCtrls;

//Give a control and everything on it the application font. The colour of a
//font is kept
procedure ApplyApplicationFont(aControl: TControl);

//The panel of a palette and the pages of its page control in clBtnFace.
//With the visual styles of Windows a panel without a colour of its own shows
//the background of its parent (the dark grey of the main form when the
//palette is docked) and a tab sheet is white, so the parts of a palette had
//three different backgrounds. A sheet cannot be given a colour: its controls
//are moved onto a panel that fills it
procedure UsePaletteBackground(MainPnl: TPanel; PageControl: TPageControl);

//The height of a line of text in the application font
function ApplicationFontHeight: integer;
function ApplicationFontTextWidth(const s: string): integer;

//Size the tab strip and paint both of its states: TabsImg with the first
//tab in front, Tabs2Img with the second one. PBox1 and PBox2 are the paint
//boxes of the two captions; a PBox2 that is not visible means one tab only
procedure LayoutPaletteTabs(TabsPnl: TPanel; TabsImg, Tabs2Img, OptionsImg: TImage;
  PBox1, PBox2: TPaintBox; const Caption1, Caption2: string);

implementation

uses Math, MainDM;

type
  TControlCracker = class(TControl);

var
  InLayout: Boolean = False;

procedure ApplyApplicationFont(aControl: TControl);
var i: integer;
begin
  with TControlCracker(aControl).Font do
  begin
    Name:=DMMain.ApplicationFontName;
    Size:=DMMain.ApplicationFontSize;
    Style:=DMMain.ApplicationFontStyle;
  end;

  if(aControl is TWinControl)then
    for i:=0 to TWinControl(aControl).ControlCount-1 do
      ApplyApplicationFont(TWinControl(aControl).Controls[i]);
end;

procedure UsePaletteBackground(MainPnl: TPanel; PageControl: TPageControl);
var i: integer;
  Sheet: TTabSheet;
  Back: TPanel;
begin
  MainPnl.ParentColor:=False;
  MainPnl.ParentBackground:=False;
  MainPnl.Color:=clBtnFace;

  for i:=0 to PageControl.PageCount-1 do
  begin
    Sheet:=PageControl.Pages[i];

    Back:=TPanel.Create(Sheet);
    Back.BevelOuter:=bvNone;
    Back.Caption:='';
    Back.ParentBackground:=False;
    Back.Color:=clBtnFace;
    Back.Align:=alClient;
    Back.Parent:=Sheet;

    //Back is the last control of the sheet; the others keep their order
    while(Sheet.ControlCount>1)do
      Sheet.Controls[0].Parent:=Back;
  end;
end;

procedure SetApplicationFont(aCanvas: TCanvas);
begin
  aCanvas.Font.Name:=DMMain.ApplicationFontName;
  aCanvas.Font.Size:=DMMain.ApplicationFontSize;
  aCanvas.Font.Style:=DMMain.ApplicationFontStyle;
end;

function ApplicationFontHeight: integer;
var bmp: TBitmap;
begin
  bmp:=TBitmap.Create;
  try
    SetApplicationFont(bmp.Canvas);
    Result:=bmp.Canvas.TextHeight('Ag');
  finally
    bmp.Free;
  end;
end;

function ApplicationFontTextWidth(const s: string): integer;
var bmp: TBitmap;
begin
  bmp:=TBitmap.Create;
  try
    SetApplicationFont(bmp.Canvas);
    Result:=bmp.Canvas.TextWidth(s);
  finally
    bmp.Free;
  end;
end;

//The colour halfway between two system colours
function MixColors(c1, c2: TColor): TColor;
begin
  c1:=ColorToRGB(c1);
  c2:=ColorToRGB(c2);
  Result:=RGBToColor((Red(c1)+Red(c2)) div 2, (Green(c1)+Green(c2)) div 2,
    (Blue(c1)+Blue(c2)) div 2);
end;

procedure LayoutPaletteTabs(TabsPnl: TPanel; TabsImg, Tabs2Img, OptionsImg: TImage;
  PBox1, PBox2: TPaintBox; const Caption1, Caption2: string);
const
  TabLeft = 4;    //left edge of the first tab
  TabPadding = 7; //between the edge of a tab and its caption
var bmp: TBitmap;
  w, h, th, slant, x1, w1, x2, w2, base: integer;
  TwoTabs: Boolean;

  //A tab with its vertical left edge at x and its top from x to x+tw; the
  //right edge slants down to the base line. The active tab is open at the
  //bottom, it belongs to the page below
  procedure PaintTab(x, tw: integer; Active: Boolean);
  var bottom: integer;
  begin
    with bmp.Canvas do
    begin
      if(Active)then
      begin
        bottom:=h;
        Brush.Color:=clBtnFace;
      end
      else
      begin
        bottom:=base;
        Brush.Color:=MixColors(clBtnFace, clBtnShadow);
      end;

      Pen.Color:=clBlack;
      Polygon([Point(x, bottom), Point(x, 2), Point(x+tw, 2),
        Point(x+tw+slant, base), Point(x+tw+slant, bottom)]);

      //the light from the top left
      Pen.Color:=clBtnHighlight;
      MoveTo(x+1, bottom-1);
      LineTo(x+1, 3);
      LineTo(x+tw, 3);

      if(Active)then
      begin
        //open at the bottom
        Pen.Color:=clBtnFace;
        MoveTo(x+2, base);
        LineTo(x+tw+slant, base);
        MoveTo(x+2, base+1);
        LineTo(x+tw+slant+1, base+1);
      end;
    end;
  end;

  procedure PaintStrip(ActiveTab: integer; theImg: TImage);
  begin
    with bmp.Canvas do
    begin
      Brush.Style:=bsSolid;
      Brush.Color:=clBtnShadow;
      FillRect(Rect(0, 0, w, h));

      //the edge of the page below
      Pen.Color:=clBlack;
      MoveTo(0, base);
      LineTo(w, base);
      Pen.Color:=clBtnHighlight;
      MoveTo(0, base+1);
      LineTo(w, base+1);
    end;

    //the active tab last, it lies on top of its neighbour
    if(TwoTabs)and(ActiveTab=1)then
      PaintTab(x2, w2, False);
    if(ActiveTab=2)then
      PaintTab(x1, w1, False);
    if(ActiveTab=1)then
      PaintTab(x1, w1, True)
    else
      PaintTab(x2, w2, True);

    theImg.AutoSize:=False;
    theImg.Stretch:=False;
    theImg.Transparent:=False;
    theImg.Align:=alNone;
    theImg.Picture.Bitmap.Assign(bmp);
    theImg.SetBounds(0, 0, w, h);
  end;

begin
  if(InLayout)then
    Exit;

  w:=TabsPnl.ClientWidth;
  if(w<=0)then
    Exit;

  InLayout:=True;
  bmp:=TBitmap.Create;
  try
    SetApplicationFont(bmp.Canvas);
    th:=bmp.Canvas.TextHeight('Ag');
    h:=Max(20, th+7);
    base:=h-2;
    slant:=h-7;

    TwoTabs:=(PBox2<>nil)and(PBox2.Visible);

    x1:=TabLeft;
    w1:=bmp.Canvas.TextWidth(Caption1)+2*TabPadding;
    x2:=x1+w1+6;
    w2:=bmp.Canvas.TextWidth(Caption2)+2*TabPadding;

    if(TabsPnl.Height<>h)then
      TabsPnl.Height:=h;

    bmp.SetSize(w, h);

    PaintStrip(1, TabsImg);
    if(TwoTabs)then
      PaintStrip(2, Tabs2Img)
    else
      PaintStrip(1, Tabs2Img);

    PBox1.SetBounds(x1+TabPadding, 2+(base-2-th) div 2+1, w1-2*TabPadding+2, th);
    if(PBox2<>nil)then
      PBox2.SetBounds(x2+TabPadding+2, PBox1.Top, w2-2*TabPadding+2, th);

    OptionsImg.SetBounds(w-OptionsImg.Width-1, Max(1, (base-OptionsImg.Height) div 2),
      OptionsImg.Width, OptionsImg.Height);
  finally
    bmp.Free;
    InLayout:=False;
  end;
end;

end.
