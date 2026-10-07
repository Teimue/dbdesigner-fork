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
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, Controls, Graphics, Forms, ImgList;

const
  //The DPI the forms and bitmaps are made for
  DesignDPI = 96;

//The DPI of the display the program scales itself to
function UIDPI: integer;

//A number of pixels of the design in the pixels of the display
function ScaleDPI(Value: integer): integer;
//... and back: sizes are stored in the settings in the pixels of the design
function UnscaleDPI(Value: integer): integer;

//An enlarged copy of a bitmap. The colour of the pixel at the bottom left
//stands for transparent pixels when Transparent is set, as the LCL takes it
//for the glyph of a button; the copy keeps that colour and hard edges. Cells
//is the number of pictures the bitmap holds side by side (NumGlyphs).
function ScaledBitmap(Src: TCustomBitmap; Cells: integer; Transparent: Boolean;
  Mul, Divisor: integer): TBitmap;

//Enlarge the glyphs, images and image lists of a form by the DPI of the
//display. Once per form
procedure ScaleFormGraphics(theForm: TCustomForm);

procedure ScaleImageList(theList: TCustomImageList; Mul, Divisor: integer);

implementation

uses Buttons, ExtCtrls, ComCtrls, IntfGraphics, GraphType, FPimage, LCLType;

const
  GraphicsDoneName = 'DBDGraphicsDone';

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

procedure ScaleImageList(theList: TCustomImageList; Mul, Divisor: integer);
var Bmps: TList;
  bmp: TBitmap;
  i, NewW, NewH: integer;
  Res: TCustomImageListResolution;
begin
  if(theList.Count=0)or(Mul=Divisor)then
    Exit;

  NewW:=MulDiv(theList.Width, Mul, Divisor);
  NewH:=MulDiv(theList.Height, Mul, Divisor);

  Bmps:=TList.Create;
  try
    //The list makes the pictures of another width itself
    Res:=theList.ResolutionByIndex[theList.ResolutionCount-1];
    if(Res.Width<>NewW)then
      Res:=theList.Resolution[NewW];
    for i:=0 to theList.Count-1 do
    begin
      bmp:=TBitmap.Create;
      Res.GetBitmap(i, bmp);
      Bmps.Add(bmp);
    end;

    //clears the list
    theList.Width:=NewW;
    theList.Height:=NewH;
    for i:=0 to Bmps.Count-1 do
      theList.Add(TBitmap(Bmps[i]), nil);
  finally
    for i:=0 to Bmps.Count-1 do
      TBitmap(Bmps[i]).Free;
    Bmps.Free;
  end;
end;

procedure ScaleFormGraphics(theForm: TCustomForm);
var i, Mul: integer;
  Marker, C: TComponent;
  bmp: TBitmap;
begin
  Mul:=UIDPI;
  if(Mul=DesignDPI)or(theForm.FindComponent(GraphicsDoneName)<>nil)then
    Exit;

  Marker:=TComponent.Create(theForm);
  Marker.Name:=GraphicsDoneName;

  for i:=0 to theForm.ComponentCount-1 do
  begin
    C:=theForm.Components[i];
    bmp:=nil;
    try
      if(C is TCustomSpeedButton)then
      begin
        with TSpeedButton(C) do
          if(Not(Glyph.Empty))then
          begin
            bmp:=ScaledBitmap(Glyph, NumGlyphs, True, Mul, DesignDPI);
            Glyph.Assign(bmp);
          end;
      end
      else if(C is TCustomBitBtn)then
      begin
        with TBitBtn(C) do
          if(Not(Glyph.Empty))then
          begin
            bmp:=ScaledBitmap(Glyph, NumGlyphs, True, Mul, DesignDPI);
            Glyph.Assign(bmp);
          end;
      end
      else if(C is TImage)then
      begin
        with TImage(C) do
          if(Not(Stretch))and(Picture.Graphic is TCustomBitmap)and
            (Not(Picture.Graphic.Empty))then
          begin
            bmp:=ScaledBitmap(TCustomBitmap(Picture.Graphic), 1, Transparent,
              Mul, DesignDPI);
            Picture.Bitmap.Assign(bmp);
          end;
      end
      else if(C is TCustomImageList)then
        ScaleImageList(TCustomImageList(C), Mul, DesignDPI);
    finally
      bmp.Free;
    end;
  end;

  //A row of a tree is as high as its pictures at least
  for i:=0 to theForm.ComponentCount-1 do
    if(theForm.Components[i] is TTreeView)then
      with TTreeView(theForm.Components[i]) do
        if(Images<>nil)then
          if(DefaultItemHeight<Images.Height+2)then
            DefaultItemHeight:=Images.Height+2;
end;

end.
