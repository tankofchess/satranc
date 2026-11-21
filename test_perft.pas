program test_perft;

{$mode objfpc}{$H+}

uses ChessEngine;

function Perft(const P: TPosition; Depth: Integer): Int64;
var
  L: TMoveList;
  P2: TPosition;
  i: Integer;
begin
  L := GenLegal(P);
  if Depth <= 1 then Exit(L.Count);
  Result := 0;
  for i := 0 to L.Count - 1 do
  begin
    P2 := P;
    ApplyMove(P2, L.Items[i]);
    Result := Result + Perft(P2, Depth - 1);
  end;
end;

procedure Run(const FEN: string; MaxDepth: Integer);
var
  P: TPosition;
  d: Integer;
begin
  P := FENToPos(FEN);
  WriteLn('FEN: ', FEN);
  for d := 1 to MaxDepth do
    WriteLn('  perft(', d, ') = ', Perft(P, d));
end;

begin
  Run('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 3);
  Run('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 3);
  Run('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 3);
  Run('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', 3);
  Run('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', 3);
  Run('r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10', 3);
end.
