unit Splash;

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

// You should have received a copy of the GNU General Public License
// along with DBDesigner4; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//----------------------------------------------------------------------------------------------------------------------
//
// Unit Splash.pas
// ---------------
// Version Fork 1.5, 13.10.2010, JP
// Version 1.0, 13.013.2003, Mike
// Description
//   Contains the splash form class
//
// Changes:
//   Version 1.1, 13.03.2003, Mike
//     initial version
// Version Fork 1.5, 13.10.2010, JP: changes in the splash screen.
//
//----------------------------------------------------------------------------------------------------------------------


{$I DBDesigner4.inc}

interface

uses
  SysUtils, Types, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, Buttons, LCLType;

type
  TSplashForm = class(TForm)
    CloseTimer: TTimer;
    InfoLbl1: TLabel;
    VersionLbl: TLabel;
    InfoLbl5: TLabel;
    InfoLbl2: TLabel;
    InfoLbl4: TLabel;
    InfoLbl3: TLabel;
    InfoLbl6: TLabel;
    InfoLbl7: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure OKSBtnClick(Sender: TObject);
    procedure AbortSBtnClick(Sender: TObject);
    procedure CloseTimerTimer(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormPaint(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormClick(Sender: TObject);
  private
    { Private declarations }
    SplashImg: TPicture;
  public
    { Public declarations }
    //Close the start picture after it was shown for that long
    procedure CloseAfter(Milliseconds: integer);
  end;

var
  SplashForm: TSplashForm;

implementation

uses Main, UIScale;

{$R *.lfm}

procedure TSplashForm.FormCreate(Sender: TObject);
begin
  {$IFDEF LINUX}
  Font.Name:='Nimbus Sans L';
  Font.Size:=10;
  {$ENDIF}

  //started by CloseAfter
  CloseTimer.Enabled:=False;

  //The picture is a PNG file. Without it the window stays grey
  SplashImg:=TPicture.Create;
  try
    SplashImg.LoadFromFile(ExtractFilePath(Application.ExeName)+
      'Gfx'+PathDelim+'splashscreen.png');
  except
  end;

  //In the size of the picture, in the scale of the display. The window has
  //no border; ClientWidth is not reliable before the form has a handle
  if(SplashImg.Width>0)then
  begin
    Width:=ScaleDPI(SplashImg.Width);
    Height:=ScaleDPI(SplashImg.Height);
  end
  else
  begin
    Width:=ScaleDPI(697);
    Height:=ScaleDPI(358);
  end;

  Position:=poScreenCenter;
end;

procedure TSplashForm.CloseAfter(Milliseconds: integer);
begin
  if(Milliseconds<=0)then
    Close
  else
  begin
    CloseTimer.Interval:=Milliseconds;
    CloseTimer.Enabled:=True;
  end;
end;

procedure TSplashForm.FormDestroy(Sender: TObject);
begin
  SplashImg.Free;

  if(SplashForm=self)then
    SplashForm:=nil;
end;

procedure TSplashForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action:=caFree;
end;

procedure TSplashForm.OKSBtnClick(Sender: TObject);
begin
  ModalResult:=mrOK;
end;

procedure TSplashForm.AbortSBtnClick(Sender: TObject);
begin
  ModalResult:=mrAbort;
end;

procedure TSplashForm.CloseTimerTimer(Sender: TObject);
begin
  CloseTimer.Enabled:=False;
  Close;
end;

procedure TSplashForm.FormPaint(Sender: TObject);
var i: integer;
  theLbl: TLabel;
begin
  if(Assigned(SplashImg))then
  begin
    if(SplashImg.Graphic<>nil)and(Not(SplashImg.Graphic.Empty))then
    begin
      Canvas.AntialiasingMode:=amOn;
      Canvas.StretchDraw(ClientRect, SplashImg.Graphic);
    end;

{$IFDEF LINUX}
    Canvas.Font.Name:='Nimbus Sans L';
{$ELSE}
    Canvas.Font.Name:='Microsoft Sans Serif';
{$ENDIF}
    Canvas.Font.Height:=ScaleDPI(13);
    //on the dark band at the bottom of the picture
    Canvas.Font.Color:=clWhite;
    Canvas.Brush.Style:=bsClear;

//    for i:=1 to 7 do
//    begin
//      theLbl:=TLabel(FindComponent('InfoLbl'+IntToStr(i)));
//      if(theLbl<>nil)then
//      begin
//        Canvas.TextOut(theLbl.Left, theLbl.Top, theLbl.Caption);
//      end;
//    end;

    Canvas.TextOut(ClientWidth-ScaleDPI(14)-Canvas.TextWidth(VersionLbl.Caption),
      ScaleDPI(318), VersionLbl.Caption);
  end;
end;

procedure TSplashForm.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ModalResult:=mrAbort;
end;

procedure TSplashForm.FormClick(Sender: TObject);
begin
  Close;
end;

end.
