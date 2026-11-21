unit ChessEngine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TPiece = (pcEmpty,
            pcWP, pcWN, pcWB, pcWR, pcWQ, pcWK,
            pcBP, pcBN, pcBB, pcBR, pcBQ, pcBK);

  TColor = (coWhite, coBlack);
  TSquare = 0..63;

  TMoveFlag = (mfNormal, mfCastleK, mfCastleQ, mfEnPassant,
               mfPromoQ, mfPromoR, mfPromoB, mfPromoN);

  TMove = record
    FromSq, ToSq: TSquare;
    Flag: TMoveFlag;
    Captured: TPiece;
  end;

  TMoveList = record
    Items: array[0..255] of TMove;
    Count: Integer;
  end;

  TBoard = array[TSquare] of TPiece;

  TPosition = record
    Board: TBoard;
    Side: TColor;
    Castle: Integer;   // 1 = WK, 2 = WQ, 4 = BK, 8 = BQ
    EP: Integer;       // -1 = yok
    Halfmove: Integer;
    Fullmove: Integer;
  end;

const
  PK_PAWN = 1; PK_KNIGHT = 2; PK_BISHOP = 3;
  PK_ROOK = 4; PK_QUEEN = 5; PK_KING = 6;

function Opp(C: TColor): TColor;
function ColorOf(P: TPiece): TColor;
function KindOf(P: TPiece): Integer;
function PieceChar(P: TPiece): Char;
function FileOf(S: TSquare): Integer;
function RankOf(S: TSquare): Integer;
function SqName(S: TSquare): string;
function NameToSq(const S: string): TSquare;

function GenPseudo(const P: TPosition): TMoveList;
function GenLegal(const P: TPosition): TMoveList;
function IsAttacked(const P: TPosition; Sq: TSquare; By: TColor): Boolean;
function InCheck(const P: TPosition; C: TColor): Boolean;
procedure ApplyMove(var P: TPosition; const M: TMove);
function PositionKey(const P: TPosition): string;
function IsInsufficientMaterial(const P: TPosition): Boolean;

function StartPos: TPosition;
function FENToPos(const FEN: string): TPosition;
function PosToFEN(const P: TPosition): string;

type
  TChessGame = class
  private
    FPos: TPosition;
    FInitialFEN: string;
    FSan: array of string;
    FPosHist: array of TPosition;
    procedure PushHistory(const ASan: string);
  public
    constructor Create;
    procedure Reset;
    procedure SetPosition(const APos: TPosition);
    procedure LoadFEN(const FEN: string);
    function DoMove(const M: TMove): string;
    procedure Undo;
    function CanUndo: Boolean;
    function LegalMoves: TMoveList;
    function LegalFrom(Sq: TSquare): TMoveList;
    function MoveToSAN(const M: TMove): string;
    function GetResult(out Text: string): Boolean;
    function ResultCode: string;
    function IsRepetition: Boolean;
    function FEN: string;
    function InitialFEN: string;
    function SanCount: Integer;
    function SanItem(Index: Integer): string;
    property Pos: TPosition read FPos;
  end;

implementation

const
  KnightDF: array[0..7] of Integer = (1, 2, 2, 1, -1, -2, -2, -1);
  KnightDR: array[0..7] of Integer = (2, 1, -1, -2, -2, -1, 1, 2);
  KingDF: array[0..7] of Integer = (1, 1, 0, -1, -1, -1, 0, 1);
  KingDR: array[0..7] of Integer = (0, 1, 1, 1, 0, -1, -1, -1);
  BishopDF: array[0..3] of Integer = (1, 1, -1, -1);
  BishopDR: array[0..3] of Integer = (1, -1, 1, -1);
  RookDF: array[0..3] of Integer = (1, -1, 0, 0);
  RookDR: array[0..3] of Integer = (0, 0, 1, -1);

function Opp(C: TColor): TColor;
begin
  if C = coWhite then Result := coBlack else Result := coWhite;
end;

function ColorOf(P: TPiece): TColor;
begin
  if Ord(P) <= 6 then Result := coWhite else Result := coBlack;
end;

function KindOf(P: TPiece): Integer;
begin
  if Ord(P) <= 6 then Result := Ord(P)
  else Result := Ord(P) - 6;
end;

function PieceChar(P: TPiece): Char;
const
  Chars = ' PNBRQKpnbrqk';
begin
  Result := Chars[Ord(P) + 1];
end;

function FileOf(S: TSquare): Integer;
begin
  Result := S mod 8;
end;

function RankOf(S: TSquare): Integer;
begin
  Result := S div 8;
end;

function SqName(S: TSquare): string;
begin
  Result := Chr(Ord('a') + FileOf(S)) + IntToStr(RankOf(S) + 1);
end;

function NameToSq(const S: string): TSquare;
var
  F, R: Integer;
  Ch: Char;
begin
  Result := 0;
  if Length(S) < 2 then Exit;
  Ch := S[1];
  if Ch in ['A'..'Z'] then Ch := Chr(Ord(Ch) + 32);
  F := Ord(Ch) - Ord('a');
  R := StrToIntDef(Copy(S, 2, 1), 1) - 1;
  if (F < 0) or (F > 7) or (R < 0) or (R > 7) then Exit;
  Result := R * 8 + F;
end;

function StepSq(S: TSquare; DF, DR: Integer): Integer;
var
  F, R: Integer;
begin
  F := FileOf(S) + DF;
  R := RankOf(S) + DR;
  if (F < 0) or (F > 7) or (R < 0) or (R > 7) then
    Result := -1
  else
    Result := R * 8 + F;
end;

procedure AddMove(var L: TMoveList; F, T: TSquare; Flag: TMoveFlag; Captured: TPiece);
begin
  if L.Count >= Length(L.Items) then Exit;
  L.Items[L.Count].FromSq := F;
  L.Items[L.Count].ToSq := T;
  L.Items[L.Count].Flag := Flag;
  L.Items[L.Count].Captured := Captured;
  Inc(L.Count);
end;

function IsAttacked(const P: TPosition; Sq: TSquare; By: TColor): Boolean;
var
  i, T: Integer;
  pc: TPiece;
  K: Integer;
begin
  Result := False;

  // Piyon saldırıları (beyaz aşağıdan yukarı, siyah yukarıdan aşağıya)
  if By = coWhite then
  begin
    if (RankOf(Sq) > 0) and (FileOf(Sq) > 0) and (P.Board[Sq - 9] = pcWP) then Exit(True);
    if (RankOf(Sq) > 0) and (FileOf(Sq) < 7) and (P.Board[Sq - 7] = pcWP) then Exit(True);
  end
  else
  begin
    if (RankOf(Sq) < 7) and (FileOf(Sq) > 0) and (P.Board[Sq + 7] = pcBP) then Exit(True);
    if (RankOf(Sq) < 7) and (FileOf(Sq) < 7) and (P.Board[Sq + 9] = pcBP) then Exit(True);
  end;

  // At
  for i := 0 to 7 do
  begin
    T := StepSq(Sq, KnightDF[i], KnightDR[i]);
    if T >= 0 then
    begin
      pc := P.Board[T];
      if (pc <> pcEmpty) and (ColorOf(pc) = By) and (KindOf(pc) = PK_KNIGHT) then Exit(True);
    end;
  end;

  // Şah
  for i := 0 to 7 do
  begin
    T := StepSq(Sq, KingDF[i], KingDR[i]);
    if T >= 0 then
    begin
      pc := P.Board[T];
      if (pc <> pcEmpty) and (ColorOf(pc) = By) and (KindOf(pc) = PK_KING) then Exit(True);
    end;
  end;

  // Fil / Kale / Vezir
  for i := 0 to 3 do
  begin
    T := StepSq(Sq, BishopDF[i], BishopDR[i]);
    while T >= 0 do
    begin
      pc := P.Board[T];
      if pc <> pcEmpty then
      begin
        K := KindOf(pc);
        if (ColorOf(pc) = By) and ((K = PK_QUEEN) or (K = PK_BISHOP)) then Exit(True);
        Break;
      end;
      T := StepSq(T, BishopDF[i], BishopDR[i]);
    end;

    T := StepSq(Sq, RookDF[i], RookDR[i]);
    while T >= 0 do
    begin
      pc := P.Board[T];
      if pc <> pcEmpty then
      begin
        K := KindOf(pc);
        if (ColorOf(pc) = By) and ((K = PK_QUEEN) or (K = PK_ROOK)) then Exit(True);
        Break;
      end;
      T := StepSq(T, RookDF[i], RookDR[i]);
    end;
  end;
end;

function InCheck(const P: TPosition; C: TColor): Boolean;
var
  S: TSquare;
  King: TPiece;
begin
  if C = coWhite then King := pcWK else King := pcBK;
  for S := 0 to 63 do
    if P.Board[S] = King then Exit(IsAttacked(P, S, Opp(C)));
  Result := False;
end;

function GenPseudo(const P: TPosition): TMoveList;
var
  L: TMoveList;
  S, T: TSquare;
  i, TT, K: Integer;
  pc: TPiece;
  C, O: TColor;
  Dir, StartRank, PromoRank: Integer;
  Promo: Boolean;

  procedure TryPawnTarget(ToSq: TSquare; Flag: TMoveFlag; Capture: Boolean);
  var
    Cap: TPiece;
    pf: TMoveFlag;
    IsEP: Boolean;
  begin
    Cap := P.Board[ToSq];
    IsEP := False;
    if Capture and (Cap = pcEmpty) and (P.EP = ToSq) then
    begin
      if C = coWhite then Cap := P.Board[ToSq - 8]
      else Cap := P.Board[ToSq + 8];
      IsEP := True;
    end;
    if (not Capture) and (Cap <> pcEmpty) then Exit;
    if Capture and ((Cap = pcEmpty) or (ColorOf(Cap) = C)) then Exit;
    if IsEP then Flag := mfEnPassant;
    if Promo then
    begin
      pf := mfPromoQ; AddMove(L, S, ToSq, pf, Cap);
      pf := mfPromoR; AddMove(L, S, ToSq, pf, Cap);
      pf := mfPromoB; AddMove(L, S, ToSq, pf, Cap);
      pf := mfPromoN; AddMove(L, S, ToSq, pf, Cap);
    end
    else
      AddMove(L, S, ToSq, Flag, Cap);
  end;

begin
  L.Count := 0;
  C := P.Side;
  O := Opp(C);

  for S := 0 to 63 do
  begin
    pc := P.Board[S];
    if (pc = pcEmpty) or (ColorOf(pc) <> C) then Continue;

    case KindOf(pc) of
      PK_PAWN:
        begin
          if C = coWhite then
          begin
            Dir := 8; StartRank := 1; PromoRank := 7;
          end
          else
          begin
            Dir := -8; StartRank := 6; PromoRank := 0;
          end;
          Promo := RankOf(S) + (Dir div 8) = PromoRank;

          TT := S + Dir;
          if (TT >= 0) and (TT < 64) and (P.Board[TT] = pcEmpty) then
            TryPawnTarget(TT, mfNormal, False);

          if (RankOf(S) = StartRank) and (P.Board[S + Dir] = pcEmpty) and
             (P.Board[S + 2 * Dir] = pcEmpty) then
            AddMove(L, S, S + 2 * Dir, mfNormal, pcEmpty);

          if FileOf(S) > 0 then
          begin
            TT := S + Dir - 1;
            if (TT >= 0) and (TT < 64) then TryPawnTarget(TT, mfNormal, True);
          end;
          if FileOf(S) < 7 then
          begin
            TT := S + Dir + 1;
            if (TT >= 0) and (TT < 64) then TryPawnTarget(TT, mfNormal, True);
          end;
        end;

      PK_KNIGHT:
        for i := 0 to 7 do
        begin
          TT := StepSq(S, KnightDF[i], KnightDR[i]);
          if TT >= 0 then
          begin
            T := TT;
            if (P.Board[T] = pcEmpty) or (ColorOf(P.Board[T]) = O) then
              AddMove(L, S, T, mfNormal, P.Board[T]);
          end;
        end;

      PK_KING:
        for i := 0 to 7 do
        begin
          TT := StepSq(S, KingDF[i], KingDR[i]);
          if TT >= 0 then
          begin
            T := TT;
            if (P.Board[T] = pcEmpty) or (ColorOf(P.Board[T]) = O) then
              AddMove(L, S, T, mfNormal, P.Board[T]);
          end;
        end;

      PK_BISHOP, PK_ROOK, PK_QUEEN:
        begin
          K := KindOf(pc);
          if (K = PK_BISHOP) or (K = PK_QUEEN) then
            for i := 0 to 3 do
            begin
              TT := StepSq(S, BishopDF[i], BishopDR[i]);
              while TT >= 0 do
              begin
                T := TT;
                if P.Board[T] = pcEmpty then
                  AddMove(L, S, T, mfNormal, pcEmpty)
                else
                begin
                  if ColorOf(P.Board[T]) = O then AddMove(L, S, T, mfNormal, P.Board[T]);
                  Break;
                end;
                TT := StepSq(T, BishopDF[i], BishopDR[i]);
              end;
            end;
          if (K = PK_ROOK) or (K = PK_QUEEN) then
            for i := 0 to 3 do
            begin
              TT := StepSq(S, RookDF[i], RookDR[i]);
              while TT >= 0 do
              begin
                T := TT;
                if P.Board[T] = pcEmpty then
                  AddMove(L, S, T, mfNormal, pcEmpty)
                else
                begin
                  if ColorOf(P.Board[T]) = O then AddMove(L, S, T, mfNormal, P.Board[T]);
                  Break;
                end;
                TT := StepSq(T, RookDF[i], RookDR[i]);
              end;
            end;
        end;
    end;
  end;

  // Rok
  if C = coWhite then
  begin
    if (P.Board[4] = pcWK) and ((P.Castle and 1) <> 0) and
       (P.Board[5] = pcEmpty) and (P.Board[6] = pcEmpty) and (P.Board[7] = pcWR) and
       (not IsAttacked(P, 4, coBlack)) and (not IsAttacked(P, 5, coBlack)) and
       (not IsAttacked(P, 6, coBlack)) then
      AddMove(L, 4, 6, mfCastleK, pcEmpty);
    if (P.Board[4] = pcWK) and ((P.Castle and 2) <> 0) and
       (P.Board[3] = pcEmpty) and (P.Board[2] = pcEmpty) and (P.Board[1] = pcEmpty) and
       (P.Board[0] = pcWR) and
       (not IsAttacked(P, 4, coBlack)) and (not IsAttacked(P, 3, coBlack)) and
       (not IsAttacked(P, 2, coBlack)) then
      AddMove(L, 4, 2, mfCastleQ, pcEmpty);
  end
  else
  begin
    if (P.Board[60] = pcBK) and ((P.Castle and 4) <> 0) and
       (P.Board[61] = pcEmpty) and (P.Board[62] = pcEmpty) and (P.Board[63] = pcBR) and
       (not IsAttacked(P, 60, coWhite)) and (not IsAttacked(P, 61, coWhite)) and
       (not IsAttacked(P, 62, coWhite)) then
      AddMove(L, 60, 62, mfCastleK, pcEmpty);
    if (P.Board[60] = pcBK) and ((P.Castle and 8) <> 0) and
       (P.Board[59] = pcEmpty) and (P.Board[58] = pcEmpty) and (P.Board[57] = pcEmpty) and
       (P.Board[56] = pcBR) and
       (not IsAttacked(P, 60, coWhite)) and (not IsAttacked(P, 59, coWhite)) and
       (not IsAttacked(P, 58, coWhite)) then
      AddMove(L, 60, 58, mfCastleQ, pcEmpty);
  end;

  Result := L;
end;

function GenLegal(const P: TPosition): TMoveList;
var
  Pseudo: TMoveList;
  L: TMoveList;
  i: Integer;
  P2: TPosition;
begin
  L.Count := 0;
  Pseudo := GenPseudo(P);
  for i := 0 to Pseudo.Count - 1 do
  begin
    P2 := P;
    ApplyMove(P2, Pseudo.Items[i]);
    if not InCheck(P2, P.Side) then
    begin
      L.Items[L.Count] := Pseudo.Items[i];
      Inc(L.Count);
    end;
  end;
  Result := L;
end;

procedure ApplyMove(var P: TPosition; const M: TMove);
var
  pc, NewPc: TPiece;
  C: TColor;
begin
  pc := P.Board[M.FromSq];
  C := ColorOf(pc);
  P.Board[M.FromSq] := pcEmpty;

  case M.Flag of
    mfEnPassant:
      begin
        P.Board[M.ToSq] := pc;
        if C = coWhite then P.Board[M.ToSq - 8] := pcEmpty
        else P.Board[M.ToSq + 8] := pcEmpty;
        P.EP := -1;
      end;
    mfCastleK, mfCastleQ:
      begin
        P.Board[M.ToSq] := pc;
        if M.Flag = mfCastleK then
        begin
          if C = coWhite then
          begin
            P.Board[5] := P.Board[7]; P.Board[7] := pcEmpty;
          end
          else
          begin
            P.Board[61] := P.Board[63]; P.Board[63] := pcEmpty;
          end;
        end
        else
        begin
          if C = coWhite then
          begin
            P.Board[3] := P.Board[0]; P.Board[0] := pcEmpty;
          end
          else
          begin
            P.Board[59] := P.Board[56]; P.Board[56] := pcEmpty;
          end;
        end;
        P.EP := -1;
      end;
    mfPromoQ, mfPromoR, mfPromoB, mfPromoN:
      begin
        case M.Flag of
          mfPromoQ: if C = coWhite then NewPc := pcWQ else NewPc := pcBQ;
          mfPromoR: if C = coWhite then NewPc := pcWR else NewPc := pcBR;
          mfPromoB: if C = coWhite then NewPc := pcWB else NewPc := pcBB;
        else
          if C = coWhite then NewPc := pcWN else NewPc := pcBN;
        end;
        P.Board[M.ToSq] := NewPc;
        P.EP := -1;
      end;
  else
    begin
      P.Board[M.ToSq] := pc;
      if (KindOf(pc) = PK_PAWN) and (Abs(M.ToSq - M.FromSq) = 16) then
        P.EP := (M.FromSq + M.ToSq) div 2
      else
        P.EP := -1;
    end;
  end;

  // Rok hakları
  if pc = pcWK then P.Castle := P.Castle and not 3;
  if pc = pcBK then P.Castle := P.Castle and not 12;
  if (M.FromSq = 0) or (M.ToSq = 0) then P.Castle := P.Castle and not 2;
  if (M.FromSq = 7) or (M.ToSq = 7) then P.Castle := P.Castle and not 1;
  if (M.FromSq = 56) or (M.ToSq = 56) then P.Castle := P.Castle and not 8;
  if (M.FromSq = 63) or (M.ToSq = 63) then P.Castle := P.Castle and not 4;

  if (KindOf(pc) = PK_PAWN) or (M.Captured <> pcEmpty) then
    P.Halfmove := 0
  else
    Inc(P.Halfmove);

  if P.Side = coBlack then Inc(P.Fullmove);
  P.Side := Opp(P.Side);
end;

function PositionKey(const P: TPosition): string;
var
  S: Integer;
begin
  Result := '';
  for S := 0 to 63 do Result := Result + PieceChar(P.Board[S]);
  if P.Side = coWhite then Result := Result + 'w' else Result := Result + 'b';
  Result := Result + Chr(Ord('0') + P.Castle);
  if P.EP >= 0 then Result := Result + SqName(P.EP) else Result := Result + '--';
end;

// FIDE 5.2b: mat hiçbir şekilde mümkün değilse oyun beraberedir.
// Yalnızca kesin olarak ölü olan konumlar otomatik berabere sayılır.
function IsInsufficientMaterial(const P: TPosition): Boolean;
var
  S: Integer;
  WP, WN, WB, BP, BN, BB: Integer;
  WBC, BBC: Integer;
begin
  WP := 0; WN := 0; WB := 0; WBC := 0;
  BP := 0; BN := 0; BB := 0; BBC := 0;

  for S := 0 to 63 do
  begin
    if P.Board[S] = pcEmpty then Continue;
    case P.Board[S] of
      pcWP: Inc(WP);
      pcWN: Inc(WN);
      pcBP: Inc(BP);
      pcBN: Inc(BN);
      pcWB: begin Inc(WB); WBC := WBC or (1 shl ((FileOf(S) + RankOf(S)) and 1)); end;
      pcBB: begin Inc(BB); BBC := BBC or (1 shl ((FileOf(S) + RankOf(S)) and 1)); end;
      pcWR, pcWQ, pcBR, pcBQ: Exit(False);  // kale/vezir varsa mat mümkün
    end;
  end;

  // Piyon varsa terfi ile mat mümkündür.
  if (WP > 0) or (BP > 0) then Exit(False);

  // Şah + şah
  if (WN + WB + BN + BB = 0) then Exit(True);

  // Tek taraflı eksik malzeme
  if (BN + BB = 0) then
  begin
    if (WN = 1) and (WB = 0) then Exit(True);  // K+A vs K
    if (WB = 1) and (WN = 0) then Exit(True);  // K+F vs K
    // Aynı renk karelerde iki (veya daha fazla) fil ile mat imkânsızdır.
    if (WN = 0) and (WB >= 2) and ((WBC and (WBC - 1)) = 0) then Exit(True);
    Exit(False);
  end;
  if (WN + WB = 0) then
  begin
    if (BN = 1) and (BB = 0) then Exit(True);
    if (BB = 1) and (BN = 0) then Exit(True);
    if (BN = 0) and (BB >= 2) and ((BBC and (BBC - 1)) = 0) then Exit(True);
    Exit(False);
  end;

  // İki tarafta da yalnızca hafif taşlar. FIDE'ye göre K+A vs K+A ölü
  // konum değildir: savunan at kendi şahının kaçış karesini kapatabilir.
  // Buna karşılık tüm filler aynı renkte ve hiç at yoksa mat imkânsızdır.
  if (WN = 0) and (BN = 0) and (WB > 0) and (BB > 0) then
  begin
    if ((WBC or BBC) and ((WBC or BBC) - 1)) = 0 then Exit(True);
  end;
  Result := False;
end;

function StartPos: TPosition;
begin
  Result := FENToPos('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
end;

function FENToPos(const FEN: string): TPosition;
var
  Parts: TStringList;
  BoardPart, Chars: string;
  Rank, F, p: Integer;
  Ch: Char;
  Piece: TPiece;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Side := coWhite;
  Result.Castle := 0;
  Result.EP := -1;
  Result.Halfmove := 0;
  Result.Fullmove := 1;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Trim(FEN);
    while Parts.Count < 6 do Parts.Add('');

    BoardPart := Parts[0];
    FillChar(Result.Board, SizeOf(Result.Board), 0);

    Rank := 7;
    F := 0;
    p := 1;
    while (p <= Length(BoardPart)) and (Rank >= 0) do
    begin
      Ch := BoardPart[p];
      if Ch = '/' then
      begin
        Dec(Rank); F := 0;
      end
      else if Ch in ['1'..'8'] then
        Inc(F, Ord(Ch) - Ord('0'))
      else
      begin
        case Ch of
          'P': Piece := pcWP; 'N': Piece := pcWN; 'B': Piece := pcWB;
          'R': Piece := pcWR; 'Q': Piece := pcWQ; 'K': Piece := pcWK;
          'p': Piece := pcBP; 'n': Piece := pcBN; 'b': Piece := pcBB;
          'r': Piece := pcBR; 'q': Piece := pcBQ; 'k': Piece := pcBK;
        else
          Piece := pcEmpty;
        end;
        if (Rank >= 0) and (F >= 0) and (F < 8) then
          Result.Board[Rank * 8 + F] := Piece;
        Inc(F);
      end;
      Inc(p);
    end;

    if Parts[1] = 'w' then Result.Side := coWhite
    else if Parts[1] = 'b' then Result.Side := coBlack;

    Result.Castle := 0;
    Chars := Parts[2];
    for Ch in Chars do
      case Ch of
        'K': Result.Castle := Result.Castle or 1;
        'Q': Result.Castle := Result.Castle or 2;
        'k': Result.Castle := Result.Castle or 4;
        'q': Result.Castle := Result.Castle or 8;
      end;

    if (Length(Parts[3]) = 2) and (Parts[3][1] in ['a'..'h']) and
       (Parts[3][2] in ['1'..'8']) then
      Result.EP := NameToSq(Parts[3])
    else
      Result.EP := -1;

    Result.Halfmove := StrToIntDef(Parts[4], 0);
    Result.Fullmove := StrToIntDef(Parts[5], 1);
    if Result.Fullmove < 1 then Result.Fullmove := 1;
  finally
    Parts.Free;
  end;
end;

function PosToFEN(const P: TPosition): string;
var
  Rank, F, Empty: Integer;
  pc: TPiece;
begin
  Result := '';
  for Rank := 7 downto 0 do
  begin
    Empty := 0;
    for F := 0 to 7 do
    begin
      pc := P.Board[Rank * 8 + F];
      if pc = pcEmpty then Inc(Empty)
      else
      begin
        if Empty > 0 then begin Result := Result + IntToStr(Empty); Empty := 0; end;
        Result := Result + PieceChar(pc);
      end;
    end;
    if Empty > 0 then Result := Result + IntToStr(Empty);
    if Rank > 0 then Result := Result + '/';
  end;

  Result := Result + ' ';
  if P.Side = coWhite then Result := Result + 'w' else Result := Result + 'b';
  Result := Result + ' ';
  if P.Castle = 0 then Result := Result + '-'
  else
  begin
    if (P.Castle and 1) <> 0 then Result := Result + 'K';
    if (P.Castle and 2) <> 0 then Result := Result + 'Q';
    if (P.Castle and 4) <> 0 then Result := Result + 'k';
    if (P.Castle and 8) <> 0 then Result := Result + 'q';
  end;
  Result := Result + ' ';
  if P.EP >= 0 then Result := Result + SqName(P.EP) else Result := Result + '-';
  Result := Result + ' ' + IntToStr(P.Halfmove) + ' ' + IntToStr(P.Fullmove);
end;

{ TChessGame }

constructor TChessGame.Create;
begin
  inherited Create;
  Reset;
end;

procedure TChessGame.Reset;
begin
  FPos := StartPos;
  FInitialFEN := PosToFEN(FPos);
  SetLength(FSan, 0);
  SetLength(FPosHist, 0);
  PushHistory('');
end;

procedure TChessGame.SetPosition(const APos: TPosition);
begin
  FPos := APos;
  FInitialFEN := PosToFEN(FPos);
  SetLength(FSan, 0);
  SetLength(FPosHist, 0);
  PushHistory('');
end;

procedure TChessGame.LoadFEN(const FEN: string);
begin
  SetPosition(FENToPos(FEN));
end;

procedure TChessGame.PushHistory(const ASan: string);
var
  N: Integer;
begin
  N := Length(FSan);
  SetLength(FSan, N + 1);
  FSan[N] := ASan;
  SetLength(FPosHist, N + 1);
  FPosHist[N] := FPos;
end;

function TChessGame.DoMove(const M: TMove): string;
begin
  Result := MoveToSAN(M);
  ChessEngine.ApplyMove(FPos, M);
  // Geçmiş, hamle sonrası pozisyonları tutar; böylece mevcut pozisyon da
  // IsRepetition sayımına dahil olur ve üç tekrar 3. oluşumda yakalanır.
  PushHistory(Result);
end;

procedure TChessGame.Undo;
var
  N: Integer;
begin
  N := Length(FSan);
  if N <= 1 then Exit;
  // FPosHist[N-1] mevcut pozisyon, N-2 ise son hamle öncesi pozisyondur.
  FPos := FPosHist[N - 2];
  SetLength(FSan, N - 1);
  SetLength(FPosHist, N - 1);
end;

function TChessGame.CanUndo: Boolean;
begin
  Result := Length(FSan) > 1;
end;

function TChessGame.LegalMoves: TMoveList;
begin
  Result := GenLegal(FPos);
end;

function TChessGame.LegalFrom(Sq: TSquare): TMoveList;
var
  All: TMoveList;
  L: TMoveList;
  i: Integer;
begin
  L.Count := 0;
  All := GenLegal(FPos);
  for i := 0 to All.Count - 1 do
    if All.Items[i].FromSq = Sq then
    begin
      L.Items[L.Count] := All.Items[i];
      Inc(L.Count);
    end;
  Result := L;
end;

function TChessGame.MoveToSAN(const M: TMove): string;
var
  All, After: TMoveList;
  i: Integer;
  SameFile, SameRank, NeedFile, NeedRank: Boolean;
  pc: TPiece;
  P2: TPosition;
  Suffix: string;
begin
  case M.Flag of
    mfCastleK: Result := 'O-O';
    mfCastleQ: Result := 'O-O-O';
  else
    begin
      pc := FPos.Board[M.FromSq];
      Result := '';
      if KindOf(pc) <> PK_PAWN then
        case KindOf(pc) of
          PK_KNIGHT: Result := 'N';
          PK_BISHOP: Result := 'B';
          PK_ROOK: Result := 'R';
          PK_QUEEN: Result := 'Q';
          PK_KING: Result := 'K';
        end;

      if KindOf(pc) = PK_PAWN then
      begin
        if M.Captured <> pcEmpty then Result := Chr(Ord('a') + FileOf(M.FromSq));
      end
      else
      begin
        All := GenLegal(FPos);
        SameFile := False; SameRank := False; NeedFile := False;
        for i := 0 to All.Count - 1 do
          if (All.Items[i].ToSq = M.ToSq) and (All.Items[i].FromSq <> M.FromSq) and
             (FPos.Board[All.Items[i].FromSq] = pc) then
          begin
            NeedFile := True;
            if FileOf(All.Items[i].FromSq) = FileOf(M.FromSq) then SameFile := True;
            if RankOf(All.Items[i].FromSq) = RankOf(M.FromSq) then SameRank := True;
          end;
        if NeedFile then
        begin
          NeedRank := SameFile and SameRank;
          if SameFile and (not SameRank) then NeedFile := False;
          if NeedFile then Result := Result + Chr(Ord('a') + FileOf(M.FromSq));
          if NeedRank then Result := Result + IntToStr(RankOf(M.FromSq) + 1);
        end;
      end;

      if M.Captured <> pcEmpty then Result := Result + 'x';
      Result := Result + SqName(M.ToSq);
      case M.Flag of
        mfPromoQ: Result := Result + '=Q';
        mfPromoR: Result := Result + '=R';
        mfPromoB: Result := Result + '=B';
        mfPromoN: Result := Result + '=N';
      end;
    end;
  end;

  P2 := FPos;
  ChessEngine.ApplyMove(P2, M);
  if InCheck(P2, P2.Side) then
  begin
    After := GenLegal(P2);
    if After.Count = 0 then Suffix := '#' else Suffix := '+';
    Result := Result + Suffix;
  end;
end;

function TChessGame.GetResult(out Text: string): Boolean;
var
  L: TMoveList;
  WinnerStr: string;
begin
  Result := False;
  Text := '';
  L := GenLegal(FPos);
  if L.Count = 0 then
  begin
    if InCheck(FPos, FPos.Side) then
    begin
      if FPos.Side = coWhite then WinnerStr := 'Siyah'
      else WinnerStr := 'Beyaz';
      Text := 'Şah mat! ' + WinnerStr + ' kazandı.';
    end
    else
      Text := 'Pat. Oyun berabere.';
    Exit(True);
  end;
  if IsInsufficientMaterial(FPos) then
  begin
    Text := 'Yetersiz mat malzemesi: Berabere.';
    Exit(True);
  end;
  if FPos.Halfmove >= 100 then
  begin
    Text := '50 hamle kuralı: Berabere.';
    Exit(True);
  end;
  if IsRepetition then
  begin
    Text := 'Üç tekrar kuralı: Berabere.';
    Exit(True);
  end;
end;

function TChessGame.ResultCode: string;
var S: string;
begin
  Result := '*';
  if not GetResult(S) then Exit;
  if System.Pos('Beyaz kazandı', S) > 0 then Result := '1-0'
  else if System.Pos('Siyah kazandı', S) > 0 then Result := '0-1'
  else Result := '1/2-1/2';
end;

function TChessGame.IsRepetition: Boolean;
var
  i, Count: Integer;
  Key: string;
begin
  Key := PositionKey(FPos);
  Count := 0;
  for i := 0 to High(FPosHist) do
    if PositionKey(FPosHist[i]) = Key then Inc(Count);
  Result := Count >= 3;
end;

function TChessGame.FEN: string;
begin
  Result := PosToFEN(FPos);
end;

function TChessGame.InitialFEN: string;
begin
  Result := FInitialFEN;
end;

function TChessGame.SanCount: Integer;
begin
  Result := Length(FSan) - 1;
end;

function TChessGame.SanItem(Index: Integer): string;
begin
  // FSan[0] başlangıç pozisyonu için boş tutucudur; gerçek hamleler 1'den başlar.
  Inc(Index);
  if (Index < 1) or (Index >= Length(FSan)) then Result := ''
  else Result := FSan[Index];
end;

end.
