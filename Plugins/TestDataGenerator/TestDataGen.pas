unit TestDataGen;

//----------------------------------------------------------------------------------------------------------------------
//
// This file is part of DBDesigner Fork which is forked from DBDesigner 4.
//
// Unit TestDataGen.pas
// --------------------
// Description
//   Generates test data for the tables of a model as a script of INSERT
//   statements:
//
//   - the tables are filled in the order of their foreign keys, a foreign
//     key column takes the values of a row that was generated for the
//     referenced table,
//   - primary keys and the columns of unique indices get unique values,
//   - the other values follow the datatype (length, precision, the values of
//     an ENUM) and the name of the column (name, street, city, e-mail ...),
//   - the same seed gives the same data.
//
//   The unit has no user interface, see Main.pas of the plugin and
//   tests/TestTestDataGen.pas.
//
//----------------------------------------------------------------------------------------------------------------------

{$I DBDesigner4.inc}

interface

uses Classes, SysUtils, EERModel;

type
  TTestDataOptions = record
    TargetDB: string;      //one of TestDataTargets
    DefaultRows: integer;  //rows of a table that is not in RowCounts
    Seed: LongWord;
    NullPercent: integer;  //share of NULL in the columns that allow it
    German: Boolean;       //German names, cities ... instead of English ones
    DeleteFirst: Boolean;  //DELETE FROM the tables before the inserts
    SkipAutoInc: Boolean;  //leave the auto increment columns to the database
    Commit: Boolean;       //COMMIT at the end
  end;

function DefaultTestDataOptions: TTestDataOptions;

//The database types a script can be made for
procedure TestDataTargets(List: TStrings);
//The entry of TestDataTargets for the database type of a model
function TargetDBOfModel(Model: TEERModel): string;

//Does the table exist in the database? A table of a linked model does only
//when the model creates SQL code for linked objects
function TableHasSQL(Model: TEERModel; T: TEERTable): Boolean;

//Tables: the TEERTable objects to fill. RowCounts: <table name>=<rows> for
//the tables that do not get Opt.DefaultRows (may be nil).
//Returns the number of INSERT statements
function GenerateTestData(Model: TEERModel; Tables: TList; RowCounts: TStrings;
  const Opt: TTestDataOptions; Output: TStrings): integer;

implementation

uses Math, StrUtils, LazUTF8, EERDM;

const
  FirstNamesDE: array[0..23] of string = ('Anna', 'Lukas', 'Marie', 'Jonas',
    'Lena', 'Felix', 'Sophie', 'Paul', 'Laura', 'Maximilian', 'Julia', 'Tim',
    'Katharina', 'Jan', 'Sabine', 'Stefan', 'Petra', 'Jürgen', 'Monika',
    'Günter', 'Heike', 'Björn', 'Käthe', 'Sören');
  LastNamesDE: array[0..23] of string = ('Müller', 'Schmidt', 'Schneider',
    'Fischer', 'Weber', 'Meyer', 'Wagner', 'Becker', 'Schulz', 'Hoffmann',
    'Schäfer', 'Koch', 'Bauer', 'Richter', 'Klein', 'Wolf', 'Schröder',
    'Neumann', 'Schwarz', 'Zimmermann', 'Braun', 'Krüger', 'Hartmann', 'Köhler');
  StreetsDE: array[0..15] of string = ('Hauptstraße', 'Bahnhofstraße',
    'Gartenstraße', 'Schulstraße', 'Dorfstraße', 'Bergstraße', 'Lindenweg',
    'Kirchplatz', 'Mühlenweg', 'Am Markt', 'Goethestraße', 'Schillerstraße',
    'Rosenweg', 'Industriestraße', 'Feldweg', 'Ringstraße');
  CitiesDE: array[0..19] of string = ('Berlin', 'Hamburg', 'München', 'Köln',
    'Frankfurt am Main', 'Stuttgart', 'Düsseldorf', 'Leipzig', 'Dortmund',
    'Essen', 'Bremen', 'Dresden', 'Hannover', 'Nürnberg', 'Erfurt', 'Jena',
    'Weimar', 'Würzburg', 'Lübeck', 'Rostock');
  CountriesDE: array[0..9] of string = ('Deutschland', 'Österreich', 'Schweiz',
    'Frankreich', 'Niederlande', 'Belgien', 'Dänemark', 'Polen', 'Italien',
    'Spanien');
  CompaniesDE: array[0..11] of string = ('Müller GmbH', 'Schmidt & Söhne KG',
    'Nordbau AG', 'Hansa Logistik GmbH', 'Bergmann Technik', 'Rheinwerk AG',
    'Sonnenhof eG', 'Elbe Software GmbH', 'Weber Maschinenbau',
    'Köhler Elektro GmbH', 'Alpen Handel KG', 'Baustoffe Neumann');
  ColorsDE: array[0..9] of string = ('Rot', 'Grün', 'Blau', 'Gelb', 'Schwarz',
    'Weiß', 'Grau', 'Orange', 'Violett', 'Braun');
  WordsDE: array[0..31] of string = ('Projekt', 'Auftrag', 'Lieferung',
    'Rechnung', 'Angebot', 'Kunde', 'Standard', 'Muster', 'Prüfung', 'Lager',
    'Bestand', 'Planung', 'Material', 'Leistung', 'Position', 'Ausführung',
    'Gruppe', 'Bereich', 'Vorgang', 'Bericht', 'Übersicht', 'Abschnitt',
    'Bauteil', 'Menge', 'Kosten', 'Termin', 'Änderung', 'Freigabe', 'Vertrag',
    'Nachweis', 'Montage', 'Wartung');

  FirstNamesEN: array[0..23] of string = ('James', 'Mary', 'John', 'Linda',
    'Robert', 'Susan', 'Michael', 'Karen', 'David', 'Emma', 'Daniel', 'Olivia',
    'Thomas', 'Sarah', 'Peter', 'Laura', 'George', 'Alice', 'Henry', 'Grace',
    'Oliver', 'Emily', 'Jack', 'Sophie');
  LastNamesEN: array[0..23] of string = ('Smith', 'Johnson', 'Brown', 'Taylor',
    'Miller', 'Wilson', 'Moore', 'Anderson', 'Clark', 'Walker', 'Hall', 'Young',
    'King', 'Wright', 'Scott', 'Green', 'Baker', 'Adams', 'Nelson', 'Carter',
    'Mitchell', 'Turner', 'Parker', 'Evans');
  StreetsEN: array[0..15] of string = ('Main Street', 'High Street',
    'Church Road', 'Park Avenue', 'Station Road', 'Mill Lane', 'Oak Street',
    'Maple Avenue', 'Victoria Road', 'King Street', 'Queen Street',
    'Elm Street', 'Bridge Road', 'Market Square', 'Hill Road', 'Green Lane');
  CitiesEN: array[0..19] of string = ('London', 'New York', 'Chicago',
    'Boston', 'Seattle', 'Dublin', 'Manchester', 'Toronto', 'Sydney', 'Denver',
    'Austin', 'Portland', 'Glasgow', 'Bristol', 'Leeds', 'Ottawa', 'Atlanta',
    'Phoenix', 'Dallas', 'Oxford');
  CountriesEN: array[0..9] of string = ('United Kingdom', 'United States',
    'Canada', 'Ireland', 'Australia', 'Germany', 'France', 'Netherlands',
    'Sweden', 'New Zealand');
  CompaniesEN: array[0..11] of string = ('Miller Ltd', 'Northwind Inc',
    'Brown & Sons', 'Harbor Logistics', 'Summit Engineering', 'Riverside AG',
    'Oakfield Trading', 'Bluebird Software', 'Carter Machines',
    'Evans Electric', 'Highland Supplies', 'Parker Building Materials');
  ColorsEN: array[0..9] of string = ('Red', 'Green', 'Blue', 'Yellow', 'Black',
    'White', 'Grey', 'Orange', 'Purple', 'Brown');
  WordsEN: array[0..31] of string = ('Project', 'Order', 'Delivery',
    'Invoice', 'Offer', 'Customer', 'Standard', 'Sample', 'Review', 'Stock',
    'Inventory', 'Planning', 'Material', 'Service', 'Item', 'Version',
    'Group', 'Section', 'Process', 'Report', 'Overview', 'Chapter', 'Part',
    'Quantity', 'Cost', 'Schedule', 'Change', 'Release', 'Contract', 'Record',
    'Assembly', 'Maintenance');

type
  TStringRow = array of string;

  //The rows that were generated for a table: the SQL literal of every column
  TTableData = class
    Table: TEERTable;
    Rows: array of TStringRow;
    Done: Boolean;
    function ColumnIndex(const ColName: string): integer;
  end;

  //A small generator of its own: the same seed gives the same data, whatever
  //the run time library does with Random
  TRandom = class
    State: LongWord;
    function Next(Range: integer): integer;  //0..Range-1
    function Between(Lo, Hi: integer): integer;
    function Pick(const A: array of string): string;
  end;

function TTableData.ColumnIndex(const ColName: string): integer;
var i: integer;
begin
  Result:=-1;
  for i:=0 to Table.Columns.Count-1 do
    if(CompareText(TEERColumn(Table.Columns[i]).ColName, ColName)=0)then
    begin
      Result:=i;
      break;
    end;
end;

function TRandom.Next(Range: integer): integer;
begin
  //xorshift32
  State:=State xor (State shl 13);
  State:=State xor (State shr 17);
  State:=State xor (State shl 5);
  if(Range<=1)then
    Result:=0
  else
    Result:=integer((State shr 1) mod LongWord(Range));
end;

function TRandom.Between(Lo, Hi: integer): integer;
begin
  if(Hi<=Lo)then
    Result:=Lo
  else
    Result:=Lo+Next(Hi-Lo+1);
end;

function TRandom.Pick(const A: array of string): string;
begin
  Result:=A[Next(Length(A))];
end;

function DefaultTestDataOptions: TTestDataOptions;
begin
  Result.TargetDB:='My SQL';
  Result.DefaultRows:=10;
  Result.Seed:=1;
  Result.NullPercent:=10;
  Result.German:=False;
  Result.DeleteFirst:=False;
  Result.SkipAutoInc:=False;
  Result.Commit:=True;
end;

procedure TestDataTargets(List: TStrings);
begin
  List.Clear;
  List.Add('FireBird');
  List.Add('My SQL');
  List.Add('Oracle');
  List.Add('PostgreSQL');
  List.Add('SQL Server');
  List.Add('SQLite');
end;

function TargetDBOfModel(Model: TEERModel): string;
var s: string;
begin
  s:=UpperCase(Model.DatabaseType);
  if(Pos('FIREBIRD', s)>0)or(Pos('INTERBASE', s)>0)then
    Result:='FireBird'
  else if(Pos('ORACLE', s)>0)then
    Result:='Oracle'
  else if(Pos('POSTGRE', s)>0)then
    Result:='PostgreSQL'
  else if(Pos('MSSQL', s)>0)or(Pos('SQL SERVER', s)>0)then
    Result:='SQL Server'
  else if(Pos('SQLITE', s)>0)then
    Result:='SQLite'
  else
    Result:='My SQL';
end;

function TableHasSQL(Model: TEERModel; T: TEERTable): Boolean;
begin
  Result:=(Not(T.IsLinkedObject))or(Model.CreateSQLforLinkedObjects);
end;

function QuoteStr(const s: string): string;
begin
  Result:=''''+StringReplace(s, '''', '''''', [rfReplaceAll])+'''';
end;

//(10,2) -> 10 and 2; -1 when there is no such parameter
procedure ParseParams(const Params: string; out P1, P2: integer);
var s: string;
  k: integer;
begin
  P1:=-1;
  P2:=-1;
  s:=Trim(Params);
  if(Copy(s, 1, 1)='(')then
    Delete(s, 1, 1);
  if(Copy(s, Length(s), 1)=')')then
    Delete(s, Length(s), 1);
  k:=Pos(',', s);
  if(k>0)then
  begin
    P1:=StrToIntDef(Trim(Copy(s, 1, k-1)), -1);
    P2:=StrToIntDef(Trim(Copy(s, k+1, Length(s))), -1);
  end
  else
    P1:=StrToIntDef(Trim(s), -1);
end;

//('a','b''c') -> a and b'c
procedure ParseEnumValues(const Params: string; Values: TStrings);
var i: integer;
  InQuote: Boolean;
  cur: string;
begin
  Values.Clear;
  InQuote:=False;
  cur:='';
  i:=1;
  while(i<=Length(Params))do
  begin
    if(Params[i]='''')then
    begin
      if(InQuote)and(i<Length(Params))and(Params[i+1]='''')then
      begin
        cur:=cur+'''';
        inc(i);
      end
      else
      begin
        if(InQuote)then
          Values.Add(cur);
        cur:='';
        InQuote:=Not(InQuote);
      end;
    end
    else if(InQuote)then
      cur:=cur+Params[i];
    inc(i);
  end;
end;

function HasAny(const Name: string; const Parts: array of string): Boolean;
var i: integer;
begin
  Result:=False;
  for i:=0 to High(Parts) do
    if(Pos(Parts[i], Name)>0)then
    begin
      Result:=True;
      break;
    end;
end;

function GenerateTestData(Model: TEERModel; Tables: TList; RowCounts: TStrings;
  const Opt: TTestDataOptions; Output: TStrings): integer;
var
  Rnd: TRandom;
  Data: TList;         //TTableData in the order the tables are filled
  Statements: integer;

  function DataOf(T: TEERTable): TTableData;
  var i: integer;
  begin
    Result:=nil;
    for i:=0 to Data.Count-1 do
      if(TTableData(Data[i]).Table=T)then
      begin
        Result:=TTableData(Data[i]);
        break;
      end;
  end;

  function RowsFor(T: TEERTable): integer;
  begin
    Result:=Opt.DefaultRows;
    if(RowCounts<>nil)then
      if(RowCounts.IndexOfName(T.ObjName)>=0)then
        Result:=StrToIntDef(RowCounts.Values[T.ObjName], Opt.DefaultRows);
    if(Result<0)then
      Result:=0;
  end;

  function SQLName(T: TEERTable; const AName: string): string;
  begin
    if(Opt.TargetDB='FireBird')then
      Result:=T.GetSQLName(AName, 'FireBird')
    else if(Not(DMEER.EncloseNames))then
      Result:=AName
    else if(Opt.TargetDB='My SQL')then
      Result:='`'+AName+'`'
    else if(Opt.TargetDB='SQL Server')then
      Result:='['+AName+']'
    else
      Result:='"'+AName+'"';
  end;

  function SQLTableName(T: TEERTable): string;
  begin
    if(Opt.TargetDB='My SQL')then
      Result:=T.GetSQLTableName
    else
      Result:=SQLName(T, T.ObjName);
  end;

  function TypeNameOf(Col: TEERColumn): string;
  begin
    Result:=UpperCase(Trim(Model.GetDataTypeName(Col.idDatatype)));
  end;

  function IsIntType(const tn: string): Boolean;
  begin
    Result:=(Pos('INT', tn)>0)or(tn='SERIAL')or(tn='BIGSERIAL')or(tn='YEAR');
  end;

  function IsBoolType(const tn: string): Boolean;
  begin
    Result:=(tn='BOOL')or(tn='BOOLEAN')or(tn='BIT');
  end;

  function IsDecimalType(const tn: string): Boolean;
  begin
    Result:=(tn='DECIMAL')or(tn='NUMERIC')or(tn='DEC')or(tn='FIXED')or
      (tn='FLOAT')or(tn='REAL')or(Pos('DOUBLE', tn)>0)or(tn='NUMBER')or
      (Pos('MONEY', tn)>0);
  end;

  function IsStringType(const tn: string): Boolean;
  begin
    Result:=(Pos('CHAR', tn)>0)or(Pos('TEXT', tn)>0)or(Pos('CLOB', tn)>0);
  end;

  function DateLiteral(d: TDateTime): string;
  begin
    Result:=''''+FormatDateTime('yyyy"-"mm"-"dd', d)+'''';
    if(Opt.TargetDB='Oracle')then
      Result:='DATE '+Result;
  end;

  function DateTimeLiteral(d: TDateTime): string;
  begin
    Result:=''''+FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', d)+'''';
    if(Opt.TargetDB='Oracle')then
      Result:='TIMESTAMP '+Result;
  end;

  function RandomDate(const cn: string): TDateTime;
  begin
    if(HasAny(cn, ['geburt', 'birth', 'geb_dat', 'gebdat', 'dob']))then
      Result:=EncodeDate(1950, 1, 1)+Rnd.Next(20000)
    else
      Result:=EncodeDate(2015, 1, 1)+Rnd.Next(4000);
  end;

  function Words(Count: integer): string;
  var i: integer;
  begin
    Result:='';
    for i:=1 to Count do
    begin
      if(Result<>'')then
        Result:=Result+' ';
      if(Opt.German)then
        Result:=Result+Rnd.Pick(WordsDE)
      else
        Result:=Result+Rnd.Pick(WordsEN);
    end;
  end;

  function Digits(Count: integer): string;
  var i: integer;
  begin
    Result:='';
    for i:=1 to Count do
      Result:=Result+Chr(Ord('0')+Rnd.Next(10));
  end;

  function Letters(Count: integer): string;
  var i: integer;
  begin
    Result:='';
    for i:=1 to Count do
      Result:=Result+Chr(Ord('A')+Rnd.Next(26));
  end;

  function HexDigits(Count: integer): string;
  const Hex = '0123456789ABCDEF';
  var i: integer;
  begin
    Result:='';
    for i:=1 to Count do
      Result:=Result+Hex[1+Rnd.Next(16)];
  end;

  function AsciiLower(const s: string): string;
  begin
    Result:=LowerCase(s);
    Result:=StringReplace(Result, 'ä', 'ae', [rfReplaceAll]);
    Result:=StringReplace(Result, 'ö', 'oe', [rfReplaceAll]);
    Result:=StringReplace(Result, 'ü', 'ue', [rfReplaceAll]);
    Result:=StringReplace(Result, 'ß', 'ss', [rfReplaceAll]);
    Result:=StringReplace(Result, 'Ä', 'ae', [rfReplaceAll]);
    Result:=StringReplace(Result, 'Ö', 'oe', [rfReplaceAll]);
    Result:=StringReplace(Result, 'Ü', 'ue', [rfReplaceAll]);
    Result:=StringReplace(Result, ' ', '', [rfReplaceAll]);
  end;

  function FirstName: string;
  begin
    if(Opt.German)then Result:=Rnd.Pick(FirstNamesDE) else Result:=Rnd.Pick(FirstNamesEN);
  end;

  function LastName: string;
  begin
    if(Opt.German)then Result:=Rnd.Pick(LastNamesDE) else Result:=Rnd.Pick(LastNamesEN);
  end;

  //A text for a column by its name. MaxLen in characters. Unique: the text
  //must differ from row to row, RowNr goes into it
  function TextValue(const tblname, cn: string; MaxLen, RowNr: integer; Unique: Boolean): string;
  var s, nr: string;
  begin
    if(MaxLen<=0)then
      MaxLen:=255;

    if(HasAny(cn, ['guid', 'uuid']))then
    begin
      s:=HexDigits(8)+'-'+HexDigits(4)+'-'+HexDigits(4)+'-'+HexDigits(4)+'-'+HexDigits(12);
      if(MaxLen>=38)then
        s:='{'+s+'}'
      else if(MaxLen<36)then
        s:=StringReplace(s, '-', '', [rfReplaceAll]);
      Unique:=False;
    end
    else if(HasAny(cn, ['email', 'e_mail', 'mail']))then
      s:=AsciiLower(FirstName)+'.'+AsciiLower(LastName)+IfThen(Unique, IntToStr(RowNr), '')+
        '@example.com'
    else if(HasAny(cn, ['vorname', 'firstname', 'first_name', 'fname', 'givenname']))then
      s:=FirstName
    else if(HasAny(cn, ['nachname', 'lastname', 'last_name', 'surname', 'familienname', 'zuname']))then
      s:=LastName
    else if(HasAny(cn, ['strasse', 'straße', 'street', 'address', 'adresse', 'anschrift']))then
    begin
      if(Opt.German)then
        s:=Rnd.Pick(StreetsDE)+' '+IntToStr(Rnd.Between(1, 120))
      else
        s:=IntToStr(Rnd.Between(1, 120))+' '+Rnd.Pick(StreetsEN);
    end
    else if(HasAny(cn, ['plz', 'zip', 'postal', 'postcode']))then
      s:=Digits(5)
    else if(HasAny(cn, ['ort', 'stadt', 'city', 'town']))and(Not(HasAny(cn, ['sort', 'port', 'wort'])))then
    begin
      if(Opt.German)then s:=Rnd.Pick(CitiesDE) else s:=Rnd.Pick(CitiesEN);
    end
    else if(HasAny(cn, ['land', 'country', 'staat']))then
    begin
      if(Opt.German)then s:=Rnd.Pick(CountriesDE) else s:=Rnd.Pick(CountriesEN);
    end
    else if(HasAny(cn, ['telefon', 'phone', 'fax', 'mobil', 'handy']))or(cn='tel')then
    begin
      if(Opt.German)then
        s:='0'+Digits(3)+' '+Digits(7)
      else
        s:='+1 '+Digits(3)+' '+Digits(3)+' '+Digits(4);
    end
    else if(HasAny(cn, ['firma', 'company', 'unternehmen', 'hersteller', 'lieferant', 'supplier']))then
    begin
      if(Opt.German)then s:=Rnd.Pick(CompaniesDE) else s:=Rnd.Pick(CompaniesEN);
    end
    else if(HasAny(cn, ['url', 'homepage', 'website', 'link']))then
      s:='https://www.example.com/'+AsciiLower(Words(1))+IfThen(Unique, IntToStr(RowNr), '')
    else if(HasAny(cn, ['user', 'login', 'benutzer']))then
      s:=Copy(AsciiLower(FirstName), 1, 1)+AsciiLower(LastName)+IfThen(Unique, IntToStr(RowNr), '')
    else if(HasAny(cn, ['passw', 'pwd', 'kennwort']))then
      s:=HexDigits(12)
    else if(HasAny(cn, ['iban']))then
      s:='DE'+Digits(20)
    else if(HasAny(cn, ['ean', 'barcode', 'gtin']))and(Not(HasAny(cn, ['mean', 'clean', 'bean'])))then
      s:=Digits(13)
    else if(HasAny(cn, ['creditcard', 'kreditkarte', 'cardnr', 'kartennr', 'kartennummer']))then
      s:=Digits(16)
    else if(cn='ip')or(HasAny(cn, ['ipaddr', 'ip_addr', 'ipadr', 'ip_adr']))then
      s:=IntToStr(Rnd.Between(10, 250))+'.'+IntToStr(Rnd.Next(256))+'.'+
        IntToStr(Rnd.Next(256))+'.'+IntToStr(Rnd.Between(1, 254))
    else if(HasAny(cn, ['farbe', 'color', 'colour']))then
    begin
      if(Opt.German)then s:=Rnd.Pick(ColorsDE) else s:=Rnd.Pick(ColorsEN);
    end
    else if(HasAny(cn, ['beschreibung', 'description', 'comment', 'kommentar',
      'bemerk', 'text', 'info', 'notiz', 'note', 'memo', 'statement', 'paragraph']))then
      s:=Words(Rnd.Between(4, 9))+'.'
    else if(HasAny(cn, ['datum', 'date']))then
      s:=FormatDateTime('yyyy"-"mm"-"dd', RandomDate(cn))
    else if(HasAny(cn, ['code', 'kuerzel', 'kürzel', 'abk', 'sign']))or
      (Copy(cn, 1, 2)='kz')or(Copy(cn, Length(cn)-1, 2)='kz')then
    begin
      s:=Letters(Min(Max(MaxLen, 1), 4));
      if(MaxLen<3)then
        Unique:=False;
    end
    else if(HasAny(cn, ['fullname', 'kontakt', 'contact', 'ansprech', 'bearbeiter']))or
      ((HasAny(cn, ['name']))and(HasAny(tblname, ['kunde', 'customer', 'person',
        'user', 'benutzer', 'mitarbeiter', 'employee', 'kontakt', 'contact',
        'author', 'autor', 'member', 'mitglied', 'client'])))then
      s:=FirstName+' '+LastName
    else if(HasAny(cn, ['nummer', 'number']))or(Copy(cn, Length(cn)-1, 2)='nr')then
      s:=Digits(Min(Max(MaxLen, 1), 8))
    else if(MaxLen<=2)then
      s:=Letters(MaxLen)
    else
      s:=Words(Rnd.Between(1, 3));

    //a number keeps its length: the row number replaces its last digits
    if(Unique)and(s<>'')and(StrToInt64Def(s, -1)>=0)and(Length(s)>=Length(IntToStr(RowNr)))then
    begin
      nr:=IntToStr(RowNr);
      s:=Copy(s, 1, Length(s)-Length(nr))+nr;
      Unique:=False;
    end;

    if(Unique)and(Pos(IntToStr(RowNr), s)=0)then
    begin
      nr:=' '+IntToStr(RowNr);
      s:=UTF8Copy(s, 1, Max(MaxLen-Length(nr), 0))+nr;
      s:=Trim(s);
    end;

    Result:=UTF8Copy(s, 1, MaxLen);

    //as many characters as fit: the number that makes the value unique last
    if(Unique)and(UTF8Length(s)>MaxLen)then
      Result:=UTF8Copy(IntToStr(RowNr), 1, MaxLen);
  end;

  //The SQL literal of a column that is not a foreign key
  function ColumnValue(T: TEERTable; Col: TEERColumn; RowNr: integer; Unique: Boolean): string;
  var tn, cn, s: string;
    p1, p2, k, maxInt: integer;
    Enum: TStringList;
    IsBool: Boolean;
    d: Double;
    fs: TFormatSettings;
  begin
    tn:=TypeNameOf(Col);
    cn:=LowerCase(Col.ColName);
    ParseParams(Col.DatatypeParams, p1, p2);

    //Keys count up
    if(Col.AutoInc)or((Unique)and(IsIntType(tn)))then
    begin
      Result:=IntToStr(RowNr);
      Exit;
    end;

    if(Not(Col.NotNull))and(Not(Col.PrimaryKey))and(Not(Unique))then
      if(Rnd.Next(100)<Opt.NullPercent)then
      begin
        Result:='NULL';
        Exit;
      end;

    IsBool:=IsBoolType(tn);
    if(IsBool)or((IsIntType(tn))and(tn<>'YEAR')and
      ((Copy(cn, 1, 2)='is')or(Copy(cn, 1, 3)='hat')or(Copy(cn, 1, 3)='has')or
       (HasAny(cn, ['aktiv', 'active', 'flag', 'enabled', 'deleted', 'geloescht', 'gesperrt', 'locked']))))then
    begin
      k:=Rnd.Next(2);
      if(IsBool)and(Opt.TargetDB='PostgreSQL')then
        Result:=IfThen(k=1, 'TRUE', 'FALSE')
      else
        Result:=IntToStr(k);
    end
    else if(IsIntType(tn))then
    begin
      if(Pos('TINY', tn)>0)then
        maxInt:=100
      else if(Pos('SMALL', tn)>0)then
        maxInt:=30000
      else
        maxInt:=100000;

      if(tn='YEAR')or(HasAny(cn, ['jahr', 'year']))then
        Result:=IntToStr(Rnd.Between(1990, 2025))
      else if(HasAny(cn, ['alter', 'age']))and(Not(HasAny(cn, ['page', 'image', 'stage', 'usage'])))then
        Result:=IntToStr(Rnd.Between(18, 90))
      else if(HasAny(cn, ['plz', 'zip']))then
        Result:=IntToStr(Rnd.Between(10000, Min(99999, Max(maxInt, 10000))))
      else if(HasAny(cn, ['anzahl', 'menge', 'count', 'qty', 'quantity', 'stueck', 'stück']))then
        Result:=IntToStr(Rnd.Between(1, 100))
      else if(HasAny(cn, ['version', 'status', 'state', 'typ', 'type', 'art', 'level', 'stufe', 'prio']))then
        Result:=IntToStr(Rnd.Between(0, 5))
      else if(HasAny(cn, ['pos', 'sort', 'reihenfolge', 'order', 'nr', 'num']))then
        Result:=IntToStr(Min(RowNr, maxInt))
      else
        Result:=IntToStr(Rnd.Between(1, Min(1000, maxInt)));
    end
    else if(IsDecimalType(tn))then
    begin
      if(p2<0)then
      begin
        if(p1>0)and((tn='DECIMAL')or(tn='NUMERIC')or(tn='DEC')or(tn='FIXED')or(tn='NUMBER'))then
          p2:=0
        else
          p2:=2;
      end;
      if(p2>6)then
        p2:=6;
      //digits before the decimal point
      if(p1>0)then
        k:=Max(Min(p1-p2, 4), 1)
      else
        k:=3;
      d:=Rnd.Next(Round(IntPower(10, k)))+Rnd.Next(1000000)/1000000;
      if(p2=0)then
        d:=Int(d);
      fs:=DefaultFormatSettings;
      fs.DecimalSeparator:='.';
      Result:=FloatToStrF(d, ffFixed, 18, p2, fs);
    end
    else if(tn='DATE')then
      Result:=DateLiteral(RandomDate(cn))
    else if(tn='TIME')then
      Result:=''''+Format('%.2d:%.2d:%.2d', [Rnd.Next(24), Rnd.Next(60), Rnd.Next(60)])+''''
    else if(Pos('DATETIME', tn)>0)or(Pos('TIMESTAMP', tn)>0)then
      Result:=DateTimeLiteral(RandomDate(cn)+Rnd.Next(86400)/86400)
    else if(tn='ENUM')or(tn='SET')then
    begin
      Enum:=TStringList.Create;
      try
        ParseEnumValues(Col.DatatypeParams, Enum);
        if(Enum.Count>0)then
          Result:=QuoteStr(Enum[Rnd.Next(Enum.Count)])
        else if(Col.NotNull)then
          Result:=''''''
        else
          Result:='NULL';
      finally
        Enum.Free;
      end;
    end
    else if(IsStringType(tn))then
    begin
      //the long text types have no length
      if(p1<=0)then
      begin
        if(Pos('CHAR', tn)>0)and(Pos('VAR', tn)=0)then
          p1:=1
        else if(Pos('TINY', tn)>0)then
          p1:=255
        else
          p1:=2000;
      end;
      s:=TextValue(LowerCase(T.ObjName), cn, p1, RowNr, Unique);
      Result:=QuoteStr(s);
    end
    else
    begin
      //BLOB, geometry and everything unknown
      if(Col.NotNull)or(Col.PrimaryKey)then
      begin
        if(Unique)then
          Result:=QuoteStr(IntToStr(RowNr))
        else
          Result:='''''';
      end
      else
        Result:='NULL';
    end;
  end;

  //Is the column the only column of a unique index of the table?
  function InUniqueIndex(T: TEERTable; Col: TEERColumn): Boolean;
  var i: integer;
  begin
    Result:=False;
    for i:=0 to T.Indices.Count-1 do
      with TEERIndex(T.Indices[i]) do
        if(IndexKind=ik_UNIQUE_INDEX)and(Columns.Count=1)then
          if(Columns[0]=IntToStr(Col.Obj_id))then
            Result:=True;
  end;

  procedure FillTable(TD: TTableData);
  var T: TEERTable;
    Wanted, RowNr, c, i, k, Attempt, PKCount, PKNoFK, FirstOwnPK, ParentRow, sc, dc: integer;
    Row: TStringRow;
    Col: TEERColumn;
    Rel: TEERRel;
    Parent: TTableData;
    Keys: TStringList;
    Key: string;
    FKNullable, KeyOK, SetNull: Boolean;
    IsFKCol: array of Boolean;
    Warned: TStringList;
  begin
    T:=TD.Table;
    Wanted:=RowsFor(T);
    Keys:=TStringList.Create;
    Warned:=TStringList.Create;
    try
      Keys.Sorted:=True;

      //The columns that take their value from another table
      SetLength(IsFKCol, T.Columns.Count);
      for c:=0 to T.Columns.Count-1 do
        IsFKCol[c]:=False;
      for i:=0 to T.RelEnd.Count-1 do
      begin
        Rel:=TEERRel(T.RelEnd[i]);
        if(Rel.DestTbl<>T)then
          continue;
        for k:=0 to Rel.FKFields.Count-1 do
        begin
          dc:=TD.ColumnIndex(Rel.FKFields.ValueFromIndex[k]);
          if(dc>=0)then
            IsFKCol[dc]:=True;
        end;
      end;

      PKCount:=0;
      PKNoFK:=0;
      FirstOwnPK:=-1;
      for c:=0 to T.Columns.Count-1 do
        if(TEERColumn(T.Columns[c]).PrimaryKey)then
        begin
          inc(PKCount);
          if(Not(IsFKCol[c]))then
          begin
            inc(PKNoFK);
            if(FirstOwnPK=-1)then
              FirstOwnPK:=c;
          end;
        end;

      SetLength(TD.Rows, 0);
      for RowNr:=1 to Wanted do
      begin
        SetLength(Row, T.Columns.Count);

        //Columns of the table itself
        for c:=0 to T.Columns.Count-1 do
          if(Not(IsFKCol[c]))then
          begin
            Col:=TEERColumn(T.Columns[c]);
            //A primary key of several own columns: the first one counts
            //up, which is enough to make the key unique
            Row[c]:=ColumnValue(T, Col, RowNr,
              (c=FirstOwnPK)or(InUniqueIndex(T, Col)));
          end;

        //Foreign keys: the values of a row of the referenced table. When
        //they are (part of) the primary key the combination must be new
        Attempt:=0;
        repeat
          inc(Attempt);

          for i:=0 to T.RelEnd.Count-1 do
          begin
            Rel:=TEERRel(T.RelEnd[i]);
            if(Rel.DestTbl<>T)or(Rel.FKFields.Count=0)then
              continue;

            FKNullable:=True;
            for k:=0 to Rel.FKFields.Count-1 do
            begin
              dc:=TD.ColumnIndex(Rel.FKFields.ValueFromIndex[k]);
              if(dc>=0)then
                if(TEERColumn(T.Columns[dc]).NotNull)or(TEERColumn(T.Columns[dc]).PrimaryKey)then
                  FKNullable:=False;
            end;

            Parent:=DataOf(TEERTable(Rel.SrcTbl));
            ParentRow:=-1;
            SetNull:=False;

            if(Rel.SrcTbl=T)then
            begin
              //A reference to the table itself: one of the rows before
              if(Length(TD.Rows)>0)then
                ParentRow:=Rnd.Next(Length(TD.Rows))
              else
                SetNull:=True;
              Parent:=TD;
            end
            else if(Parent=nil)or(Not(Parent.Done))or(Length(Parent.Rows)=0)then
            begin
              //The referenced table is not filled (not selected, no rows,
              //or a circle of foreign keys)
              SetNull:=True;
              if(Warned.IndexOf(Rel.ObjName)=-1)then
              begin
                Warned.Add(Rel.ObjName);
                if(FKNullable)then
                  Output.Add('-- '+T.ObjName+': no rows of '+TEERTable(Rel.SrcTbl).ObjName+
                    ' in this script, the foreign key ('+Rel.ObjName+') stays NULL')
                else
                  Output.Add('-- WARNING '+T.ObjName+': no rows of '+TEERTable(Rel.SrcTbl).ObjName+
                    ' in this script, the foreign key ('+Rel.ObjName+
                    ') is NOT NULL and gets numbers that may not exist');
              end;
            end
            else if(Rel.RelKind=rk_11)or(Rel.RelKind=rk_11Sub)or(Rel.RelKind=rk_11NonId)then
            begin
              //1:1: every row of the referenced table once
              if(RowNr+Attempt-2<Length(Parent.Rows))then
                ParentRow:=RowNr+Attempt-2
              else
                SetNull:=True;
            end
            else
              ParentRow:=Rnd.Next(Length(Parent.Rows));

            //an optional reference stays empty now and then
            if(ParentRow>=0)and(FKNullable)and(Rnd.Next(100)<Opt.NullPercent)then
              SetNull:=True;

            for k:=0 to Rel.FKFields.Count-1 do
            begin
              dc:=TD.ColumnIndex(Rel.FKFields.ValueFromIndex[k]);
              if(dc<0)then
                continue;
              Col:=TEERColumn(T.Columns[dc]);

              if(SetNull)or(ParentRow<0)then
              begin
                if(FKNullable)then
                  Row[dc]:='NULL'
                else if(Rel.SrcTbl=T)then
                  //the first row of a table that must reference itself
                  Row[dc]:=ColumnValue(T, Col, RowNr, True)
                else
                  Row[dc]:=ColumnValue(T, Col, Rnd.Between(1, Max(Opt.DefaultRows, 1)), True);
              end
              else
              begin
                sc:=Parent.ColumnIndex(Rel.FKFields.Names[k]);
                if(sc>=0)then
                  Row[dc]:=Parent.Rows[ParentRow][sc]
                else
                  Row[dc]:='NULL';
              end;
            end;
          end;

          KeyOK:=True;
          if(PKCount>0)and(PKNoFK=0)then
          begin
            Key:='';
            for c:=0 to T.Columns.Count-1 do
              if(TEERColumn(T.Columns[c]).PrimaryKey)then
                Key:=Key+Row[c]+#1;
            KeyOK:=(Keys.IndexOf(Key)=-1);
            if(KeyOK)then
              Keys.Add(Key);
          end;
        until (KeyOK)or(Attempt>=200);

        if(Not(KeyOK))then
        begin
          Output.Add('-- '+T.ObjName+': '+IntToStr(RowNr-1)+' of '+IntToStr(Wanted)+
            ' rows, there are no more combinations of the referenced rows for its primary key');
          break;
        end;

        SetLength(TD.Rows, Length(TD.Rows)+1);
        TD.Rows[High(TD.Rows)]:=Copy(Row, 0, Length(Row));
      end;

      TD.Done:=True;
    finally
      Keys.Free;
      Warned.Free;
    end;
  end;

  procedure WriteTable(TD: TTableData);
  var T: TEERTable;
    r, c: integer;
    Cols, Vals: string;
    HasAutoInc, Skip: Boolean;
  begin
    T:=TD.Table;
    if(Length(TD.Rows)=0)then
      Exit;

    HasAutoInc:=False;
    for c:=0 to T.Columns.Count-1 do
      if(TEERColumn(T.Columns[c]).AutoInc)then
        HasAutoInc:=True;

    Output.Add('');
    Output.Add('-- '+T.ObjName+' ('+IntToStr(Length(TD.Rows))+')');

    if(HasAutoInc)and(Not(Opt.SkipAutoInc))and(Opt.TargetDB='SQL Server')then
      Output.Add('SET IDENTITY_INSERT '+SQLTableName(T)+' ON;');

    Cols:='';
    for c:=0 to T.Columns.Count-1 do
    begin
      Skip:=(Opt.SkipAutoInc)and(TEERColumn(T.Columns[c]).AutoInc);
      if(Not(Skip))then
      begin
        if(Cols<>'')then
          Cols:=Cols+', ';
        Cols:=Cols+SQLName(T, TEERColumn(T.Columns[c]).ColName);
      end;
    end;

    for r:=0 to High(TD.Rows) do
    begin
      Vals:='';
      for c:=0 to T.Columns.Count-1 do
      begin
        Skip:=(Opt.SkipAutoInc)and(TEERColumn(T.Columns[c]).AutoInc);
        if(Not(Skip))then
        begin
          if(Vals<>'')then
            Vals:=Vals+', ';
          Vals:=Vals+TD.Rows[r][c];
        end;
      end;
      Output.Add('INSERT INTO '+SQLTableName(T)+' ('+Cols+') VALUES ('+Vals+');');
      inc(Statements);
    end;

    if(HasAutoInc)and(Not(Opt.SkipAutoInc))and(Opt.TargetDB='SQL Server')then
      Output.Add('SET IDENTITY_INSERT '+SQLTableName(T)+' OFF;');
  end;

var
  Pending: TList;
  i, k: integer;
  T: TEERTable;
  TD: TTableData;
  Ready, Progress, AnyAutoInc: Boolean;
  Rel: TEERRel;
begin
  Statements:=0;
  Rnd:=TRandom.Create;
  Data:=TList.Create;
  Pending:=TList.Create;
  try
    Rnd.State:=LongWord((QWord(Opt.Seed)*2654435761+1) and $FFFFFFFF);
    if(Rnd.State=0)then
      Rnd.State:=1;

    Output.Add('-- Test data, generated by the DBDesigner Fork Test Data Generator');
    Output.Add('-- Model: '+Model.GetModelName+', database: '+Opt.TargetDB+
      ', seed: '+IntToStr(Opt.Seed));

    //The order: a table after the tables it references
    for i:=0 to Tables.Count-1 do
      Pending.Add(Tables[i]);

    while(Pending.Count>0)do
    begin
      Progress:=False;
      i:=0;
      while(i<Pending.Count)do
      begin
        T:=TEERTable(Pending[i]);
        Ready:=True;
        for k:=0 to T.RelEnd.Count-1 do
        begin
          Rel:=TEERRel(T.RelEnd[k]);
          if(Rel.DestTbl=T)and(Rel.SrcTbl<>T)then
            if(Pending.IndexOf(Rel.SrcTbl)>=0)then
              Ready:=False;
        end;

        if(Ready)then
        begin
          TD:=TTableData.Create;
          TD.Table:=T;
          Data.Add(TD);
          Pending.Delete(i);
          Progress:=True;
        end
        else
          inc(i);
      end;

      if(Not(Progress))then
      begin
        //A circle of foreign keys: take the first table as it is
        T:=TEERTable(Pending[0]);
        Output.Add('-- WARNING: circular foreign keys, '+T.ObjName+
          ' is filled before the tables it references');
        TD:=TTableData.Create;
        TD.Table:=T;
        Data.Add(TD);
        Pending.Delete(0);
      end;
    end;

    for i:=0 to Data.Count-1 do
      FillTable(TTableData(Data[i]));

    if(Opt.DeleteFirst)then
    begin
      Output.Add('');
      for i:=Data.Count-1 downto 0 do
        Output.Add('DELETE FROM '+SQLTableName(TTableData(Data[i]).Table)+';');
    end;

    AnyAutoInc:=False;
    for i:=0 to Data.Count-1 do
    begin
      WriteTable(TTableData(Data[i]));
      for k:=0 to TTableData(Data[i]).Table.Columns.Count-1 do
        if(TEERColumn(TTableData(Data[i]).Table.Columns[k]).AutoInc)then
          AnyAutoInc:=True;
    end;

    if(Opt.Commit)then
    begin
      Output.Add('');
      Output.Add('COMMIT;');
    end;

    if(AnyAutoInc)then
    begin
      Output.Add('');
      if(Opt.SkipAutoInc)then
        Output.Add('-- The auto increment columns are left to the database. The foreign keys '+
          'expect that it numbers the rows of every table from 1.')
      else if(Opt.TargetDB<>'My SQL')and(Opt.TargetDB<>'SQLite')then
        Output.Add('-- The auto increment columns got explicit values: set the sequences / '+
          'generators of the tables behind the highest value before you insert more rows.');
    end;

    Result:=Statements;
  finally
    for i:=0 to Data.Count-1 do
      TTableData(Data[i]).Free;
    Data.Free;
    Pending.Free;
    Rnd.Free;
  end;
end;

end.
