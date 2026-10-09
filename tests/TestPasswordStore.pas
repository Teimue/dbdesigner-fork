program TestPasswordStore;

// The protection of stored database passwords (src/PasswordStore.pas):
// a password comes back as it was, the protected text does not contain it,
// a damaged or foreign text gives nothing.
//
// Plain FPC, no LCL:
//   fpc -Mdelphi -Fusrc -Fisrc -FEbin tests/TestPasswordStore.pas && bin/TestPasswordStore
// Exit code = number of failed checks.

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses SysUtils, PasswordStore;

var
  Failures: integer = 0;
  p, e1, e2: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if(Cond)then
    WriteLn('  ok    ', What)
  else
  begin
    WriteLn('  FAIL  ', What);
    inc(Failures);
  end;
end;

begin
  if(Not(PasswordStoreAvailable))then
  begin
    Check(ProtectPassword('secret')='', 'not available on this system: nothing is stored');
    Check(UnprotectPassword('abc')='', 'and nothing is read');
  end
  else
  begin
    p:='Gehe!m 123 '#$C3#$A4#$C3#$B6#$C3#$BC' "quote" ;=';
    e1:=ProtectPassword(p);
    Check(e1<>'', 'a password is protected');
    Check(Pos('Gehe', e1)=0, 'the protected text does not contain the password');
    Check((Pos(#13, e1)=0)and(Pos(#10, e1)=0)and(Pos('=', Copy(e1, 1, Length(e1)-2))=0),
      'it is one line without "=" inside (a value of an ini file)');
    Check(UnprotectPassword(e1)=p, 'and comes back as it was, with umlauts and special characters');

    e2:=ProtectPassword(p);
    Check(UnprotectPassword(e2)=p, 'a second time too');

    Check(ProtectPassword('')='', 'an empty password is not stored');
    Check(UnprotectPassword('')='', 'an empty text gives nothing');
    Check(UnprotectPassword('this is no protected text')='', 'a text that is not protected gives nothing');

    //damaged in the middle
    e2:=e1;
    if(e2[Length(e2) div 2]='A')then
      e2[Length(e2) div 2]:='B'
    else
      e2[Length(e2) div 2]:='A';
    Check(UnprotectPassword(e2)='', 'a damaged text gives nothing');
  end;

  WriteLn;
  if(Failures=0)then
    WriteLn('SUCCESS: the password store works')
  else
    WriteLn(Failures, ' check(s) FAILED');
  Halt(Failures);
end.
