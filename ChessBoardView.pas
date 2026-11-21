unit ChessBoardView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ChessEngine;

type
  TMoveEvent = procedure(Sender: TObject; const M: TMove) of object;
  TPromoteEvent = function(Sender: TObject): TMoveFlag of object;

  TChessBoardView = class(TCustomControl)
  private
    FGame: TChessGame;
    FFlipped: Boolean;
    FEditMode: Boolean;
    FEditPos: TPosition;
    FBrush: TPiece;
    FPainting: Boolean;
    FPaintPiece: TPiece;
    FShowLegal: Boolean;
    FSelected: Integer;
    FLegal: TMoveList;
    FDragging: Boolean;
    FDragFrom: Integer;
    FDragX, FDragY: Integer;
    FLastMove: TMove;
    FHasLast: Boolean;
    FSuggested: TMove;
    FHasSuggested: Boolean;
    FTopMoves: array[0..4] of TMove;
    FTopCount: Integer;
    FBoardSize, FSqSize, FOriginX, FOriginY: Integer;
    FOnMove: TMoveEvent;
    FOnPromote: TPromoteEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnEditChanged: TNotifyEvent;
    procedure SetGame(AValue: TChessGame);
    procedure SetFlipped(AValue: Boolean);
    procedure SetShowLegal(AValue: Boolean);
    procedure SetEditMode(AValue: Boolean);
    procedure SetBrush(AValue: TPiece);
    function ActivePos: TPosition;
    function SquareAt(X, Y: Integer): Integer;
    function FindMove(AFrom, ATo: TSquare; out M: TMove): Boolean;
    procedure DoUserMove(const M: TMove);
    procedure DrawPiece(Cv: TCanvas; X, Y, S: Integer; P: TPiece);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshLegal;
    procedure ClearSelection;
    procedure SetLastMove(const M: TMove; Has: Boolean);
    procedure SetSuggestion(const M: TMove; Has: Boolean);
    procedure SetTopMoves(const AMoves: array of TMove);
    property Game: TChessGame read FGame write SetGame;
    property Flipped: Boolean read FFlipped write SetFlipped;
    property ShowLegal: Boolean read FShowLegal write SetShowLegal;
    property EditMode: Boolean read FEditMode write SetEditMode;
    property EditPosition: TPosition read FEditPos write FEditPos;
    property Brush: TPiece read FBrush write SetBrush;
    property OnMove: TMoveEvent read FOnMove write FOnMove;
    property OnPromote: TPromoteEvent read FOnPromote write FOnPromote;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnEditChanged: TNotifyEvent read FOnEditChanged write FOnEditChanged;
  end;

implementation

uses
  Math;

constructor TChessBoardView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelected := -1;
  FDragFrom := -1;
  FLegal.Count := 0;
  FShowLegal := True;
  DoubleBuffered := True;
  Width := 600;
  Height := 600;
end;

procedure TChessBoardView.SetGame(AValue: TChessGame);
begin
  FGame := AValue;
  ClearSelection;
  FHasLast := False;
  FHasSuggested := False;
  Invalidate;
end;

procedure TChessBoardView.SetFlipped(AValue: Boolean);
begin
  if FFlipped = AValue then Exit;
  FFlipped := AValue;
  Invalidate;
end;

procedure TChessBoardView.SetShowLegal(AValue: Boolean);
begin
  if FShowLegal = AValue then Exit;
  FShowLegal := AValue;
  Invalidate;
end;

procedure TChessBoardView.SetBrush(AValue: TPiece);
begin
  FBrush := AValue;
end;

function TChessBoardView.ActivePos: TPosition;
begin
  if FEditMode then Result := FEditPos
  else if FGame <> nil then Result := FGame.Pos
  else FillChar(Result, SizeOf(Result), 0);
end;

procedure TChessBoardView.SetEditMode(AValue: Boolean);
begin
  if FEditMode = AValue then Exit;
  FEditMode := AValue;
  FDragging := False;
  FPainting := False;
  FSelected := -1;
  FLegal.Count := 0;
  if AValue and (FGame <> nil) then FEditPos := FGame.Pos;
  Invalidate;
end;

procedure TChessBoardView.ClearSelection;
begin
  FSelected := -1;
  FDragging := False;
  FLegal.Count := 0;
  Invalidate;
end;

procedure TChessBoardView.RefreshLegal;
begin
  FLegal.Count := 0;
  if (FGame <> nil) and (FSelected >= 0) then
    FLegal := FGame.LegalFrom(FSelected);
  Invalidate;
end;

procedure TChessBoardView.SetLastMove(const M: TMove; Has: Boolean);
begin
  FLastMove := M;
  FHasLast := Has;
  Invalidate;
end;

procedure TChessBoardView.SetSuggestion(const M: TMove; Has: Boolean);
begin
  FSuggested := M;
  FHasSuggested := Has;
  if not Has then FTopCount := 0;
  Invalidate;
end;

procedure TChessBoardView.SetTopMoves(const AMoves: array of TMove);
var
  i: Integer;
begin
  FTopCount := Length(AMoves);
  if FTopCount > 5 then FTopCount := 5;
  for i := 0 to FTopCount - 1 do FTopMoves[i] := AMoves[i];
  Invalidate;
end;

function TChessBoardView.SquareAt(X, Y: Integer): Integer;
var
  DispCol, DispRow, F, R: Integer;
begin
  Result := -1;
  if (FSqSize <= 0) then Exit;
  if (X < FOriginX) or (Y < FOriginY) or
     (X >= FOriginX + FBoardSize) or (Y >= FOriginY + FBoardSize) then Exit;

  DispCol := (X - FOriginX) div FSqSize;
  DispRow := (Y - FOriginY) div FSqSize;
  if FFlipped then
  begin
    F := 7 - DispCol;
    R := DispRow;
  end
  else
  begin
    F := DispCol;
    R := 7 - DispRow;
  end;
  if (F < 0) or (F > 7) or (R < 0) or (R > 7) then Exit;
  Result := R * 8 + F;
end;

function TChessBoardView.FindMove(AFrom, ATo: TSquare; out M: TMove): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to FLegal.Count - 1 do
    if (FLegal.Items[i].FromSq = AFrom) and (FLegal.Items[i].ToSq = ATo) then
    begin
      M := FLegal.Items[i];
      Exit(True);
    end;
end;

procedure TChessBoardView.DoUserMove(const M: TMove);
var
  Actual: TMove;
begin
  Actual := M;
  if M.Flag in [mfPromoQ, mfPromoR, mfPromoB, mfPromoN] then
    if Assigned(FOnPromote) then
      Actual.Flag := FOnPromote(Self);
  FSelected := -1;
  FDragging := False;
  FLegal.Count := 0;
  FHasSuggested := False;
  Invalidate;
  if Assigned(FOnMove) then FOnMove(Self, Actual);
end;

procedure TChessBoardView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Sq: Integer;
  M: TMove;
  pc: TPiece;
begin
  inherited MouseDown(Button, Shift, X, Y);

  if FEditMode then
  begin
    Sq := SquareAt(X, Y);
    if Sq < 0 then Exit;
    if Button = mbRight then
    begin
      FEditPos.Board[Sq] := pcEmpty;
      FPaintPiece := pcEmpty;
      FPainting := True;
    end
    else if Button = mbLeft then
    begin
      FEditPos.Board[Sq] := FBrush;
      FPaintPiece := FBrush;
      FPainting := True;
    end
    else Exit;
    Invalidate;
    if Assigned(FOnEditChanged) then FOnEditChanged(Self);
    Exit;
  end;

  if Button <> mbLeft then Exit;
  if FGame = nil then Exit;
  Sq := SquareAt(X, Y);
  if Sq < 0 then Exit;

  if (FSelected >= 0) and FindMove(FSelected, Sq, M) then
  begin
    DoUserMove(M);
    Exit;
  end;

  pc := FGame.Pos.Board[Sq];
  if (pc <> pcEmpty) and (ColorOf(pc) = FGame.Pos.Side) then
  begin
    if FSelected = Sq then
    begin
      ClearSelection;
      if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
      Exit;
    end;
    FSelected := Sq;
    FDragging := True;
    FDragFrom := Sq;
    FDragX := X;
    FDragY := Y;
    RefreshLegal;
    if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
  end
  else
  begin
    ClearSelection;
    if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
  end;
end;

procedure TChessBoardView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Sq: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FEditMode then
  begin
    if FPainting then
    begin
      Sq := SquareAt(X, Y);
      if (Sq >= 0) and (FEditPos.Board[Sq] <> FPaintPiece) then
      begin
        FEditPos.Board[Sq] := FPaintPiece;
        Invalidate;
        if Assigned(FOnEditChanged) then FOnEditChanged(Self);
      end;
    end;
    Exit;
  end;
  if FDragging then
  begin
    FDragX := X;
    FDragY := Y;
    Invalidate;
  end;
end;

procedure TChessBoardView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Sq, FromSq: Integer;
  M: TMove;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FEditMode then
  begin
    FPainting := False;
    Exit;
  end;
  if (not FDragging) or (Button <> mbLeft) then Exit;
  FDragging := False;
  Sq := SquareAt(X, Y);
  FromSq := FDragFrom;

  if (Sq >= 0) and (Sq <> FromSq) and FindMove(FromSq, Sq, M) then
  begin
    DoUserMove(M);
    Exit;
  end;

  if (Sq >= 0) and (Sq = FromSq) then
  begin
    // tıklayıp bırakma: seçim korunur
    FDragFrom := -1;
    Invalidate;
    Exit;
  end;

  ClearSelection;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
end;

procedure TChessBoardView.DrawPiece(Cv: TCanvas; X, Y, S: Integer; P: TPiece);
const
  // İki taraf da dolu sembollerle çizilir. Beyaz taşlar odun kahverengisi,
  // siyah taşlar koyu mürekkep rengindedir; böylece taşlar şeffaf görünmez.
  WhiteGlyphs: array[1..6] of string = ('♟', '♞', '♝', '♜', '♛', '♚');
  BlackGlyphs: array[1..6] of string = ('♟', '♞', '♝', '♜', '♛', '♚');
  Dx: array[0..7] of Integer = (-2, 0, 2, 0, -2, 2, -2, 2);
  Dy: array[0..7] of Integer = (0, -2, 0, 2, -2, -2, 2, 2);
var
  Txt: string;
  InkC, HaloC: Graphics.TColor;
  TX, TY, W, H, D, i: Integer;
  OldName: string;
  OldHeight: Integer;
  OldStyle: TFontStyles;
begin
  if (Ord(P) < 1) or (Ord(P) > 12) then Exit;
  if ColorOf(P) = coWhite then
  begin
    Txt := WhiteGlyphs[KindOf(P)];
    InkC := RGBToColor(150, 100, 55);   // odun / kahverengi
    HaloC := RGBToColor(255, 246, 224); // açık kenarlık
  end
  else
  begin
    Txt := BlackGlyphs[KindOf(P)];
    InkC := RGBToColor(28, 30, 34);
    HaloC := RGBToColor(244, 242, 230);
  end;
  D := Max(1, S div 45);

  OldName := Cv.Font.Name;
  OldHeight := Cv.Font.Height;
  OldStyle := Cv.Font.Style;

  Cv.Font.Name := 'DejaVu Sans';
  Cv.Font.Height := Round(S * 0.80);
  Cv.Font.Style := [];
  W := Cv.TextWidth(Txt);
  H := Cv.TextHeight(Txt);
  TX := X + (S - W) div 2;
  TY := Y + (S - H) div 2 - Max(1, S div 60);

  // Dolu sembol + açık halka: hem açık hem koyu karede net okunur.

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := HaloC;
  for i := 0 to 7 do
    Cv.TextOut(TX + Dx[i] * D, TY + Dy[i] * D, Txt);
  Cv.Font.Color := InkC;
  Cv.TextOut(TX, TY, Txt);
  Cv.Brush.Style := bsSolid;

  Cv.Font.Name := OldName;
  Cv.Font.Height := OldHeight;
  Cv.Font.Style := OldStyle;
end;

procedure TChessBoardView.Resize;
begin
  inherited Resize;
  // Boyut değişince eski kare/taş çizimleri kalmasın.
  Invalidate;
end;

procedure TChessBoardView.Paint;
var
  i, DispRow, DispCol, X, Y, S: Integer;
  Light, Dark, Tile: Graphics.TColor;
  Sq, KingSq: TSquare;
  pc: TPiece;
  Cv: TCanvas;
  SideInCheck: Boolean;
  PosNow: TPosition;
  k: Integer;
begin
  inherited Paint;
  Cv := Canvas;
  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := RGBToColor(28, 30, 34);
  Cv.FillRect(ClientRect);

  S := Min(ClientWidth - 12, ClientHeight - 12);
  if S < 16 then Exit;
  S := (S div 8) * 8;
  FSqSize := S div 8;
  FBoardSize := S;
  FOriginX := (ClientWidth - S) div 2;
  FOriginY := (ClientHeight - S) div 2;

  Light := RGBToColor(235, 236, 208);
  Dark := RGBToColor(120, 150, 105);
  PosNow := ActivePos;

  SideInCheck := False;
  KingSq := 0;
  if not FEditMode then
  begin
    SideInCheck := InCheck(PosNow, PosNow.Side);
    if SideInCheck then
    begin
      for Sq := 0 to 63 do
        if ((PosNow.Side = coWhite) and (PosNow.Board[Sq] = pcWK)) or
           ((PosNow.Side = coBlack) and (PosNow.Board[Sq] = pcBK)) then
          KingSq := Sq;
    end;
  end;

  for i := 0 to 63 do
  begin
    if FFlipped then
    begin
      DispRow := RankOf(i);
      DispCol := 7 - FileOf(i);
    end
    else
    begin
      DispRow := 7 - RankOf(i);
      DispCol := FileOf(i);
    end;
    X := FOriginX + DispCol * FSqSize;
    Y := FOriginY + DispRow * FSqSize;

    if ((FileOf(i) + RankOf(i)) mod 2) = 0 then Tile := Dark
    else Tile := Light;
    Cv.Brush.Color := Tile;
    Cv.Pen.Style := psClear;
    Cv.FillRect(X, Y, X + FSqSize, Y + FSqSize);

    // Son hamle vurgusu
    if FHasLast and (i in [FLastMove.FromSq, FLastMove.ToSq]) then
    begin
      Cv.Brush.Color := RGBToColor(210, 195, 90);
      Cv.FillRect(X, Y, X + FSqSize, Y + FSqSize);
    end;

    // Önerilen hamle (analiz)
    if FHasSuggested and (i in [FSuggested.FromSq, FSuggested.ToSq]) then
    begin
      Cv.Brush.Color := RGBToColor(110, 190, 130);
      Cv.FillRect(X, Y, X + FSqSize, Y + FSqSize);
    end;

    // Seçili kare
    if i = FSelected then
    begin
      Cv.Brush.Color := RGBToColor(110, 165, 220);
      Cv.FillRect(X, Y, X + FSqSize, Y + FSqSize);
    end;

    // Şah uyarısı
    if SideInCheck and (i = KingSq) then
    begin
      Cv.Brush.Color := RGBToColor(220, 90, 85);
      Cv.FillRect(X, Y, X + FSqSize, Y + FSqSize);
    end;

    // Koordinatlar
    Cv.Font.Height := Max(9, FSqSize div 7);
    Cv.Font.Style := [fsBold];
    if ((FileOf(i) + RankOf(i)) mod 2) = 0 then Cv.Font.Color := Light
    else Cv.Font.Color := Dark;
    Cv.Brush.Style := bsClear;
    if DispRow = 7 then
      Cv.TextOut(X + FSqSize - Cv.TextWidth(Chr(Ord('a') + FileOf(i))) - 3,
                 Y + FSqSize - Cv.TextHeight('a') - 2,
                 Chr(Ord('a') + FileOf(i)));
    if DispCol = 0 then
      Cv.TextOut(X + 3, Y + 2, IntToStr(RankOf(i) + 1));
    Cv.Brush.Style := bsSolid;

    // Taş
    pc := PosNow.Board[i];
    if pc <> pcEmpty then
      if not (FDragging and (i = FDragFrom)) then
        DrawPiece(Cv, X, Y, FSqSize, pc);

  end;

  // Legal hedef noktaları (taşların üstüne gelmesi için ayrı tur)
  if FShowLegal then
    for i := 0 to FLegal.Count - 1 do
    begin
      if FFlipped then
      begin
        DispRow := RankOf(FLegal.Items[i].ToSq);
        DispCol := 7 - FileOf(FLegal.Items[i].ToSq);
      end
      else
      begin
        DispRow := 7 - RankOf(FLegal.Items[i].ToSq);
        DispCol := FileOf(FLegal.Items[i].ToSq);
      end;
      X := FOriginX + DispCol * FSqSize + FSqSize div 2;
      Y := FOriginY + DispRow * FSqSize + FSqSize div 2;
      if FLegal.Items[i].Captured <> pcEmpty then
      begin
        Cv.Pen.Color := RGBToColor(40, 60, 40);
        Cv.Pen.Width := Max(2, FSqSize div 18);
        Cv.Brush.Style := bsClear;
        Cv.Ellipse(X - FSqSize div 3, Y - FSqSize div 3,
                   X + FSqSize div 3, Y + FSqSize div 3);
        Cv.Brush.Style := bsSolid;
      end
      else
      begin
        Cv.Pen.Style := psClear;
        Cv.Brush.Color := RGBToColor(45, 60, 45);
        Cv.Ellipse(X - FSqSize div 9, Y - FSqSize div 9,
                   X + FSqSize div 9, Y + FSqSize div 9);
        Cv.Pen.Style := psSolid;
      end;
    end;

  // En iyi 5 hamlenin hedef kareleri: ince yeşil çerçeve
  if FTopCount > 0 then
    for k := 0 to FTopCount - 1 do
    begin
      if FFlipped then
      begin
        DispRow := RankOf(FTopMoves[k].ToSq);
        DispCol := 7 - FileOf(FTopMoves[k].ToSq);
      end
      else
      begin
        DispRow := 7 - RankOf(FTopMoves[k].ToSq);
        DispCol := FileOf(FTopMoves[k].ToSq);
      end;
      X := FOriginX + DispCol * FSqSize;
      Y := FOriginY + DispRow * FSqSize;
      Cv.Pen.Color := RGBToColor(70, 160, 100);
      Cv.Pen.Width := Max(2, FSqSize div 22);
      Cv.Pen.Style := psSolid;
      Cv.Brush.Style := bsClear;
      Cv.Rectangle(X + 3, Y + 3, X + FSqSize - 3, Y + FSqSize - 3);
      Cv.Brush.Style := bsSolid;
    end;

  // Sürüklenen taş
  if FDragging and (FDragFrom >= 0) then
  begin
    pc := PosNow.Board[FDragFrom];
    if pc <> pcEmpty then
      DrawPiece(Cv, FDragX - FSqSize div 2, FDragY - FSqSize div 2, FSqSize, pc);
  end;

  // Çerçeve
  Cv.Pen.Color := RGBToColor(15, 16, 18);
  Cv.Pen.Width := 2;
  Cv.Brush.Style := bsClear;
  Cv.Rectangle(FOriginX - 1, FOriginY - 1,
               FOriginX + FBoardSize + 1, FOriginY + FBoardSize + 1);
end;

end.
