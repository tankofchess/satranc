unit ChessAI;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ChessEngine;

type
  TScoredMove = record
    Move: TMove;
    Score: Integer;   // hamleyi yapan tarafın bakış açısı (centipawn)
  end;

  TSearchResult = record
    Move: TMove;
    Score: Integer;
    Nodes: Int64;
    Depth: Integer;
    Found: Boolean;
    Top: array[0..4] of TScoredMove;  // en iyi 5 kök hamlesi, puana göre sıralı
    TopCount: Integer;
  end;

function EvaluatePosition(const P: TPosition): Integer; // + = beyaz iyi
function FindBestMove(const P: TPosition; MaxDepth, MaxTimeMs: Integer;
                      out R: TSearchResult): Boolean;
procedure AbortSearch; // arka plandaki aramayı iptal etmek için

implementation

uses
  Classes, ZStream;

{$R kbn.res}

const
  MATE = 100000;
  INF = 200000;

  Val: array[1..6] of Integer = (100, 320, 330, 500, 900, 0);

  CornerFile: array[0..3] of Integer = (0, 7, 0, 7);
  CornerRank: array[0..3] of Integer = (0, 0, 7, 7);

  // Hareket alanı (mobility): yapraktaki legal hamle sayısı başına centipawn.
  // GenLegal zaten her düğümde çağrıldığı için ekstra arama maliyeti yok.
  // Toplam bonus en fazla bir piyon değerini (100 cp) geçemez.
  MOBILITY_MG = 3;   // açılış/orta oyun
  MOBILITY_EG = 1;   // oyun sonu

  // Transposition table: 2^17 = 131072 girdi
  TT_BITS = 17;
  TT_SIZE = 1 shl TT_BITS;
  TT_MASK = TT_SIZE - 1;

  // Tablolar 8. sıradan 1. sıraya doğru yazılmıştır (beyaz perspektifi)
  PST_Pawn: array[0..63] of Integer = (
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0);

  PST_Knight: array[0..63] of Integer = (
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50);

  PST_Bishop: array[0..63] of Integer = (
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20);

  PST_Rook: array[0..63] of Integer = (
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0);

  PST_Queen: array[0..63] of Integer = (
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20);

  PST_KingMG: array[0..63] of Integer = (
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20);

  PST_KingEG: array[0..63] of Integer = (
    -50,-40,-30,-20,-20,-30,-40,-50,
    -30,-20,-10,  0,  0,-10,-20,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-30,  0,  0,  0,  0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50);

type
  ESearchAbort = class(Exception);

  TTTFlag = (tfNone, tfExact, tfLower, tfUpper);

  TTTEntry = record
    Key: QWord;
    Score: Integer;
    Depth: Integer;
    Best: TMove;
    Flag: TTTFlag;
  end;

  TByteArray = array of Byte;
  TTableKind = (tkNone, tkKBN, tkKQ, tkKR, tkKQKR, tkKRB, tkKBB, tkKRN);

var
  AbortFlag: Boolean;
  StartTicks, TimeLimit: QWord;
  Killer1, Killer2: array[0..63] of TMove;
  History: array[0..63, 0..63] of Integer;
  TT: array[0..TT_SIZE - 1] of TTTEntry;
  TTBest: TMove;
  TTBestValid: Boolean;
  ZobPiece: array[0..11, 0..63] of QWord;
  ZobSide: QWord;
  ZobCastle: array[0..15] of QWord;
  ZobEP: array[0..63] of QWord;
  ZobSeed: QWord;
  ZobInit: Boolean;

  // Kesin oyun sonu tabloları: K+F+A, K+V, K+R, K+V vs K+R, K+R+F,
  // zıt renk K+F+F ve K+R+A DTM baytları. Sıkıştırılmış olarak kaynağa gömülür.
  KBNData, KQData, KRData, KQKRData, KRBData, KBBData, KRNData: TByteArray;
  BasicReady, BasicFailed: Boolean;

function LoadCompressedResource(const ResName: string; ExpectedSize: Integer;
                                out Data: TByteArray): Boolean;
var
  RS: TResourceStream;
  DS: TDecompressionStream;
  P: PByte;
  Got, Total: Integer;
begin
  Result := False;
  RS := nil;
  DS := nil;
  try
    SetLength(Data, ExpectedSize);
    RS := TResourceStream.Create(HInstance, ResName, PChar(10));
    DS := TDecompressionStream.Create(RS);
    Total := 0;
    P := @Data[0];
    repeat
      Got := DS.Read(P^, 65536);
      if Got <= 0 then Break;
      Inc(Total, Got);
      Inc(P, Got);
    until False;
    Result := Total = ExpectedSize;
  except
    Result := False;
  end;
  DS.Free;
  RS.Free;
  if not Result then SetLength(Data, 0);
end;

procedure InitBasicTables;
begin
  if BasicReady or BasicFailed then Exit;
  BasicFailed := True;
  if not LoadCompressedResource('kbn', 64 * 64 * 64 * 64 * 2, KBNData) then Exit;
  if not LoadCompressedResource('kq', 64 * 64 * 64 * 2, KQData) then Exit;
  if not LoadCompressedResource('kr', 64 * 64 * 64 * 2, KRData) then Exit;
  if not LoadCompressedResource('kqkr', 64 * 64 * 64 * 64 * 2, KQKRData) then Exit;
  if not LoadCompressedResource('krb', 64 * 64 * 64 * 64 * 2, KRBData) then Exit;
  if not LoadCompressedResource('kbb', 64 * 64 * 64 * 64 * 2, KBBData) then Exit;
  if not LoadCompressedResource('krn', 64 * 64 * 64 * 64 * 2, KRNData) then Exit;
  BasicReady := True;
  BasicFailed := False;
end;

function KBNIndex(WK, BK, BS, NS, STM: Integer): Integer; inline;
begin
  Result := ((((WK * 64 + BK) * 64 + BS) * 64 + NS) * 2 + STM);
end;

function SingleIndex(WK, BK, PS, STM: Integer): Integer; inline;
begin
  Result := (((WK * 64 + BK) * 64 + PS) * 2 + STM);
end;

function KBNNormalizedSTM(const P: TPosition; WhiteAttacker: Boolean): Integer; inline;
begin
  if WhiteAttacker then Result := Ord(P.Side)
  else Result := Ord(Opp(P.Side));
end;

function GetKBNSetup(const P: TPosition; out WK, BK, BS, NS: Integer;
                     out WhiteAttacker: Boolean): Boolean;
var
  S, WKing, BKing, WBsq, WNsq, BBsq, BNsq: Integer;
  CWK, CBK, CWB, CWN, CBB, CBN: Integer;
  Extra: Boolean;
begin
  Result := False;
  WKing := -1; BKing := -1; WBsq := -1; WNsq := -1; BBsq := -1; BNsq := -1;
  CWK := 0; CBK := 0; CWB := 0; CWN := 0; CBB := 0; CBN := 0;
  Extra := False;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWB: begin Inc(CWB); WBsq := S; end;
      pcWN: begin Inc(CWN); WNsq := S; end;
      pcBB: begin Inc(CBB); BBsq := S; end;
      pcBN: begin Inc(CBN); BNsq := S; end;
      pcEmpty: ;
    else
      Extra := True;
    end;
  if Extra or (CWK <> 1) or (CBK <> 1) then Exit;

  WhiteAttacker := (CWB = 1) and (CWN = 1) and (CBB = 0) and (CBN = 0);
  if not WhiteAttacker then
    if (CWB <> 0) or (CWN <> 0) or (CBB <> 1) or (CBN <> 1) then Exit;

  if WhiteAttacker then
  begin
    WK := WKing;  BK := BKing;  BS := WBsq;  NS := WNsq;
  end
  else
  begin
    // 180 derece ayna: saldıran siyah daima beyaz gibi değerlendirilir.
    WK := 63 - BKing;  BK := 63 - WKing;
    BS := 63 - BBsq;   NS := 63 - BNsq;
  end;
  Result := True;
end;

function GetSingleSetup(const P: TPosition; out WK, BK, PS: Integer;
                        out WhiteAttacker: Boolean; out Kind: TTableKind): Boolean;
var
  S, WKing, BKing, WQsq, WRsq, BQsq, BRsq: Integer;
  CWK, CBK, CWQ, CWR, CBQ, CBR: Integer;
  Extra: Boolean;
begin
  Result := False;
  Kind := tkNone;
  WhiteAttacker := False;
  WKing := -1; BKing := -1; WQsq := -1; WRsq := -1; BQsq := -1; BRsq := -1;
  CWK := 0; CBK := 0; CWQ := 0; CWR := 0; CBQ := 0; CBR := 0;
  Extra := False;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWQ: begin Inc(CWQ); WQsq := S; end;
      pcWR: begin Inc(CWR); WRsq := S; end;
      pcBQ: begin Inc(CBQ); BQsq := S; end;
      pcBR: begin Inc(CBR); BRsq := S; end;
      pcEmpty: ;
    else
      Extra := True;
    end;
  if Extra or (CWK <> 1) or (CBK <> 1) then Exit;

  if (CWQ = 1) and (CWR = 0) and (CBQ = 0) and (CBR = 0) then
  begin
    Kind := tkKQ; WhiteAttacker := True; PS := WQsq;
  end
  else if (CWR = 1) and (CWQ = 0) and (CBQ = 0) and (CBR = 0) then
  begin
    Kind := tkKR; WhiteAttacker := True; PS := WRsq;
  end
  else if (CBQ = 1) and (CBR = 0) and (CWQ = 0) and (CWR = 0) then
  begin
    Kind := tkKQ; WhiteAttacker := False; PS := 63 - BQsq;
  end
  else if (CBR = 1) and (CBQ = 0) and (CWQ = 0) and (CWR = 0) then
  begin
    Kind := tkKR; WhiteAttacker := False; PS := 63 - BRsq;
  end
  else Exit;

  if WhiteAttacker then
  begin
    WK := WKing;  BK := BKing;
  end
  else
  begin
    WK := 63 - BKing;  BK := 63 - WKing;
  end;
  Result := True;
end;

function KRBIndex(WK, BK, RS, BS, STM: Integer): Integer; inline;
begin
  Result := ((((WK * 64 + BK) * 64 + RS) * 64 + BS) * 2 + STM);
end;

function KRNIndex(WK, BK, RS, NS, STM: Integer): Integer; inline;
begin
  Result := ((((WK * 64 + BK) * 64 + RS) * 64 + NS) * 2 + STM);
end;

function GetKRBSetup(const P: TPosition; out WK, BK, RS, BS: Integer;
                     out WhiteAttacker: Boolean): Boolean;
var
  S, WKing, BKing, WRsq, WBsq, BRsq, BBsq: Integer;
  CWK, CBK, CWR, CWB, CBR, CBB: Integer;
  Extra: Boolean;
begin
  Result := False;
  WKing := -1; BKing := -1; WRsq := -1; WBsq := -1; BRsq := -1; BBsq := -1;
  CWK := 0; CBK := 0; CWR := 0; CWB := 0; CBR := 0; CBB := 0;
  Extra := False;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWR: begin Inc(CWR); WRsq := S; end;
      pcWB: begin Inc(CWB); WBsq := S; end;
      pcBR: begin Inc(CBR); BRsq := S; end;
      pcBB: begin Inc(CBB); BBsq := S; end;
      pcEmpty: ;
    else
      Extra := True;
    end;
  if Extra or (CWK <> 1) or (CBK <> 1) then Exit;

  WhiteAttacker := (CWR = 1) and (CWB = 1) and (CBR = 0) and (CBB = 0);
  if not WhiteAttacker then
    if (CWR <> 0) or (CWB <> 0) or (CBR <> 1) or (CBB <> 1) then Exit;

  if WhiteAttacker then
  begin
    WK := WKing;  BK := BKing;  RS := WRsq;  BS := WBsq;
  end
  else
  begin
    // 180 derece ayna: saldıran siyah daima normalize beyaz olur.
    WK := 63 - BKing;  BK := 63 - WKing;
    RS := 63 - BRsq;   BS := 63 - BBsq;
  end;
  Result := True;
end;

function GetKRNSetup(const P: TPosition; out WK, BK, RS, NS: Integer;
                     out WhiteAttacker: Boolean): Boolean;
var
  S, WKing, BKing, WRsq, WNsq, BRsq, BNsq: Integer;
  CWK, CBK, CWR, CWN, CBR, CBN: Integer;
  Extra: Boolean;
begin
  Result := False;
  WKing := -1; BKing := -1; WRsq := -1; WNsq := -1; BRsq := -1; BNsq := -1;
  CWK := 0; CBK := 0; CWR := 0; CWN := 0; CBR := 0; CBN := 0;
  Extra := False;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWR: begin Inc(CWR); WRsq := S; end;
      pcWN: begin Inc(CWN); WNsq := S; end;
      pcBR: begin Inc(CBR); BRsq := S; end;
      pcBN: begin Inc(CBN); BNsq := S; end;
      pcEmpty: ;
    else
      Extra := True;
    end;
  if Extra or (CWK <> 1) or (CBK <> 1) then Exit;

  WhiteAttacker := (CWR = 1) and (CWN = 1) and (CBR = 0) and (CBN = 0);
  if not WhiteAttacker then
    if (CWR <> 0) or (CWN <> 0) or (CBR <> 1) or (CBN <> 1) then Exit;

  if WhiteAttacker then
  begin
    WK := WKing;  BK := BKing;  RS := WRsq;  NS := WNsq;
  end
  else
  begin
    // 180 derece ayna: saldıran siyah daima normalize beyaz olur.
    WK := 63 - BKing;  BK := 63 - WKing;
    RS := 63 - BRsq;   NS := 63 - BNsq;
  end;
  Result := True;
end;

function KBBIndex(WK, BK, B1, B2, STM: Integer): Integer; inline;
begin
  Result := ((((WK * 64 + BK) * 64 + B1) * 64 + B2) * 2 + STM);
end;

function GetKBBSetup(const P: TPosition; out WK, BK, B1, B2: Integer;
                     out WhiteAttacker: Boolean): Boolean;
var
  S, WKing, BKing, Bs1, Bs2: Integer;
  CWK, CBK, CWB, CBB, Other: Integer;
  Tmp1: Integer;
begin
  Result := False;
  WKing := -1; BKing := -1; Bs1 := -1; Bs2 := -1;
  CWK := 0; CBK := 0; CWB := 0; CBB := 0; Other := 0;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWB: begin Inc(CWB); if Bs1 < 0 then Bs1 := S else Bs2 := S; end;
      pcBB: begin Inc(CBB); if Bs1 < 0 then Bs1 := S else Bs2 := S; end;
      pcEmpty: ;
    else
      Inc(Other);
    end;
  if (Other <> 0) or (CWK <> 1) or (CBK <> 1) then Exit;

  WhiteAttacker := (CWB = 2) and (CBB = 0);
  if not WhiteAttacker then
    if (CWB <> 0) or (CBB <> 2) then Exit;

  // Aynı renk filer zorla mat getirmez; FIDE 5.2.2 gereği zaten beraberlik.
  if ((FileOf(Bs1) + RankOf(Bs1)) and 1) = ((FileOf(Bs2) + RankOf(Bs2)) and 1) then Exit;

  if WhiteAttacker then
  begin
    WK := WKing;  BK := BKing;
  end
  else
  begin
    WK := 63 - BKing;  BK := 63 - WKing;
    Bs1 := 63 - Bs1;   Bs2 := 63 - Bs2;
  end;

  // Tabloda b1 açık renk, b2 koyu renk fildir.
  if ((FileOf(Bs1) + RankOf(Bs1)) and 1) = 0 then
  begin
    Tmp1 := Bs1; Bs1 := Bs2; Bs2 := Tmp1;
  end;
  B1 := Bs1;  B2 := Bs2;
  Result := True;
end;

function TablePositionDtm(const P: TPosition; out WhiteAttacker: Boolean;
                          out Kind: TTableKind): Integer;
var
  WK, BK, BS, NS, RS, BSS, B1, B2, STM: Integer;
  WA: Boolean;
begin
  Result := -1;
  Kind := tkNone;
  WhiteAttacker := False;
  InitBasicTables;
  if not BasicReady then Exit;

  if GetKBNSetup(P, WK, BK, BS, NS, WA) then
  begin
    Kind := tkKBN;
    WhiteAttacker := WA;
    STM := KBNNormalizedSTM(P, WA);
    Result := KBNData[KBNIndex(WK, BK, BS, NS, STM)];
    Exit;
  end;

  if GetKRBSetup(P, WK, BK, RS, BSS, WA) then
  begin
    Kind := tkKRB;
    WhiteAttacker := WA;
    STM := KBNNormalizedSTM(P, WA);
    Result := KRBData[KRBIndex(WK, BK, RS, BSS, STM)];
    Exit;
  end;

  if GetKRNSetup(P, WK, BK, RS, NS, WA) then
  begin
    Kind := tkKRN;
    WhiteAttacker := WA;
    STM := KBNNormalizedSTM(P, WA);
    Result := KRNData[KRNIndex(WK, BK, RS, NS, STM)];
    Exit;
  end;

  if GetKBBSetup(P, WK, BK, B1, B2, WA) then
  begin
    Kind := tkKBB;
    WhiteAttacker := WA;
    STM := KBNNormalizedSTM(P, WA);
    Result := KBBData[KBBIndex(WK, BK, B1, B2, STM)];
    Exit;
  end;

  if GetSingleSetup(P, WK, BK, BS, WA, Kind) then
  begin
    WhiteAttacker := WA;
    STM := KBNNormalizedSTM(P, WA);
    if Kind = tkKQ then Result := KQData[SingleIndex(WK, BK, BS, STM)]
    else Result := KRData[SingleIndex(WK, BK, BS, STM)];
  end;
end;

function KQKRIndex(WK, BK, WQ, BR, STM: Integer): Integer; inline;
begin
  Result := ((((WK * 64 + BK) * 64 + WQ) * 64 + BR) * 2 + STM);
end;

function GetKQKRSetup(const P: TPosition; out WK, BK, WQ, BR, STM: Integer;
                      out QueenIsWhite: Boolean): Boolean;
var
  S, WKing, BKing, WQsq, WRsq, BQsq, BRsq: Integer;
  CWK, CBK, CWQ, CWR, CBQ, CBR: Integer;
  Extra: Boolean;
begin
  Result := False;
  WKing := -1; BKing := -1; WQsq := -1; WRsq := -1; BQsq := -1; BRsq := -1;
  CWK := 0; CBK := 0; CWQ := 0; CWR := 0; CBQ := 0; CBR := 0;
  Extra := False;
  for S := 0 to 63 do
    case P.Board[S] of
      pcWK: begin Inc(CWK); WKing := S; end;
      pcBK: begin Inc(CBK); BKing := S; end;
      pcWQ: begin Inc(CWQ); WQsq := S; end;
      pcWR: begin Inc(CWR); WRsq := S; end;
      pcBQ: begin Inc(CBQ); BQsq := S; end;
      pcBR: begin Inc(CBR); BRsq := S; end;
      pcEmpty: ;
    else
      Extra := True;
    end;
  if Extra or (CWK <> 1) or (CBK <> 1) then Exit;

  QueenIsWhite := (CWQ = 1) and (CBR = 1) and (CWR = 0) and (CBQ = 0);
  if not QueenIsWhite then
    if (CWQ <> 0) or (CBR <> 0) or (CWR <> 1) or (CBQ <> 1) then Exit;

  if QueenIsWhite then
  begin
    WK := WKing;  BK := BKing;  WQ := WQsq;  BR := BRsq;
    STM := Ord(P.Side);
  end
  else
  begin
    // 180 derece ayna: vezir tarafı daima normalize beyaz olur.
    WK := 63 - BKing;  BK := 63 - WKing;
    WQ := 63 - BQsq;   BR := 63 - WRsq;
    STM := Ord(Opp(P.Side));
  end;
  Result := True;
end;

// İşaretli DTM: +beyaz kazanır, -siyah kazanır, 0 kesin sonuç yok.
function SignedEndgameValue(const P: TPosition; out Kind: TTableKind): Integer;
var
  WK, BK, PS, STM: Integer;
  WA, QW: Boolean;
  WQ, BR: Integer;
begin
  Result := 0;
  Kind := tkNone;
  InitBasicTables;
  if not BasicReady then Exit;

  if GetKQKRSetup(P, WK, BK, WQ, BR, STM, QW) then
  begin
    Kind := tkKQKR;
    Result := KQKRData[KQKRIndex(WK, BK, WQ, BR, STM)];
    if Result >= 128 then Dec(Result, 256);
    if not QW then Result := -Result;
    Exit;
  end;

  if GetSingleSetup(P, WK, BK, PS, WA, Kind) then
  begin
    STM := KBNNormalizedSTM(P, WA);
    if Kind = tkKQ then Result := KQData[SingleIndex(WK, BK, PS, STM)]
    else Result := KRData[SingleIndex(WK, BK, PS, STM)];
    if not WA then Result := -Result;
  end;
end;

// Vezir tarafı gözünden işaretli DTM: +vezir kazanır, -kale kazanır.
function KQKRValue(const P: TPosition; out QueenIsWhite: Boolean): Integer;
var
  WK, BK, WQ, BR, STM: Integer;
begin
  Result := 0;
  QueenIsWhite := False;
  InitBasicTables;
  if not BasicReady then Exit;
  if not GetKQKRSetup(P, WK, BK, WQ, BR, STM, QueenIsWhite) then Exit;
  Result := KQKRData[KQKRIndex(WK, BK, WQ, BR, STM)];
  if Result >= 128 then Dec(Result, 256);
end;

function TryKQKRMove(const P: TPosition; out Best: TMove;
                     out Score: Integer): Boolean;
var
  L: TMoveList;
  Q: TPosition;
  i, V, After, MoverVal, BestVal: Integer;
  QueenIsWhite, QueenToMove, MoverIsWinner: Boolean;
  WK, BK, WQ, BR, STM: Integer;
  Kind: TTableKind;
begin
  Result := False;
  InitBasicTables;
  if not BasicReady then Exit;
  // Yalnızca gerçek K+V – K+R pozisyonlarında kullanılır. Eskiden V=0 dönen
  // her pozisyonda (yani tüm normal oyunlarda) ilk legal hamle "en iyi" sanılıyor
  // ve açılışta a-piyonu gibi saçma hamleler oynanıyordu.
  if not GetKQKRSetup(P, WK, BK, WQ, BR, STM, QueenIsWhite) then Exit;
  V := KQKRData[KQKRIndex(WK, BK, WQ, BR, STM)];
  if V >= 128 then Dec(V, 256);

  L := GenLegal(P);
  if L.Count = 0 then Exit;

  QueenToMove := (P.Side = coWhite) = QueenIsWhite;

  if V = 0 then
  begin
    // Beraberlik konumunu sığ aramaya bırakırsak kale tarafı kaybedebiliyor.
    // Tabloyla beraberliği koruyan (kaybettirmeyen) hamleyi seç.
    for i := 0 to L.Count - 1 do
    begin
      Q := P;
      ApplyMove(Q, L.Items[i]);
      After := SignedEndgameValue(Q, Kind);
      if not QueenIsWhite then After := -After;    // vezir tarafı gözünden
      if QueenToMove then MoverVal := After else MoverVal := -After;
      if MoverVal >= 0 then
      begin
        Best := L.Items[i];
        Score := 0;
        Result := True;
        Exit;
      end;
    end;
    Exit;  // kaybettirmeyen hamle yoksa normal aramaya dön
  end;

  MoverIsWinner := (V > 0) = QueenToMove;
  if MoverIsWinner then BestVal := High(Integer) else BestVal := Low(Integer);

  for i := 0 to L.Count - 1 do
  begin
    Q := P;
    ApplyMove(Q, L.Items[i]);
    After := SignedEndgameValue(Q, Kind);        // +beyaz / -siyah
    if not QueenIsWhite then After := -After;    // vezir tarafı gözünden
    if QueenToMove then MoverVal := After else MoverVal := -After;

    if MoverIsWinner then
    begin
      if (MoverVal > 0) and (MoverVal < BestVal) then
      begin
        BestVal := MoverVal;
        Best := L.Items[i];
      end;
    end
    else if MoverVal > BestVal then   // kaybeden taraf en uzun direnişi seçer
    begin
      BestVal := MoverVal;
      Best := L.Items[i];
    end;
  end;

  if (BestVal = High(Integer)) or (BestVal = Low(Integer)) then Exit;
  if (V > 0) = QueenToMove then Score := MATE - Abs(V)
  else Score := -(MATE - Abs(V));
  Result := True;
end;

function TryBasicTableMove(const P: TPosition; out Best: TMove;
                           out Score: Integer): Boolean;
var
  L: TMoveList;
  Q: TPosition;
  i, Dtm, After, BestVal: Integer;
  WhiteAttacker, AttackerToMove, WA2: Boolean;
  Kind, Kind2: TTableKind;
begin
  Result := False;
  Dtm := TablePositionDtm(P, WhiteAttacker, Kind);
  if (Dtm <= 0) or (Kind = tkNone) then Exit;  // tabloda yok veya zorla mat yok

  L := GenLegal(P);
  if L.Count = 0 then Exit;

  AttackerToMove := (P.Side = coWhite) = WhiteAttacker;
  if AttackerToMove then BestVal := High(Integer) else BestVal := -1;

  for i := 0 to L.Count - 1 do
  begin
    Q := P;
    ApplyMove(Q, L.Items[i]);
    After := TablePositionDtm(Q, WA2, Kind2);
    if (After < 0) or (WA2 <> WhiteAttacker) or (Kind2 <> Kind) then
      After := 0;  // taş alındıysa artık kesin bitiş değil

    if AttackerToMove then
    begin
      if (After > 0) and (After < BestVal) then
      begin
        BestVal := After;
        Best := L.Items[i];
      end;
    end
    else if After > BestVal then
    begin
      BestVal := After;
      Best := L.Items[i];
    end;
  end;

  if (BestVal = High(Integer)) or (BestVal < 0) then Exit;
  if AttackerToMove then Score := MATE - BestVal
  else Score := -(MATE - BestVal);
  Result := True;
end;

function NextRandom64: QWord;
begin
  ZobSeed := ZobSeed xor (ZobSeed shl 13);
  ZobSeed := ZobSeed xor (ZobSeed shr 7);
  ZobSeed := ZobSeed xor (ZobSeed shl 17);
  Result := ZobSeed;
end;

procedure InitZobrist;
var
  Pc, S, C: Integer;
begin
  if ZobInit then Exit;
  ZobSeed := QWord($9E3779B97F4A7C15);
  for Pc := 0 to 11 do
    for S := 0 to 63 do
      ZobPiece[Pc, S] := NextRandom64;
  ZobSide := NextRandom64;
  for C := 0 to 15 do
    ZobCastle[C] := NextRandom64;
  for S := 0 to 63 do
    ZobEP[S] := NextRandom64;
  ZobInit := True;
end;

function PSTIndex(Sq: Integer; Color: TColor): Integer;
var
  R, F: Integer;
begin
  R := RankOf(Sq);
  F := FileOf(Sq);
  if Color = coBlack then R := 7 - R;
  Result := (7 - R) * 8 + F;
end;

function PSTValue(Kind, Sq: Integer; Color: TColor; EndGame: Boolean): Integer;
var
  Idx: Integer;
begin
  Idx := PSTIndex(Sq, Color);
  case Kind of
    PK_PAWN: Result := PST_Pawn[Idx];
    PK_KNIGHT: Result := PST_Knight[Idx];
    PK_BISHOP: Result := PST_Bishop[Idx];
    PK_ROOK: Result := PST_Rook[Idx];
    PK_QUEEN: Result := PST_Queen[Idx];
    PK_KING: if EndGame then Result := PST_KingEG[Idx]
             else Result := PST_KingMG[Idx];
  else
    Result := 0;
  end;
end;

function EvaluateBase(const P: TPosition; out EndGame: Boolean): Integer;
var
  S, K, Score, Total, F, R, T, T0, T1, KF, KR, Shield, OpenCnt: Integer;
  WMat, BMat, Dist, WKF, WKR, BKF, BKR: Integer;
  WBColor, BBColor, Edge, BestCorner, i: Integer;
  RooksW, RooksB, QueensW, QueensB, KnightsW, KnightsB: Integer;
  WNightSq, BNightSq, KnightDist: Integer;
  WRookSq, BRookSq: TSquare;
  PureKRW, PureKRB, PureKRNW, PureKRNB: Boolean;
  pc: TPiece;
  BishopsW, BishopsB: Integer;
  WKingSq, BKingSq: TSquare;
  WQueenSq, BQueenSq: TSquare;
  DevelopedW, DevelopedB, CenterPawnsW, CenterPawnsB: Integer;
  IsPassed: Boolean;
  WPawnCnt, BPawnCnt: array[-1..8] of Integer;
  WPawnMax: array[-1..8] of Integer;
  BPawnMin: array[-1..8] of Integer;
begin
  // Ölü konumlarda motor malzeme üstünlüğünü "kazanç" sanmasın.
  if IsInsufficientMaterial(P) then
  begin
    EndGame := True;
    Exit(0);
  end;

  for F := -1 to 8 do
  begin
    WPawnCnt[F] := 0;  BPawnCnt[F] := 0;
    WPawnMax[F] := -1; BPawnMin[F] := 8;
  end;
  WKingSq := 0;
  BKingSq := 0;
  Total := 0;
  WMat := 0;
  BMat := 0;
  WBColor := 0;
  BBColor := 0;
  RooksW := 0;  RooksB := 0;  QueensW := 0;  QueensB := 0;
  KnightsW := 0;  KnightsB := 0;
  WNightSq := 0;  BNightSq := 0;
  WRookSq := 0;  BRookSq := 0;
  WQueenSq := 0;  BQueenSq := 0;
  DevelopedW := 0;  DevelopedB := 0;
  CenterPawnsW := 0;  CenterPawnsB := 0;

  for S := 0 to 63 do
  begin
    pc := P.Board[S];
    if pc = pcEmpty then Continue;
    K := KindOf(pc);
    Inc(Total, Val[K]);
    if ColorOf(pc) = coWhite then Inc(WMat, Val[K]) else Inc(BMat, Val[K]);
    F := FileOf(S);
    R := RankOf(S);
    if K = PK_BISHOP then
    begin
      if ColorOf(pc) = coWhite then WBColor := WBColor or (1 shl ((F + R) and 1))
      else BBColor := BBColor or (1 shl ((F + R) and 1));
    end
    else if K = PK_KNIGHT then
    begin
      if ColorOf(pc) = coWhite then
      begin Inc(KnightsW); WNightSq := S; end
      else
      begin Inc(KnightsB); BNightSq := S; end;
    end
    else if K = PK_ROOK then
    begin
      if ColorOf(pc) = coWhite then
      begin Inc(RooksW); WRookSq := S; end
      else
      begin Inc(RooksB); BRookSq := S; end;
    end
    else if K = PK_QUEEN then
    begin
      if ColorOf(pc) = coWhite then Inc(QueensW) else Inc(QueensB);
    end;
    if ColorOf(pc) = coWhite then
    begin
      if K = PK_PAWN then
      begin
        Inc(WPawnCnt[F]);
        if R > WPawnMax[F] then WPawnMax[F] := R;
      end
      else if K = PK_KING then WKingSq := S;
    end
    else
    begin
      if K = PK_PAWN then
      begin
        Inc(BPawnCnt[F]);
        if R < BPawnMin[F] then BPawnMin[F] := R;
      end
      else if K = PK_KING then BKingSq := S;
    end;
  end;
  EndGame := Total < 3600;

  Score := 0;
  BishopsW := 0;
  BishopsB := 0;
  for S := 0 to 63 do
  begin
    pc := P.Board[S];
    if pc = pcEmpty then Continue;
    K := KindOf(pc);
    F := FileOf(S);
    R := RankOf(S);

    if ColorOf(pc) = coWhite then
    begin
      Score := Score + Val[K] + PSTValue(K, S, coWhite, EndGame);
      if K = PK_BISHOP then Inc(BishopsW);
      if K in [PK_KNIGHT, PK_BISHOP] then
        if R >= 2 then Inc(DevelopedW);   // arka sıradan çıkmış hafif taş
      if K = PK_QUEEN then WQueenSq := S;
      if (K = PK_PAWN) and (F in [3, 4]) and (R in [3, 4]) then
        Inc(CenterPawnsW);

      if K = PK_PAWN then
      begin
        if WPawnCnt[F] > 1 then Dec(Score, 12);                 // çift piyon
        if (WPawnMax[F - 1] < 0) and (WPawnMax[F + 1] < 0) then
          Dec(Score, 15);                                       // izole piyon
        T0 := F - 1; if T0 < 0 then T0 := 0;
        T1 := F + 1; if T1 > 7 then T1 := 7;
        IsPassed := True;
        for T := T0 to T1 do
          if BPawnMin[T] < R then IsPassed := False;
        if IsPassed then Inc(Score, 8 + R * 5);                 // geçmiş piyon
      end;

      if K = PK_ROOK then
      begin
        if WPawnCnt[F] = 0 then                                // açık/y yarım açık
        begin
          if BPawnCnt[F] = 0 then Inc(Score, 20) else Inc(Score, 10);
        end;
        if R = 6 then Inc(Score, 20);                          // 7. sıra kale
      end;
    end
    else
    begin
      Score := Score - (Val[K] + PSTValue(K, S, coBlack, EndGame));
      if K = PK_BISHOP then Inc(BishopsB);
      if K in [PK_KNIGHT, PK_BISHOP] then
        if R <= 5 then Inc(DevelopedB);
      if K = PK_QUEEN then BQueenSq := S;
      if (K = PK_PAWN) and (F in [3, 4]) and (R in [3, 4]) then
        Inc(CenterPawnsB);

      if K = PK_PAWN then
      begin
        if BPawnCnt[F] > 1 then Inc(Score, 12);
        if (BPawnMin[F - 1] = 8) and (BPawnMin[F + 1] = 8) then
          Inc(Score, 15);
        T0 := F - 1; if T0 < 0 then T0 := 0;
        T1 := F + 1; if T1 > 7 then T1 := 7;
        IsPassed := True;
        for T := T0 to T1 do
          if WPawnMax[T] > R then IsPassed := False;
        if IsPassed then Dec(Score, 8 + (7 - R) * 5);
      end;

      if K = PK_ROOK then
      begin
        if BPawnCnt[F] = 0 then
        begin
          if WPawnCnt[F] = 0 then Dec(Score, 20) else Dec(Score, 10);
        end;
        if R = 1 then Dec(Score, 20);
      end;
    end;
  end;

  // Açılış/orta oyun konumsal terimleri. Oyun sonunda PST ve mat
  // yönlendirmesi zaten doğru yönlendirdiği için bu terimler kapatılır.
  if not EndGame then
  begin
    Inc(Score, (DevelopedW - DevelopedB) * 12);     // hafif taş gelişimi
    Inc(Score, (CenterPawnsW - CenterPawnsB) * 8);  // merkez piyonları

    // Hafif taşlar gelişmeden veziri merkeze çıkarmak genelde zaman kaybıdır.
    if QueensW > 0 then
    begin
      F := FileOf(WQueenSq); R := RankOf(WQueenSq);
      if (F in [3, 4]) and (R in [3, 4]) and (DevelopedW < 2) then
        Dec(Score, 25);
    end;
    if QueensB > 0 then
    begin
      F := FileOf(BQueenSq); R := RankOf(BQueenSq);
      if (F in [3, 4]) and (R in [3, 4]) and (DevelopedB < 2) then
        Inc(Score, 25);
    end;
  end;

  if BishopsW >= 2 then Inc(Score, 30);
  if BishopsB >= 2 then Dec(Score, 30);

  // Beyaz kral güvenliği: kalkan piyonlar ve açık dosyalar
  KF := FileOf(WKingSq); KR := RankOf(WKingSq);
  Shield := 0; OpenCnt := 0;
  T0 := KF - 1; if T0 < 0 then T0 := 0;
  T1 := KF + 1; if T1 > 7 then T1 := 7;
  for F := T0 to T1 do
  begin
    if WPawnMax[F] > KR then Inc(Shield);
    if WPawnCnt[F] = 0 then Inc(OpenCnt);
  end;
  Inc(Score, Shield * 10 - OpenCnt * 12);

  // Siyah kral güvenliği
  KF := FileOf(BKingSq); KR := RankOf(BKingSq);
  Shield := 0; OpenCnt := 0;
  T0 := KF - 1; if T0 < 0 then T0 := 0;
  T1 := KF + 1; if T1 > 7 then T1 := 7;
  for F := T0 to T1 do
  begin
    if BPawnMin[F] < KR then Inc(Shield);
    if BPawnCnt[F] = 0 then Inc(OpenCnt);
  end;
  Dec(Score, Shield * 10 - OpenCnt * 12);

  // Oyun sonu mat yönlendirmesi: güçlü şah rakibe yaklaşır, zayıf şah
  // kenara/köşeye itilir. Fil bitişlerinde filin rengine uygun köşe hedeftir.
  if EndGame then
  begin
    WKF := FileOf(WKingSq); WKR := RankOf(WKingSq);
    BKF := FileOf(BKingSq); BKR := RankOf(BKingSq);
    Dist := Abs(WKF - BKF);
    T := Abs(WKR - BKR);
    if T > Dist then Dist := T;
    if Dist > 14 then Dist := 14;

    // Saf K+Kale bitişinde klasik PST değerlendirmesi zaten matı buluyor;
    // ek yönlendirme bu bitişte gtköşe döngüsüne yol açıyor.
    PureKRW := (RooksW = 1) and (QueensW = 0) and (KnightsW = 0) and
               (BishopsW = 0) and (BMat = 0);
    PureKRB := (RooksB = 1) and (QueensB = 0) and (KnightsB = 0) and
               (BishopsB = 0) and (WMat = 0);

    // Chenard tarzı "mop-up": K+R+A vs K bitişinde kale ve at zayıf şaha
    // yaklaştıkça mat yaklaşır. Tablo boş bıraktığı konumlarda aramaya yön verir.
    PureKRNW := (RooksW = 1) and (KnightsW = 1) and (QueensW = 0) and
                (BishopsW = 0) and (RooksB = 0) and (KnightsB = 0) and
                (BishopsB = 0) and (QueensB = 0) and (BMat = 0);
    PureKRNB := (RooksB = 1) and (KnightsB = 1) and (QueensB = 0) and
                (BishopsB = 0) and (RooksW = 0) and (KnightsW = 0) and
                (BishopsW = 0) and (QueensW = 0) and (WMat = 0);

    if WMat > BMat + 250 then
    begin
      if not PureKRW then
      begin
        Inc(Score, (14 - Dist) * 15);

        // Siyah şahın kenara uzaklığı (merkez 6, köşe 0)
        if BKF < 7 - BKF then Edge := BKF else Edge := 7 - BKF;
        if BKR < 7 - BKR then T := BKR else T := 7 - BKR;
        Inc(Edge, T);
        Inc(Score, (6 - Edge) * 25);

        if WBColor <> 0 then
        begin
          BestCorner := 16;
          for i := 0 to 3 do
            if (WBColor and (1 shl ((CornerFile[i] + CornerRank[i]) and 1))) <> 0 then
            begin
              T := Abs(BKF - CornerFile[i]) + Abs(BKR - CornerRank[i]);
              if T < BestCorner then BestCorner := T;
            end;
          if BestCorner < 16 then Inc(Score, (14 - BestCorner) * 8);

          // K+F+A: şah filin erişebildiği köşeye sürülmelidir. Stockfish'teki
          // gibi fil a1 rengindeyse a1/h8, değilse a8/h1 eksenine göre yönlendir.
          if ((WBColor and (WBColor - 1)) = 0) and (KnightsW = 1) and
             (BishopsW = 1) then
          begin
            if (WBColor and 1) <> 0 then T := Abs(7 - BKF - BKR)
            else T := Abs(BKF - BKR);
            Inc(Score, T * 200);
            KnightDist := Abs(FileOf(WNightSq) - BKF) + Abs(RankOf(WNightSq) - BKR);
            Inc(Score, (14 - KnightDist) * 4);
          end;
        end;

        if PureKRNW then
        begin
          // Chenard: kale/vezir yakınlığı tam, hafif taş yakınlığı 1/12 ağırlıkta.
          T := Abs(FileOf(WRookSq) - BKF) + Abs(RankOf(WRookSq) - BKR);
          Inc(Score, (14 - T) * 6);
          KnightDist := Abs(FileOf(WNightSq) - BKF) + Abs(RankOf(WNightSq) - BKR);
          Inc(Score, (14 - KnightDist) * 2);
        end;
      end;
    end
    else if BMat > WMat + 250 then
    begin
      if not PureKRB then
      begin
        Dec(Score, (14 - Dist) * 15);

        // Beyaz şahın kenara uzaklığı
        if WKF < 7 - WKF then Edge := WKF else Edge := 7 - WKF;
        if WKR < 7 - WKR then T := WKR else T := 7 - WKR;
        Inc(Edge, T);
        Dec(Score, (6 - Edge) * 25);

        if BBColor <> 0 then
        begin
          BestCorner := 16;
          for i := 0 to 3 do
            if (BBColor and (1 shl ((CornerFile[i] + CornerRank[i]) and 1))) <> 0 then
            begin
              T := Abs(WKF - CornerFile[i]) + Abs(WKR - CornerRank[i]);
              if T < BestCorner then BestCorner := T;
            end;
          if BestCorner < 16 then Dec(Score, (14 - BestCorner) * 8);

          if ((BBColor and (BBColor - 1)) = 0) and (KnightsB = 1) and
             (BishopsB = 1) then
          begin
            if (BBColor and 1) <> 0 then T := Abs(7 - WKF - WKR)
            else T := Abs(WKF - WKR);
            Dec(Score, T * 200);
            KnightDist := Abs(FileOf(BNightSq) - WKF) + Abs(RankOf(BNightSq) - WKR);
            Dec(Score, (14 - KnightDist) * 4);
          end;
        end;

        if PureKRNB then
        begin
          T := Abs(FileOf(BRookSq) - WKF) + Abs(RankOf(BRookSq) - WKR);
          Dec(Score, (14 - T) * 6);
          KnightDist := Abs(FileOf(BNightSq) - WKF) + Abs(RankOf(BNightSq) - WKR);
          Dec(Score, (14 - KnightDist) * 2);
        end;
      end;
    end;
  end;

  Result := Score;  // beyaz perspektifi
end;

function EvaluatePosition(const P: TPosition): Integer;
var
  EndGame: Boolean;
begin
  Result := EvaluateBase(P, EndGame);
end;

// Yaprak değerlendirmesi: Negamax zaten LegalCount'u üretmiş olduğundan
// mobility puanı ekstra maliyetsiz eklenir. Sonuç hamle sırasındaki
// tarafın perspektifindedir.
function EvaluateLeaf(const P: TPosition; LegalCount: Integer): Integer;
var
  EndGame: Boolean;
  Weight, Bonus: Integer;
begin
  Result := EvaluateBase(P, EndGame);  // beyaz perspektifi
  if P.Side = coBlack then Result := -Result;  // hamle sırasındaki taraf
  if EndGame then Weight := MOBILITY_EG else Weight := MOBILITY_MG;

  Bonus := Weight * LegalCount;        // o tarafın hareket alanı
  if Bonus > Val[PK_PAWN] then Bonus := Val[PK_PAWN];  // en fazla 1 piyon
  Result := Result + Bonus;
end;

function PieceIdx(pc: TPiece): Integer;
begin
  if ColorOf(pc) = coWhite then Result := KindOf(pc) - 1
  else Result := 6 + KindOf(pc) - 1;   // 0..5 beyaz, 6..11 siyah
end;

function PositionHash(const P: TPosition): QWord;
var
  S: Integer;
  pc: TPiece;
begin
  Result := 0;
  for S := 0 to 63 do
  begin
    pc := P.Board[S];
    if pc <> pcEmpty then Result := Result xor ZobPiece[PieceIdx(pc), S];
  end;
  if P.Side = coBlack then Result := Result xor ZobSide;
  Result := Result xor ZobCastle[P.Castle and 15];
  if (P.EP >= 0) and (P.EP <= 63) then Result := Result xor ZobEP[P.EP];
end;

function TTIndex(const Key: QWord): Integer;
begin
  Result := Integer(Key and QWord(TT_MASK));
end;

function SameMove(const A, B: TMove): Boolean;
begin
  Result := (A.FromSq = B.FromSq) and (A.ToSq = B.ToSq) and (A.Flag = B.Flag);
end;

function MoveOrderScore(const P: TPosition; const M: TMove; Ply: Integer): Integer;
var
  Victim, Attacker, Idx: Integer;
begin
  Result := 0;
  if TTBestValid and SameMove(M, TTBest) then Inc(Result, 12000);
  if M.Captured <> pcEmpty then
  begin
    Victim := Val[KindOf(M.Captured)];
    Attacker := Val[KindOf(P.Board[M.FromSq])];
    Result := 10000 + Victim * 10 - Attacker;
  end
  else
  begin
    Idx := Ply;
    if Idx > 63 then Idx := 63;
    if SameMove(M, Killer1[Idx]) then Result := 9000
    else if SameMove(M, Killer2[Idx]) then Result := 8000
    else Result := History[M.FromSq, M.ToSq];
  end;
  case M.Flag of
    mfPromoQ: Result := Result + 9000;
    mfPromoR: Result := Result + 5000;
    mfPromoB: Result := Result + 3000;
    mfPromoN: Result := Result + 2000;
  end;
end;

procedure OrderMoves(var L: TMoveList; const P: TPosition; Ply: Integer);
var
  i, j, Best: Integer;
  Tmp: TMove;
begin
  for i := 0 to L.Count - 2 do
  begin
    Best := i;
    for j := i + 1 to L.Count - 1 do
      if MoveOrderScore(P, L.Items[j], Ply) > MoveOrderScore(P, L.Items[Best], Ply) then
        Best := j;
    if Best <> i then
    begin
      Tmp := L.Items[i];
      L.Items[i] := L.Items[Best];
      L.Items[Best] := Tmp;
    end;
  end;
end;

// Quiescence: yaprakta takas/terfi hamleleri "sessiz" hale gelene kadar okunur.
// Şah durumunda tüm legal kaçınmalar aranır. QDepth sonsuz zincirleri engeller.
function Quiesce(var P: TPosition; Alpha, Beta, Ply, QDepth: Integer;
                 var Nodes: Int64): Integer;
var
  L, Capt: TMoveList;
  P2: TPosition;
  i, Stand, Score, Best: Integer;
  InChk: Boolean;
begin
  Inc(Nodes);
  if (Nodes and 1023) = 0 then
    if AbortFlag or (GetTickCount64 > StartTicks + TimeLimit) then
      raise ESearchAbort.Create('search stopped');

  if P.Halfmove >= 100 then Exit(0);

  TTBestValid := False;   // quiescence için TT hamle önerisi yok

  L := GenLegal(P);
  if L.Count = 0 then
  begin
    if InCheck(P, P.Side) then Result := -MATE + Ply
    else Result := 0;
    Exit;
  end;

  InChk := InCheck(P, P.Side);
  if (QDepth >= 8) and (not InChk) then
    Exit(EvaluateLeaf(P, L.Count));

  if InChk then
    Best := -INF
  else
  begin
    Stand := EvaluateLeaf(P, L.Count);
    Best := Stand;
    if Stand >= Beta then Exit(Stand);
    if Stand > Alpha then Alpha := Stand;
  end;

  if InChk then
    Capt := L
  else
  begin
    Capt.Count := 0;
    for i := 0 to L.Count - 1 do
      if (L.Items[i].Captured <> pcEmpty) or
         (L.Items[i].Flag in [mfPromoQ, mfPromoR, mfPromoB, mfPromoN]) then
      begin
        Capt.Items[Capt.Count] := L.Items[i];
        Inc(Capt.Count);
      end;
    if Capt.Count = 0 then Exit(Best);
    OrderMoves(Capt, P, Ply);
  end;

  for i := 0 to Capt.Count - 1 do
  begin
    P2 := P;
    ApplyMove(P2, Capt.Items[i]);
    Score := -Quiesce(P2, -Beta, -Alpha, Ply + 1, QDepth + 1, Nodes);
    if Score > Best then Best := Score;
    if Score > Alpha then Alpha := Score;
    if Alpha >= Beta then Break;
  end;
  Result := Best;
end;

// Null-move pruning için: zugzwang riskine girmemek adına piyon/şah dışında
// taşı olan tarafa izin verilir.
function HasNonPawnMaterial(const P: TPosition; C: TColor): Boolean;
var
  S: Integer;
  pc: TPiece;
begin
  Result := False;
  for S := 0 to 63 do
  begin
    pc := P.Board[S];
    if (pc = pcEmpty) or (ColorOf(pc) <> C) then Continue;
    if KindOf(pc) in [PK_KNIGHT, PK_BISHOP, PK_ROOK, PK_QUEEN] then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function Negamax(var P: TPosition; Depth, Ply, Alpha, Beta, Ext: Integer;
                 var Nodes: Int64): Integer;
var
  L: TMoveList;
  P2: TPosition;
  i, Score, Best, ChildDepth, ChildExt, Idx, TTIdx, Red: Integer;
  HashKey: QWord;
  AlphaOrig: Integer;
  BestMove: TMove;
  Flag: TTTFlag;
  InChk: Boolean;
begin
  Inc(Nodes);
  if (Nodes and 1023) = 0 then
    if AbortFlag or (GetTickCount64 > StartTicks + TimeLimit) then
      raise ESearchAbort.Create('search stopped');

  if P.Halfmove >= 100 then Exit(0);

  HashKey := PositionHash(P);
  TTIdx := TTIndex(HashKey);
  TTBestValid := (TT[TTIdx].Flag <> tfNone) and (TT[TTIdx].Key = HashKey) and
                 (TT[TTIdx].Best.FromSq <> TT[TTIdx].Best.ToSq);
  if TTBestValid then TTBest := TT[TTIdx].Best;

  // Transposition table kontrolü
  if (TT[TTIdx].Flag <> tfNone) and (TT[TTIdx].Key = HashKey) and
     (TT[TTIdx].Depth >= Depth) and (Abs(TT[TTIdx].Score) < MATE - 100) then
  begin
    case TT[TTIdx].Flag of
      tfExact: Exit(TT[TTIdx].Score);
      tfLower: if TT[TTIdx].Score >= Beta then Exit(TT[TTIdx].Score);
      tfUpper: if TT[TTIdx].Score <= Alpha then Exit(TT[TTIdx].Score);
    end;
  end;

  AlphaOrig := Alpha;

  L := GenLegal(P);
  if L.Count = 0 then
  begin
    if InCheck(P, P.Side) then Result := -MATE + Ply
    else Result := 0;
    Exit;
  end;

  if Depth <= 0 then Exit(Quiesce(P, Alpha, Beta, Ply, 0, Nodes));

  // Null-move pruning: sırayı rakibe verip kısa aramayla üst sınır elde et.
  // Şah durumunda, mat aralığında veya sadece piyon/şah kalmışsa atlanır.
  if (Depth >= 3) and (Beta < MATE - 100) and
     (not InCheck(P, P.Side)) and HasNonPawnMaterial(P, P.Side) then
  begin
    P2 := P;
    P2.Side := Opp(P.Side);
    P2.EP := -1;
    if Depth >= 6 then Red := 3 else Red := 2;
    Score := -Negamax(P2, Depth - Red, Ply + 1, -Beta, -Beta + 1, 0, Nodes);
    if Score >= Beta then Exit(Beta);
  end;

  OrderMoves(L, P, Ply);
  InChk := InCheck(P, P.Side);
  Best := -INF;
  BestMove := L.Items[0];
  for i := 0 to L.Count - 1 do
  begin
    P2 := P;
    ApplyMove(P2, L.Items[i]);
    ChildDepth := Depth - 1;
    ChildExt := Ext;
    if (Ext > 0) and InCheck(P2, P2.Side) then
    begin
      Inc(ChildDepth);    // şah genişletmesi
      Dec(ChildExt);
    end;

    // Geç hamle indirimi (LMR): ilk üç hamleden sonraki sessiz hamleler önce
    // daraltılmış derinlikle aranır; faydalı görünürse tam derinlikte yeniden
    // aranır. Şah durumlarında indirim yapılmaz.
    if (i >= 3) and (ChildDepth >= 2) and (not InChk) and
       (L.Items[i].Captured = pcEmpty) and (L.Items[i].Flag = mfNormal) and
       (not InCheck(P2, P2.Side)) then
    begin
      Score := -Negamax(P2, ChildDepth - 1, Ply + 1, -Alpha - 1, -Alpha,
                        ChildExt, Nodes);
      if Score > Alpha then
        Score := -Negamax(P2, ChildDepth, Ply + 1, -Beta, -Alpha, ChildExt, Nodes);
    end
    else
      Score := -Negamax(P2, ChildDepth, Ply + 1, -Beta, -Alpha, ChildExt, Nodes);

    if Score > Best then
    begin
      Best := Score;
      BestMove := L.Items[i];
    end;
    if Score > Alpha then Alpha := Score;
    if Alpha >= Beta then
    begin
      if L.Items[i].Captured = pcEmpty then
      begin
        Idx := Ply;
        if Idx > 63 then Idx := 63;
        if not SameMove(L.Items[i], Killer1[Idx]) then
        begin
          Killer2[Idx] := Killer1[Idx];
          Killer1[Idx] := L.Items[i];
        end;
        Inc(History[L.Items[i].FromSq, L.Items[i].ToSq], Ply * Ply + 1);
      end;
      Break;
    end;
  end;
  Result := Best;

  // Sonucu TT'ye yaz
  if Best <= AlphaOrig then Flag := tfUpper
  else if Best >= Beta then Flag := tfLower
  else Flag := tfExact;

  if (TT[TTIdx].Flag = tfNone) or (TT[TTIdx].Key <> HashKey) or
     (Depth >= TT[TTIdx].Depth) then
  begin
    TT[TTIdx].Key := HashKey;
    TT[TTIdx].Score := Best;
    TT[TTIdx].Depth := Depth;
    TT[TTIdx].Best := BestMove;
    TT[TTIdx].Flag := Flag;
  end;
end;

function FindBestMove(const P: TPosition; MaxDepth, MaxTimeMs: Integer;
                      out R: TSearchResult): Boolean;
var
  Root: TMoveList;
  P2: TPosition;
  i, j, d, Score, Alpha, BestScore, BestIdx: Integer;
  Nodes: Int64;
  Complete: Boolean;
  BestMove, TmpMove: TMove;
  Scored: array[0..255] of TScoredMove;
  Cur: TScoredMove;
begin
  FillChar(R, SizeOf(R), 0);
  Result := False;
  Root := GenLegal(P);
  if Root.Count = 0 then Exit;

  InitZobrist;

  // K+F+A, K+V, K+R ve K+V vs K+R için kesin tablo varsa sığ aramayı atla;
  // DTM'yi en aza indiren hamleyi doğrudan oyna. Tablo yoksa normal arama çalışır.
  if TryBasicTableMove(P, R.Move, R.Score) or
     TryKQKRMove(P, R.Move, R.Score) then
  begin
    R.Nodes := 0;
    R.Depth := 1;
    R.Found := True;
    R.TopCount := 1;
    R.Top[0].Move := R.Move;
    R.Top[0].Score := R.Score;
    Exit(True);
  end;

  // Her arama tablolarını sıfırlar (aynı arama içindeki derinlikler TT'yi paylaşır)
  for i := 0 to 63 do
  begin
    FillChar(Killer1[i], SizeOf(TMove), 0);
    FillChar(Killer2[i], SizeOf(TMove), 0);
  end;
  FillChar(History, SizeOf(History), 0);
  FillChar(TT, SizeOf(TT), 0);
  TTBestValid := False;

  OrderMoves(Root, P, 0);
  AbortFlag := False;
  StartTicks := GetTickCount64;
  TimeLimit := MaxTimeMs;

  // Seçilen derinlikte arama bitince durulur; gereksiz düşünme süresi kullanılmaz.
  for d := 1 to MaxDepth do
  begin
    Nodes := 0;
    Alpha := -INF;
    BestScore := -INF;
    BestIdx := 0;
    BestMove := Root.Items[0];
    Complete := True;
    try
      for i := 0 to Root.Count - 1 do
      begin
        P2 := P;
        ApplyMove(P2, Root.Items[i]);
        Score := -Negamax(P2, d - 1, 1, -INF, -Alpha, 2, Nodes);
        Scored[i].Move := Root.Items[i];
        Scored[i].Score := Score;
        if Score > BestScore then
        begin
          BestScore := Score;
          BestIdx := i;
          BestMove := Root.Items[i];
        end;
        if Score > Alpha then Alpha := Score;
      end;
    except
      on ESearchAbort do Complete := False;
    end;

    if not Complete then Break;

    // En iyi hamleyi sonraki derinlik için öne al
    if BestIdx <> 0 then
    begin
      TmpMove := Root.Items[BestIdx];
      Root.Items[BestIdx] := Root.Items[0];
      Root.Items[0] := TmpMove;
    end;

    // En iyi 5 kök hamlesini puana göre sırala (ekleme sıralaması)
    for i := 1 to Root.Count - 1 do
    begin
      Cur := Scored[i];
      j := i - 1;
      while (j >= 0) and (Scored[j].Score < Cur.Score) do
      begin
        Scored[j + 1] := Scored[j];
        Dec(j);
      end;
      Scored[j + 1] := Cur;
    end;
    if Root.Count < 5 then R.TopCount := Root.Count else R.TopCount := 5;
    for i := 0 to R.TopCount - 1 do
      R.Top[i] := Scored[i];

    R.Move := BestMove;
    R.Score := BestScore;
    R.Nodes := Nodes;
    R.Depth := d;
    R.Found := True;
    Result := True;

    if Abs(BestScore) > MATE - 100 then Break;
    if GetTickCount64 > StartTicks + TimeLimit then Break;
  end;
end;

procedure AbortSearch;
begin
  AbortFlag := True;
end;

end.
