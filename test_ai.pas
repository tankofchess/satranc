program test_ai;
{$mode objfpc}{$H+}
uses SysUtils, ChessEngine, ChessAI;
var P: TPosition; R: TSearchResult; d, i: Integer; P2: TPosition; L: TMoveList; G: TChessGame;
begin
  P := FENToPos('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
  for d := 1 to 3 do
  begin
    if FindBestMove(P, d, 5000, R) then
      WriteLn('depth=', d, ' move=', SqName(R.Move.FromSq), SqName(R.Move.ToSq),
              ' score=', R.Score, ' nodes=', R.Nodes)
    else WriteLn('depth=', d, ' failed');
  end;

  G := TChessGame.Create;
  try
    for i := 1 to 10 do
    begin
      if not FindBestMove(G.Pos, 2, 3000, R) then Break;
      WriteLn(i, '. ', G.DoMove(R.Move), '  (', R.Score, ')');
    end;
    WriteLn('FEN: ', G.FEN);
    L := G.LegalMoves;
    WriteLn('legal=', L.Count);
  finally
    G.Free;
  end;
end.
