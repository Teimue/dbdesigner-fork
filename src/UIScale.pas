unit UIScale;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit UIScale.pas
// ----------------
// Description
//   High DPI displays: the program is laid out in the pixels of a display of
//   96 DPI and its symbols are bitmaps of 16 pixels. The manifest declares
//   it DPI aware, so it has to scale itself:
//
//   - the dialogs follow the application font (TDMMain.FitFormLayout), which
//     is larger by the DPI already,
//   - the main window, the palettes and the query editor are scaled by the
//     DPI of the display,
//   - the bitmaps of the buttons, images and image lists of every form are
//     enlarged by the DPI of the display (ScaleFormGraphics).
//
//   Displays with different DPI (the manifest says "per monitor"): a form is
//   laid out for the DPI of the primary display (UIDPI) when it is created.
//   The LCL scales its bounds and fonts when it comes to a display with
//   another DPI (TCustomForm.Scaled, switched on by TDMMain.FitFormLayout);
//   RescaleFormGraphics does the same for the bitmaps. Everything that lives
//   in the main window follows the DPI of the main window (CurrentDPI).
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, Controls, Graphics, Forms, ImgList;

const
  //The DPI the forms and bitmaps are made for
  DesignDPI = 96;

//The DPI of the primary display: a form is laid out for it when it is
//created
function UIDPI: integer;

//A number of pixels of the design in the pixels of the primary display
function ScaleDPI(Value: integer): integer;
//... and back: sizes are stored in the settings in the pixels of the design
function UnscaleDPI(Value: integer): integer;

//The DPI of the display the main window is on, for everything that lives
//in the main window (the palettes, the query editor, the model)
function CurrentDPI: integer;
function ScaleCur(Value: integer): integer;
function UnscaleCur(Value: integer): integer;

//The DPI a form is scaled to
function FormDPI(theForm: TCustomForm): integer;

//A font of that many points on a display of that DPI
procedure SetFontPoints(theFont: TFont; Points, DPI: integer);

//An enlarged copy of a bitmap. The colour of the pixel at the bottom left
//stands for transparent pixels when Transparent is set, as the LCL takes it
//for the glyph of a button; the copy keeps that colour and hard edges. Cells
//is the number of pictures the bitmap holds side by side (NumGlyphs).
function ScaledBitmap(Src: TCustomBitmap; Cells: integer; Transparent: Boolean;
  Mul, Divisor: integer): TBitmap;

//Enlarge the glyphs, images and image lists of a form by the DPI of the
//primary display. Once per form
procedure ScaleFormGraphics(theForm: TCustomForm);

//... and to another DPI later. The bitmaps of the design are kept, a bitmap
//that the program has changed since is scaled from what it is now
procedure RescaleFormGraphics(theForm: TCustomForm; DPI: integer);

implementation

uses Buttons, ExtCtrls, ComCtrls, IntfGraphics, GraphType, FPimage, LCLType,
  Contnrs, crc;

const
  GraphicsDoneName = 'DBDGraphicsDone';

type
  //A bitmap of a form as it was designed (or last set by the program)
  TGraphicItem = class
    Comp: TComponent;
    Orig: TBitmap;
    OrigDPI: integer;
    Hash: Cardinal;       //of the bitmap that was made from Orig
    constructor Create;
    destructor Destroy; override;
  end;

  TImageListItem = class
    List: TCustomImageList;
    Origs: TObjectList;   //the pictures in the size of the design
    OrigW, OrigH: integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TGraphicsHolder = class(TComponent)
  public
    Items, Lists: TObjectList;
    DPI: integer;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

constructor TGraphicItem.Create;
begin
  Orig:=TBitmap.Create;
end;

destructor TGraphicItem.Destroy;
begin
  Orig.Free;
  inherited;
end;

constructor TImageListItem.Create;
begin
  Origs:=TObjectList.Create(True);
end;

destructor TImageListItem.Destroy;
begin
  Origs.Free;
  inherited;
end;

constructor TGraphicsHolder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Items:=TObjectList.Create(True);
  Lists:=TObjectList.Create(True);
  DPI:=DesignDPI;
end;

destructor TGraphicsHolder.Destroy;
begin
  Items.Free;
  Lists.Free;
  inherited;
end;

function UIDPI: integer;
begin
  Result:=Screen.PixelsPerInch;
  if(Result<DesignDPI)then
    Result:=DesignDPI;
end;

function ScaleDPI(Value: integer): integer;
begin
  Result:=MulDiv(Value, UIDPI, DesignDPI);
end;

function UnscaleDPI(Value: integer): integer;
begin
  Result:=MulDiv(Value, DesignDPI, UIDPI);
end;

function FormDPI(theForm: TCustomForm): integer;
begin
  if(theForm<>nil)and(theForm.FindComponent('DBDLayoutDone')<>nil)and
    (TCustomDesignControl(theForm).Scaled)then
    Result:=TCustomDesignControl(theForm).PixelsPerInch
  else
    Result:=UIDPI;
end;

function CurrentDPI: integer;
begin
  Result:=FormDPI(Application.MainForm);
end;

function ScaleCur(Value: integer): integer;
begin
  Result:=MulDiv(Value, CurrentDPI, DesignDPI);
end;

function UnscaleCur(Value: integer): integer;
begin
  Result:=MulDiv(Value, DesignDPI, CurrentDPI);
end;

procedure SetFontPoints(theFont: TFont; Points, DPI: integer);
begin
  theFont.PixelsPerInch:=DPI;
  theFont.Size:=Points;
end;

function ScaledBitmap(Src: TCustomBitmap; Cells: integer; Transparent: Boolean;
  Mul, Divisor: integer): TBitmap;
var SrcImg, DstImg: TLazIntfImage;
  Desc: TRawImageDescription;
  sw, sh, dw, dh, c, x, y, i: integer;
  x0, y0, x1, y1: integer;
  fx, fy, wx, wy, w, a, sumA, r, g, b: double;
  TC, col: TFPColor;
  HasAlpha: Boolean;

  function IsTransparent(const p: TFPColor): Boolean;
  begin
    if(HasAlpha)then
      Result:=(p.alpha<$8000)
    else
      Result:=Transparent and(p.red=TC.red)and(p.green=TC.green)and(p.blue=TC.blue);
  end;

begin
  Result:=TBitmap.Create;
  if(Cells<1)then
    Cells:=1;

  sw:=Src.Width div Cells;
  sh:=Src.Height;
  if(sw<1)or(sh<1)then
  begin
    Result.Assign(Src);
    Exit;
  end;
  dw:=MulDiv(sw, Mul, Divisor);
  dh:=MulDiv(sh, Mul, Divisor);

  SrcImg:=Src.CreateIntfImage;
  DstImg:=TLazIntfImage.Create(0, 0);
  try
    TC:=SrcImg.Colors[0, sh-1];

    //A bitmap with an alpha channel that is used
    HasAlpha:=False;
    if(SrcImg.DataDescription.AlphaPrec>0)then
      for y:=0 to sh-1 do
        for x:=0 to Src.Width-1 do
          if(SrcImg.Colors[x, y].alpha<>0)then
            HasAlpha:=True;
    if(HasAlpha)then
    begin
      TC.red:=$FFFF; TC.green:=0; TC.blue:=$FFFF;
      Transparent:=True;
    end;
    TC.alpha:=$FFFF;

    Desc.Init_BPP24_B8G8R8_BIO_TTB(dw*Cells, dh);
    DstImg.DataDescription:=Desc;

    for c:=0 to Cells-1 do
      for y:=0 to dh-1 do
      begin
        fy:=(y+0.5)*sh/dh-0.5;
        if(fy<0)then fy:=0;
        if(fy>sh-1)then fy:=sh-1;
        y0:=Trunc(fy);
        y1:=y0+1;
        if(y1>sh-1)then y1:=sh-1;
        wy:=fy-y0;

        for x:=0 to dw-1 do
        begin
          fx:=(x+0.5)*sw/dw-0.5;
          if(fx<0)then fx:=0;
          if(fx>sw-1)then fx:=sw-1;
          x0:=Trunc(fx);
          x1:=x0+1;
          if(x1>sw-1)then x1:=sw-1;
          wx:=fx-x0;

          sumA:=0; r:=0; g:=0; b:=0;
          for i:=0 to 3 do
          begin
            case i of
              0: begin col:=SrcImg.Colors[c*sw+x0, y0]; w:=(1-wx)*(1-wy); end;
              1: begin col:=SrcImg.Colors[c*sw+x1, y0]; w:=wx*(1-wy); end;
              2: begin col:=SrcImg.Colors[c*sw+x0, y1]; w:=(1-wx)*wy; end;
            else
              begin col:=SrcImg.Colors[c*sw+x1, y1]; w:=wx*wy; end;
            end;

            if(IsTransparent(col))then
              a:=0
            else
              a:=1;
            sumA:=sumA+w*a;
            r:=r+w*a*col.red;
            g:=g+w*a*col.green;
            b:=b+w*a*col.blue;
          end;

          if(sumA<0.5)then
            col:=TC
          else
          begin
            col.red:=Round(r/sumA);
            col.green:=Round(g/sumA);
            col.blue:=Round(b/sumA);
            col.alpha:=$FFFF;
          end;
          DstImg.Colors[c*dw+x, y]:=col;
        end;
      end;

    Result.LoadFromIntfImage(DstImg);
    if(Transparent)then
    begin
      Result.TransparentMode:=tmFixed;
      Result.TransparentColor:=FPColorToTColor(TC);
      Result.Transparent:=True;
    end;
  finally
    SrcImg.Free;
    DstImg.Free;
  end;
end;

function BitmapHash(bmp: TCustomBitmap): Cardinal;
var ms: TMemoryStream;
begin
  Result:=0;
  if(bmp=nil)or(bmp.Empty)then
    Exit;
  ms:=TMemoryStream.Create;
  try
    bmp.SaveToStream(ms);
    Result:=crc32(0, ms.Memory, ms.Size);
    if(Result=0)then
      Result:=1;
  finally
    ms.Free;
  end;
end;

//The bitmap of a button or an image, nil when it has none that is scaled
function ComponentBitmap(C: TComponent; out Cells: integer; out Transp: Boolean): TCustomBitmap;
begin
  Result:=nil;
  Cells:=1;
  Transp:=True;
  if(C is TCustomSpeedButton)then
  begin
    Result:=TSpeedButton(C).Glyph;
    Cells:=TSpeedButton(C).NumGlyphs;
  end
  else if(C is TCustomBitBtn)then
  begin
    Result:=TBitBtn(C).Glyph;
    Cells:=TBitBtn(C).NumGlyphs;
  end
  else if(C is TImage)then
  begin
    if(Not(TImage(C).Stretch))and(TImage(C).Picture.Graphic is TCustomBitmap)then
      Result:=TCustomBitmap(TImage(C).Picture.Graphic);
    Transp:=TImage(C).Transparent;
  end;

  if(Result<>nil)and(Result.Empty)then
    Result:=nil;
end;

procedure SetComponentBitmap(C: TComponent; bmp: TBitmap);
begin
  if(C is TCustomSpeedButton)then
    TSpeedButton(C).Glyph.Assign(bmp)
  else if(C is TCustomBitBtn)then
    TBitBtn(C).Glyph.Assign(bmp)
  else if(C is TImage)then
    TImage(C).Picture.Bitmap.Assign(bmp);
end;

procedure ApplyImageList(Item: TImageListItem; DPI: integer);
var Tmp: TImageList;
  Res: TCustomImageListResolution;
  Bmps: TObjectList;
  bmp: TBitmap;
  i, NewW, NewH: integer;
begin
  NewW:=MulDiv(Item.OrigW, DPI, DesignDPI);
  NewH:=MulDiv(Item.OrigH, DPI, DesignDPI);
  if(Item.List.Width=NewW)and(Item.List.Height=NewH)then
    Exit;

  Bmps:=TObjectList.Create(True);
  Tmp:=TImageList.Create(nil);
  try
    Tmp.Width:=Item.OrigW;
    Tmp.Height:=Item.OrigH;
    for i:=0 to Item.Origs.Count-1 do
      Tmp.Add(TBitmap(Item.Origs[i]), nil);

    //The list makes the pictures of another width itself
    if(NewW=Item.OrigW)then
      Res:=Tmp.ResolutionByIndex[0]
    else
      Res:=Tmp.Resolution[NewW];
    for i:=0 to Tmp.Count-1 do
    begin
      bmp:=TBitmap.Create;
      Res.GetBitmap(i, bmp);
      Bmps.Add(bmp);
    end;

    //clears the list
    Item.List.Width:=NewW;
    Item.List.Height:=NewH;
    for i:=0 to Bmps.Count-1 do
      Item.List.Add(TBitmap(Bmps[i]), nil);
  finally
    Tmp.Free;
    Bmps.Free;
  end;
end;

function GraphicsHolder(theForm: TCustomForm): TGraphicsHolder;
var i, k, Cells: integer;
  Transp: Boolean;
  C: TComponent;
  bmp: TCustomBitmap;
  Item: TGraphicItem;
  LItem: TImageListItem;
  b: TBitmap;
begin
  Result:=TGraphicsHolder(theForm.FindComponent(GraphicsDoneName));
  if(Result<>nil)then
    Exit;

  //The bitmaps of the design
  Result:=TGraphicsHolder.Create(theForm);
  Result.Name:=GraphicsDoneName;

  for i:=0 to theForm.ComponentCount-1 do
  begin
    C:=theForm.Components[i];
    if(C is TCustomImageList)then
    begin
      if(TCustomImageList(C).Count=0)then
        continue;
      LItem:=TImageListItem.Create;
      LItem.List:=TCustomImageList(C);
      LItem.OrigW:=LItem.List.Width;
      LItem.OrigH:=LItem.List.Height;
      for k:=0 to LItem.List.Count-1 do
      begin
        b:=TBitmap.Create;
        LItem.List.GetBitmap(k, b);
        LItem.Origs.Add(b);
      end;
      Result.Lists.Add(LItem);
    end
    else
    begin
      bmp:=ComponentBitmap(C, Cells, Transp);
      if(bmp=nil)then
        continue;
      Item:=TGraphicItem.Create;
      Item.Comp:=C;
      Item.Orig.Assign(bmp);
      Item.OrigDPI:=DesignDPI;
      Item.Hash:=0;
      Result.Items.Add(Item);
    end;
  end;
end;

procedure RescaleFormGraphics(theForm: TCustomForm; DPI: integer);
var Holder: TGraphicsHolder;
  i, Cells: integer;
  Transp: Boolean;
  Item: TGraphicItem;
  bmp: TCustomBitmap;
  NewBmp: TBitmap;
begin
  if(DPI<DesignDPI)then
    DPI:=DesignDPI;

  Holder:=GraphicsHolder(theForm);
  if(Holder.DPI=DPI)then
    Exit;

  for i:=0 to Holder.Items.Count-1 do
  begin
    Item:=TGraphicItem(Holder.Items[i]);
    bmp:=ComponentBitmap(Item.Comp, Cells, Transp);
    if(bmp=nil)then
      continue;

    //The program has given the component another bitmap: that is the one
    //to scale from now on
    if(Item.Hash<>0)and(BitmapHash(bmp)<>Item.Hash)then
    begin
      Item.Orig.Assign(bmp);
      Item.OrigDPI:=Holder.DPI;
    end;

    if(DPI=Item.OrigDPI)then
      SetComponentBitmap(Item.Comp, Item.Orig)
    else
    begin
      NewBmp:=ScaledBitmap(Item.Orig, Cells, Transp, DPI, Item.OrigDPI);
      try
        SetComponentBitmap(Item.Comp, NewBmp);
      finally
        NewBmp.Free;
      end;
    end;

    bmp:=ComponentBitmap(Item.Comp, Cells, Transp);
    Item.Hash:=BitmapHash(bmp);
  end;

  for i:=0 to Holder.Lists.Count-1 do
    ApplyImageList(TImageListItem(Holder.Lists[i]), DPI);

  Holder.DPI:=DPI;

  //A row of a tree is as high as its pictures at least
  for i:=0 to theForm.ComponentCount-1 do
    if(theForm.Components[i] is TTreeView)then
      with TTreeView(theForm.Components[i]) do
        if(Images<>nil)then
          if(DefaultItemHeight<Images.Height+2)then
            DefaultItemHeight:=Images.Height+2;
end;

procedure ScaleFormGraphics(theForm: TCustomForm);
begin
  RescaleFormGraphics(theForm, UIDPI);
end;

end.
