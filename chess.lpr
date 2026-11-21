program Chess;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, ChessMain;

begin
  Application.Initialize;
  Application.CreateForm(TChessMainForm, ChessMainForm);
  Application.Run;
end.
