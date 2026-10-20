program TestSQLExport;
{$I DBDesigner4.inc}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // LCL
  Classes, SysUtils, Forms, Controls, Graphics,
  MainDM, EERModel, EERDM, LibXmlParser;

var
  Model: TEERModel;
  i: Integer;
  Table: TEERTable;
  SQL: string;
  ModelFile: string;
  ParentForm: TForm;
begin
  Application.Initialize;
  //A test must leave the settings of the user alone: without this the data
  //modules rewrite DBConn.ini (with no connections) and leave a
  //<TestName>_Settings.ini in the settings directory when they are freed
  SettingsReadOnly:=True;

  WriteLn('=== SQL Export Test ===');
  WriteLn;

  ModelFile := 'bin/Examples/order.xml';
  if not FileExists(ModelFile) then
  begin
    WriteLn('ERROR: Model file not found: ', ModelFile);
    Halt(1);
  end;

  // Create a parent form (TEERModel inherits from TPanel, needs a parent)
  ParentForm := TForm.Create(nil);
  try
    // TEERModel.Create reads the translations and the display settings
    DMMain := TDMMain.Create(ParentForm);
    DMEER := TDMEER.Create(ParentForm);

    Model := TEERModel.Create(ParentForm);
    Model.Parent := ParentForm;

    WriteLn('Loading model: ', ModelFile);
    try
      Model.LoadFromFile(ModelFile);
    except
      on E: Exception do
      begin
        WriteLn('Load error: ', E.ClassName, ': ', E.Message);
        Halt(1);
      end;
    end;
    WriteLn('Components: ', Model.ComponentCount);
    WriteLn;

    // Iterate through components to find tables
    for i := 0 to Model.ComponentCount - 1 do
    begin
      if Model.Components[i] is TEERTable then
      begin
        Table := TEERTable(Model.Components[i]);
        WriteLn('--- ', Table.ObjName, ' ---');
        try
          // params: DefinePK, DefineIndices, HideNullField, DefaultBeforeNotNull, DatabaseType, OutputComments
          SQL := Table.GetSQLCreateCode(True, True, False, True, False, True);
          WriteLn(SQL);
        except
          on E: Exception do
            WriteLn('  SQL ERROR: ', E.ClassName, ': ', E.Message);
        end;
      end;
    end;

    WriteLn;
    WriteLn('SUCCESS: SQL export test complete');
  finally
    ParentForm.Free;
  end;
end.
