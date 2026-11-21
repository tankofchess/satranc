unit ChessMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Menus, Dialogs,
  Clipbrd, Graphics, ChessEngine, ChessAI, ChessBoardView;

type
  TChessMainForm = class;

  TOpponentMode = (opHuman, opComputerBlack, opComputerWhite);

  TSearchThread = class(TThread)
  private
    FPos: TPosition;
    FDepth: Integer;
    FTimeMs: Integer;
    FResult: TSearchResult;
    FMode: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TChessMainForm; const APos: TPosition;
      ADepth, ATimeMs, AMode: Integer);
    property SearchResult: TSearchResult read FResult;
    property Mode: Integer read FMode;
  end;

  TChessMainForm = class(TForm)
  private
    FGame: TChessGame;
    FBoard: TChessBoardView;
    FBoardContainer: TPanel;
    FToolbar: TPanel;
    FRightsPanel: TPanel;
    FHistory: TListBox;
    FStatus: TLabel;
    FAnalysis: TMemo;
    FFenEdit: TEdit;
    FDepthCombo: TComboBox;
    FOppCombo: TComboBox;
    FFlipCheck: TCheckBox;
    FLegalCheck: TCheckBox;
    FAITimer: TTimer;
    FSearchThread: TSearchThread;
    FSearchPollTimer: TTimer;
    FPromoteResult: TMoveFlag;
    FMnuFlip: TMenuItem;
    FMnuLegal: TMenuItem;
    FEditPanel: TPanel;
    FEditFen: TMemo;
    FEditSide: TComboBox;
    FEditCastle: array[0..3] of TCheckBox;
    FEditEP: TEdit;
    FPaletteSelected: TButton;
    FPaletteBtns: array[0..12] of TButton;
    FBtnNew: TButton;
    FBtnUndo: TButton;
    FBtnAnalyze: TButton;
    FBtnComputer: TButton;
    FToolbarLabels: array[0..2] of TLabel;
    procedure BuildUI;
    procedure BoardContainerResize(Sender: TObject);
    procedure ToolbarResize(Sender: TObject);
    procedure BuildEditorPanel;
    procedure NewGame(Sender: TObject);
    procedure UndoMove(Sender: TObject);
    procedure Analyze(Sender: TObject);
    procedure AITimerTick(Sender: TObject);
    procedure StartSearch(AMode: Integer);
    procedure CancelSearch;
    procedure SearchPollTick(Sender: TObject);
    procedure ApplyComputerMove(const R: TSearchResult);
    procedure ApplyAnalysis(const R: TSearchResult);
    procedure BoardMoved(Sender: TObject; const M: TMove);
    function ChoosePromotion(Sender: TObject): TMoveFlag;
    procedure PromoteClick(Sender: TObject);
    procedure UpdateUI;
    function TopMovesText(const R: TSearchResult): string;
    procedure MaybeComputerMove;
    procedure OpponentChanged(Sender: TObject);
    procedure LoadFEN(Sender: TObject);
    procedure CopyFEN(Sender: TObject);
    procedure SavePGN(Sender: TObject);
    procedure FlipChanged(Sender: TObject);
    procedure LegalChanged(Sender: TObject);
    procedure EnterEditMode(Sender: TObject);
    procedure ExitEditMode(Sender: TObject);
    procedure EditApply(Sender: TObject);
    procedure EditClear(Sender: TObject);
    procedure EditStart(Sender: TObject);
    procedure PaletteClick(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure EditSideChange(Sender: TObject);
    procedure EditCastleChange(Sender: TObject);
    procedure EditEPChange(Sender: TObject);
    procedure SyncEditControls;
    procedure ShowHelpClick(Sender: TObject);
    procedure ExitApp(Sender: TObject);
    procedure ResetHighlights;
    function GetDepth: Integer;
    function GetOpponent: TOpponentMode;
    function IsGameOver: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ChessMainForm: TChessMainForm;

implementation

function ScoreText(Score: Integer): string;
var
  Sign: Char;
  AbsScore: Integer;
begin
  if Score > 0 then Sign := '+' else if Score < 0 then Sign := '-' else Sign := ' ';
  AbsScore := Abs(Score);
  Result := Sign + IntToStr(AbsScore div 100) + '.' + FormatFloat('00', AbsScore mod 100);
end;

constructor TChessMainForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGame := TChessGame.Create;
  BuildUI;
  UpdateUI;
end;

destructor TChessMainForm.Destroy;
begin
  if FSearchThread <> nil then
  begin
    AbortSearch;
    FSearchThread.Terminate;
    FSearchThread.WaitFor;
    FSearchThread.Free;
    FSearchThread := nil;
  end;
  FGame.Free;
  inherited Destroy;
end;

procedure TChessMainForm.BuildUI;
var
  MainMenu: TMainMenu;
  mGame, mView, mHelp, MI: TMenuItem;
  Toolbar, TopInfo, BottomPanel: TPanel;
  L: TLabel;
begin
  Caption := 'Satranç — Oyun ve Analiz';
  Width := 1120;
  Height := 780;
  Position := poScreenCenter;
  Constraints.MinWidth := 700;
  Constraints.MinHeight := 560;
  Color := RGBToColor(40, 42, 46);

  // ---------- Menü ----------
  MainMenu := TMainMenu.Create(Self);
  Menu := MainMenu;

  mGame := TMenuItem.Create(Self);
  mGame.Caption := 'Oyun';
  MainMenu.Items.Add(mGame);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'Yeni Oyun';
  MI.ShortCut := ShortCut(Word('N'), [ssCtrl]);
  MI.OnClick := @NewGame;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'Hamleyi Geri Al';
  MI.ShortCut := ShortCut(Word('Z'), [ssCtrl]);
  MI.OnClick := @UndoMove;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := '-';
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'Pozisyon Düzenle (elle taş diz)';
  MI.ShortCut := ShortCut(Word('E'), [ssCtrl]);
  MI.OnClick := @EnterEditMode;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := '-';
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'FEN Yükle...';
  MI.OnClick := @LoadFEN;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'FEN Kopyala';
  MI.OnClick := @CopyFEN;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'PGN Kaydet...';
  MI.OnClick := @SavePGN;
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := '-';
  mGame.Add(MI);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'Çıkış';
  MI.OnClick := @ExitApp;
  mGame.Add(MI);

  mView := TMenuItem.Create(Self);
  mView.Caption := 'Görünüm';
  MainMenu.Items.Add(mView);

  FMnuFlip := TMenuItem.Create(Self);
  FMnuFlip.Caption := 'Tahtayı Çevir';
  FMnuFlip.OnClick := @FlipChanged;
  mView.Add(FMnuFlip);

  FMnuLegal := TMenuItem.Create(Self);
  FMnuLegal.Caption := 'Geçerli Hamleleri Göster';
  FMnuLegal.Checked := True;
  FMnuLegal.OnClick := @LegalChanged;
  mView.Add(FMnuLegal);

  mHelp := TMenuItem.Create(Self);
  mHelp.Caption := 'Yardım';
  MainMenu.Items.Add(mHelp);

  MI := TMenuItem.Create(Self);
  MI.Caption := 'Nasıl Kullanılır?';
  MI.OnClick := @ShowHelpClick;
  mHelp.Add(MI);

  // ---------- Araç çubuğu ----------
  FToolbar := TPanel.Create(Self);
  Toolbar := FToolbar;
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 46;
  Toolbar.BevelOuter := bvNone;
  Toolbar.OnResize := @ToolbarResize;

  FBtnNew := TButton.Create(Toolbar);
  FBtnNew.Parent := Toolbar; FBtnNew.Left := 6; FBtnNew.Top := 7;
  FBtnNew.Width := 92; FBtnNew.Height := 30;
  FBtnNew.Caption := 'Yeni Oyun'; FBtnNew.OnClick := @NewGame;
  FBtnUndo := TButton.Create(Toolbar);
  FBtnUndo.Parent := Toolbar; FBtnUndo.Left := 104; FBtnUndo.Top := 7;
  FBtnUndo.Width := 92; FBtnUndo.Height := 30;
  FBtnUndo.Caption := 'Geri Al'; FBtnUndo.OnClick := @UndoMove;

  FBtnAnalyze := TButton.Create(Toolbar);
  FBtnAnalyze.Parent := Toolbar; FBtnAnalyze.Left := 202; FBtnAnalyze.Top := 7;
  FBtnAnalyze.Width := 100; FBtnAnalyze.Height := 30;
  FBtnAnalyze.Caption := 'Analiz Et'; FBtnAnalyze.OnClick := @Analyze;

  FBtnComputer := TButton.Create(Toolbar);
  FBtnComputer.Parent := Toolbar; FBtnComputer.Left := 308; FBtnComputer.Top := 7;
  FBtnComputer.Width := 132; FBtnComputer.Height := 30;
  FBtnComputer.Caption := 'Bilgisayar Hamlesi'; FBtnComputer.OnClick := @AITimerTick;

  L := TLabel.Create(Toolbar);
  L.Parent := Toolbar; L.Left := 452; L.Top := 13; L.Width := 58;
  L.Caption := 'Rakip:'; L.Font.Color := clWhite;
  FToolbarLabels[0] := L;

  FOppCombo := TComboBox.Create(Toolbar);
  FOppCombo.Parent := Toolbar; FOppCombo.Left := 508; FOppCombo.Top := 7;
  FOppCombo.Width := 250; FOppCombo.Height := 30;
  FOppCombo.Style := csDropDownList;
  FOppCombo.Items.Add('İki oyuncu (insan)');
  FOppCombo.Items.Add('Bilgisayar siyah oynar');
  FOppCombo.Items.Add('Bilgisayar beyaz oynar');
  FOppCombo.ItemIndex := 1;
  FOppCombo.OnChange := @OpponentChanged;

  L := TLabel.Create(Toolbar);
  L.Parent := Toolbar; L.Left := 770; L.Top := 13; L.Width := 50;
  L.Caption := 'Derinlik:'; L.Font.Color := clWhite;
  FToolbarLabels[1] := L;

  FDepthCombo := TComboBox.Create(Toolbar);
  FDepthCombo.Parent := Toolbar; FDepthCombo.Left := 824; FDepthCombo.Top := 7;
  FDepthCombo.Width := 118; FDepthCombo.Height := 30;
  FDepthCombo.Style := csDropDownList;
  FDepthCombo.Items.Add('1 - Hızlı');
  FDepthCombo.Items.Add('2 - Orta');
  FDepthCombo.Items.Add('3 - İyi');
  FDepthCombo.Items.Add('4 - Derin');
  FDepthCombo.Items.Add('5 - Çok Derin');
  FDepthCombo.Items.Add('6 - Uzman');
  FDepthCombo.ItemIndex := 2;
  FDepthCombo.Enabled := True;

  FFlipCheck := TCheckBox.Create(Toolbar);
  FFlipCheck.Parent := Toolbar; FFlipCheck.Left := 952; FFlipCheck.Top := 10;
  FFlipCheck.Width := 100; FFlipCheck.Caption := 'Çevir';
  FFlipCheck.Font.Color := clWhite; FFlipCheck.OnChange := @FlipChanged;

  FLegalCheck := TCheckBox.Create(Toolbar);
  FLegalCheck.Parent := Toolbar; FLegalCheck.Left := 952; FLegalCheck.Top := 27;
  FLegalCheck.Width := 120; FLegalCheck.Caption := 'Legal hamle';
  FLegalCheck.Font.Color := clWhite; FLegalCheck.Checked := True;
  FLegalCheck.OnChange := @LegalChanged;

  // ---------- Sağ panel ----------
  FRightsPanel := TPanel.Create(Self);
  FRightsPanel.Parent := Self;
  FRightsPanel.Align := alRight;
  FRightsPanel.Width := 340;
  FRightsPanel.BevelOuter := bvNone;
  FRightsPanel.Color := RGBToColor(48, 50, 55);

  TopInfo := TPanel.Create(FRightsPanel);
  TopInfo.Parent := FRightsPanel;
  TopInfo.Align := alTop;
  TopInfo.Height := 60;
  TopInfo.BevelOuter := bvNone;
  TopInfo.Color := FRightsPanel.Color;

  FStatus := TLabel.Create(TopInfo);
  FStatus.Parent := TopInfo;
  FStatus.Align := alClient;
  FStatus.Caption := 'Beyazın hamlesi';
  FStatus.Font.Size := 11;
  FStatus.Font.Style := [fsBold];
  FStatus.Font.Color := clWhite;
  FStatus.WordWrap := True;
  FStatus.Layout := tlCenter;

  L := TLabel.Create(FRightsPanel);
  L.Parent := FRightsPanel;
  L.Align := alTop;
  L.Height := 24;
  L.Caption := 'Hamle Geçmişi';
  L.Font.Style := [fsBold];
  L.Font.Color := RGBToColor(210, 215, 225);

  FHistory := TListBox.Create(FRightsPanel);
  FHistory.Parent := FRightsPanel;
  FHistory.Align := alClient;
  FHistory.Font.Name := 'DejaVu Sans Mono';
  FHistory.Font.Size := 10;
  FHistory.ItemHeight := 19;

  L := TLabel.Create(FRightsPanel);
  L.Parent := FRightsPanel;
  L.Align := alBottom;
  L.Height := 22;
  L.Caption := 'Analiz / Değerlendirme';
  L.Font.Style := [fsBold];
  L.Font.Color := RGBToColor(210, 215, 225);

  FAnalysis := TMemo.Create(FRightsPanel);
  FAnalysis.Parent := FRightsPanel;
  FAnalysis.Align := alBottom;
  FAnalysis.Height := 215;
  FAnalysis.ReadOnly := True;
  FAnalysis.ScrollBars := ssBoth;
  FAnalysis.WordWrap := False;
  FAnalysis.Font.Name := 'DejaVu Sans Mono';
  FAnalysis.Font.Size := 9;
  FAnalysis.Color := RGBToColor(36, 38, 42);
  FAnalysis.Font.Color := clWhite;
  FAnalysis.Text := 'Analiz için "Analiz Et" düğmesine basın.';

  L := TLabel.Create(FRightsPanel);
  L.Parent := FRightsPanel;
  L.Align := alBottom;
  L.Height := 20;
  L.Caption := 'FEN (geçerli pozisyon)';
  L.Font.Color := RGBToColor(190, 195, 205);

  FFenEdit := TEdit.Create(FRightsPanel);
  FFenEdit.Parent := FRightsPanel;
  FFenEdit.Align := alBottom;
  FFenEdit.Height := 24;
  FFenEdit.ReadOnly := True;
  FFenEdit.Color := RGBToColor(36, 38, 42);
  FFenEdit.Font.Color := clWhite;

  BottomPanel := TPanel.Create(FRightsPanel);
  BottomPanel.Parent := FRightsPanel;
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 36;
  BottomPanel.BevelOuter := bvNone;
  BottomPanel.Color := FRightsPanel.Color;
  with TButton.Create(BottomPanel) do
  begin
    Parent := BottomPanel; Left := 4; Top := 3; Width := 324; Height := 29;
    Caption := 'Pozisyon Düzenle (elle taş diz)'; OnClick := @EnterEditMode;
  end;

  // ---------- Tahta (her zaman kare, ortalanmış) ----------
  FBoardContainer := TPanel.Create(Self);
  FBoardContainer.Parent := Self;
  FBoardContainer.Align := alClient;
  FBoardContainer.BevelOuter := bvNone;
  FBoardContainer.Color := RGBToColor(28, 30, 34);
  FBoardContainer.OnResize := @BoardContainerResize;

  FBoard := TChessBoardView.Create(FBoardContainer);
  FBoard.Name := 'ChessBoard';
  FBoard.Parent := FBoardContainer;
  FBoard.Align := alNone;
  FBoard.Game := FGame;
  FBoard.OnMove := @BoardMoved;
  FBoard.OnPromote := @ChoosePromotion;
  FBoard.OnEditChanged := @EditChanged;

  ToolbarResize(Self);
  BuildEditorPanel;
  BoardContainerResize(Self);

  FAITimer := TTimer.Create(Self);
  FAITimer.Enabled := False;
  FAITimer.Interval := 60;
  FAITimer.OnTimer := @AITimerTick;

  FSearchPollTimer := TTimer.Create(Self);
  FSearchPollTimer.Enabled := False;
  FSearchPollTimer.Interval := 150;
  FSearchPollTimer.OnTimer := @SearchPollTick;
end;

procedure TChessMainForm.ToolbarResize(Sender: TObject);
const
  Lefts: array[0..9] of Integer =
    (6, 104, 202, 308, 452, 508, 770, 824, 952, 952);
  Widths: array[0..9] of Integer =
    (92, 92, 100, 132, 58, 250, 50, 118, 100, 120);
var
  Ctrls: array[0..9] of TControl;
  Scale: Double;
  i: Integer;
begin
  if FToolbar = nil then Exit;
  Ctrls[0] := FBtnNew;
  Ctrls[1] := FBtnUndo;
  Ctrls[2] := FBtnAnalyze;
  Ctrls[3] := FBtnComputer;
  Ctrls[4] := FToolbarLabels[0];
  Ctrls[5] := FOppCombo;
  Ctrls[6] := FToolbarLabels[1];
  Ctrls[7] := FDepthCombo;
  Ctrls[8] := FFlipCheck;
  Ctrls[9] := FLegalCheck;

  Scale := FToolbar.ClientWidth / 1080;
  if Scale > 1 then Scale := 1;
  if Scale < 0.55 then Scale := 0.55;
  for i := 0 to 9 do
    if Ctrls[i] <> nil then
    begin
      Ctrls[i].Left := Round(Lefts[i] * Scale);
      Ctrls[i].Width := Round(Widths[i] * Scale);
    end;
end;

procedure TChessMainForm.BoardContainerResize(Sender: TObject);
var
  W, H, Sz: Integer;
begin
  if (FBoard = nil) or (FBoardContainer = nil) then Exit;
  W := FBoardContainer.ClientWidth;
  H := FBoardContainer.ClientHeight;
  Sz := W - 16;
  if H - 16 < Sz then Sz := H - 16;
  if Sz < 64 then Sz := 64;
  FBoard.SetBounds((W - Sz) div 2, (H - Sz) div 2, Sz, Sz);
end;

procedure TChessMainForm.ResetHighlights;
var
  M: TMove;
begin
  FillChar(M, SizeOf(M), 0);
  FBoard.SetLastMove(M, False);
  FBoard.SetSuggestion(M, False);
  FBoard.ClearSelection;
end;

procedure TChessMainForm.NewGame(Sender: TObject);
begin
  FAITimer.Enabled := False;
  CancelSearch;
  FGame.Reset;
  ResetHighlights;
  FAnalysis.Lines.Text := 'Analiz için "Analiz Et" düğmesine basın.';
  UpdateUI;
end;

procedure TChessMainForm.UndoMove(Sender: TObject);
begin
  FAITimer.Enabled := False;
  CancelSearch;
  if not FGame.CanUndo then Exit;
  FGame.Undo;
  ResetHighlights;
  UpdateUI;
end;

procedure TChessMainForm.BoardMoved(Sender: TObject; const M: TMove);
var
  San: string;
begin
  FAITimer.Enabled := False;
  CancelSearch;
  San := FGame.MoveToSAN(M);
  FGame.DoMove(M);
  FBoard.SetLastMove(M, True);
  FBoard.SetSuggestion(M, False);
  FAnalysis.Lines.Text := 'Son hamle: ' + San;
  UpdateUI;
  MaybeComputerMove;
end;

function TChessMainForm.GetDepth: Integer;
begin
  Result := FDepthCombo.ItemIndex + 1;
  if Result < 1 then Result := 1;
  if Result > 6 then Result := 6;
end;

function TChessMainForm.GetOpponent: TOpponentMode;
begin
  case FOppCombo.ItemIndex of
    1: Result := opComputerBlack;
    2: Result := opComputerWhite;
  else
    Result := opHuman;
  end;
end;

function TChessMainForm.IsGameOver: Boolean;
var S: string;
begin
  Result := FGame.GetResult(S);
end;

procedure TChessMainForm.MaybeComputerMove;
var
  Opp: TOpponentMode;
begin
  Opp := GetOpponent;
  if IsGameOver then Exit;
  if ((Opp = opComputerBlack) and (FGame.Pos.Side = coBlack)) or
     ((Opp = opComputerWhite) and (FGame.Pos.Side = coWhite)) then
    FAITimer.Enabled := True;
end;

procedure TChessMainForm.OpponentChanged(Sender: TObject);
begin
  // Rakip modu değişince bekleyen otomatik hamle iptal edilir; yeni modun
  // sırasıysa hemen başlatılır. Böylece "insan" -> "bilgisayar" geçişinde
  // oyuncunun bir hamle daha yapması gerekmez.
  FAITimer.Enabled := False;
  if IsGameOver then Exit;
  MaybeComputerMove;
end;

procedure TChessMainForm.AITimerTick(Sender: TObject);
begin
  FAITimer.Enabled := False;
  if FSearchThread <> nil then
  begin
    CancelSearch;
    Exit;
  end;
  StartSearch(0);
end;

constructor TSearchThread.Create(AOwner: TChessMainForm; const APos: TPosition;
  ADepth, ATimeMs, AMode: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPos := APos;
  FDepth := ADepth;
  FTimeMs := ATimeMs;
  FMode := AMode;
  FillChar(FResult, SizeOf(FResult), 0);
  Start;
end;

procedure TSearchThread.Execute;
begin
  FindBestMove(FPos, FDepth, FTimeMs, FResult);
end;

procedure TChessMainForm.StartSearch(AMode: Integer);
var
  SearchPos: TPosition;
  Depth, TimeMs: Integer;
begin
  if FSearchThread <> nil then Exit;
  if IsGameOver then Exit;

  SearchPos := FGame.Pos;
  Depth := GetDepth;
  if AMode = 0 then TimeMs := 3000 * Depth
  else TimeMs := 3000 * Depth;

  if AMode = 0 then
  begin
    FBtnComputer.Caption := 'Durdur';
    FBtnAnalyze.Enabled := False;
    FStatus.Caption := Format('Bilgisayar düşünüyor... (derinlik %d)', [Depth]);
  end
  else
  begin
    FBtnAnalyze.Caption := 'Durdur';
    FBtnComputer.Enabled := False;
    FStatus.Caption := Format('Analiz ediliyor... (derinlik %d)', [Depth]);
  end;
  FAnalysis.Lines.Text := Format(
    'Derinlik %d araması sürüyor...'#13#10 +
    'Aynı düğmeye tekrar basarak iptal edebilirsiniz.', [Depth]);
  FSearchThread := TSearchThread.Create(Self, SearchPos, Depth, TimeMs, AMode);
  FSearchPollTimer.Enabled := True;
end;

procedure TChessMainForm.CancelSearch;
begin
  if FSearchThread = nil then Exit;
  AbortSearch;
  FSearchThread.Terminate;
  FStatus.Caption := 'Arama iptal ediliyor...';
end;

procedure TChessMainForm.SearchPollTick(Sender: TObject);
var
  Thr: TSearchThread;
begin
  if FSearchThread = nil then Exit;
  if not FSearchThread.Finished then Exit;

  FSearchPollTimer.Enabled := False;
  Thr := FSearchThread;
  FSearchThread := nil;
  try
    FBtnAnalyze.Caption := 'Analiz Et';
    FBtnComputer.Caption := 'Bilgisayar Hamlesi';
    FBtnAnalyze.Enabled := True;
    FBtnComputer.Enabled := True;

    if (not Thr.Terminated) and Thr.SearchResult.Found then
    begin
      if Thr.Mode = 0 then ApplyComputerMove(Thr.SearchResult)
      else ApplyAnalysis(Thr.SearchResult);
    end;
  finally
    Thr.Free;
  end;
end;

procedure TChessMainForm.ApplyComputerMove(const R: TSearchResult);
var
  TopTxt: string;
begin
  TopTxt := TopMovesText(R);   // SAN'lar hamle öncesi pozisyona göre üretilir
  FGame.DoMove(R.Move);
  FBoard.SetLastMove(R.Move, True);
  FAnalysis.Lines.Text := Format(
    'Bilgisayar: %s'#13#10'Değerlendirme: %s'#13#10'Derinlik: %d   Düğüm: %d'#13#10,
    [FGame.SanItem(FGame.SanCount - 1), ScoreText(R.Score), R.Depth, R.Nodes]) +
    #13#10 + TopTxt;
  UpdateUI;
  MaybeComputerMove;
end;

procedure TChessMainForm.ApplyAnalysis(const R: TSearchResult);
var
  Moves: array[0..4] of TMove;
  i: Integer;
begin
  FBoard.SetSuggestion(R.Move, True);
  for i := 0 to R.TopCount - 1 do Moves[i] := R.Top[i].Move;
  FBoard.SetTopMoves(Moves);
  FAnalysis.Lines.Text :=
    Format('Önerilen hamle: %s'#13#10'Değerlendirme: %s'#13#10 +
           'Derinlik: %d   Düğüm: %d'#13#10,
      [FGame.MoveToSAN(R.Move), ScoreText(R.Score), R.Depth, R.Nodes]) +
    #13#10 + TopMovesText(R) +
    '(Yeşil dolu kare = en iyi hamle, ince yeşil çerçeveler = ilk 5 hamle)';
  UpdateUI;
end;

function TChessMainForm.TopMovesText(const R: TSearchResult): string;
var
  i: Integer;
begin
  Result := 'En iyi 5 hamle:'#13#10;
  for i := 0 to R.TopCount - 1 do
    Result := Result + Format('  %d. %-7s %s',
      [i + 1, FGame.MoveToSAN(R.Top[i].Move), ScoreText(R.Top[i].Score)]) + #13#10;
end;

procedure TChessMainForm.Analyze(Sender: TObject);
begin
  if FSearchThread <> nil then
  begin
    CancelSearch;
    Exit;
  end;
  if IsGameOver then Exit;
  StartSearch(1);
end;

function TChessMainForm.ChoosePromotion(Sender: TObject): TMoveFlag;
var
  Dlg: TForm;
  B: TButton;
  i: Integer;
  Flags: array[0..3] of TMoveFlag = (mfPromoQ, mfPromoR, mfPromoB, mfPromoN);
  Caps: array[0..3] of string = ('Vezir (Q)', 'Kale (R)', 'Fil (B)', 'At (N)');
begin
  FPromoteResult := mfPromoQ;
  Dlg := TForm.CreateNew(Self);
  try
    Dlg.Caption := 'Terfi — yeni taşı seçin';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poScreenCenter;
    Dlg.Width := 392;
    Dlg.Height := 96;
    for i := 0 to 3 do
    begin
      B := TButton.Create(Dlg);
      B.Parent := Dlg;
      B.Left := 8 + i * 95;
      B.Top := 18;
      B.Width := 88;
      B.Height := 30;
      B.Caption := Caps[i];
      B.Tag := Ord(Flags[i]);
      B.OnClick := @PromoteClick;
      if i = 0 then B.ModalResult := mrOk;
    end;
    Dlg.ShowModal;
  finally
    Result := FPromoteResult;
    Dlg.Free;
  end;
end;

procedure TChessMainForm.PromoteClick(Sender: TObject);
begin
  FPromoteResult := TMoveFlag(TButton(Sender).Tag);
  if TButton(Sender).Owner is TForm then
    TForm(TButton(Sender).Owner).ModalResult := mrOk;
end;

procedure TChessMainForm.UpdateUI;
var
  i: Integer;
  Line, S: string;
  StaticEval: Integer;
begin
  // Durum
  if FGame.GetResult(S) then
    FStatus.Caption := S
  else if InCheck(FGame.Pos, FGame.Pos.Side) then
  begin
    if FGame.Pos.Side = coWhite then FStatus.Caption := 'Şah! Beyazın hamlesi.'
    else FStatus.Caption := 'Şah! Siyahın hamlesi.';
  end
  else
  begin
    if FGame.Pos.Side = coWhite then FStatus.Caption := 'Beyazın hamlesi'
    else FStatus.Caption := 'Siyahın hamlesi';
  end;

  // Geçmiş
  FHistory.Items.Clear;
  i := 0;
  while i < FGame.SanCount do
  begin
    Line := IntToStr(i div 2 + 1) + '. ' + FGame.SanItem(i);
    if i + 1 < FGame.SanCount then Line := Line + '  ' + FGame.SanItem(i + 1);
    FHistory.Items.Add(Line);
    Inc(i, 2);
  end;
  if FHistory.Items.Count > 0 then FHistory.ItemIndex := FHistory.Items.Count - 1;

  FFenEdit.Text := FGame.FEN;
  // Düzenleme modundayken oyun butonları pasif olur; aksi halde "Yeni Oyun"
  // tahtayı düzenleme konumunda bırakıp oyunu sıfırlıyor, tutarsızlık çıkıyor.
  FBtnNew.Enabled := not FBoard.EditMode;
  FBtnUndo.Enabled := (not FBoard.EditMode) and FGame.CanUndo;
  FBtnAnalyze.Enabled := (not FBoard.EditMode) and (not IsGameOver);
  FBtnComputer.Enabled := FBtnAnalyze.Enabled;

  FMnuFlip.Checked := FFlipCheck.Checked;
  FMnuLegal.Checked := FLegalCheck.Checked;

  StaticEval := EvaluatePosition(FGame.Pos);
  if Pos('Analiz için', FAnalysis.Lines.Text) > 0 then
    FAnalysis.Lines.Text := 'Statik değerlendirme: ' + ScoreText(StaticEval) +
      ' (beyaz açısından)'#13#10'Analiz için "Analiz Et" düğmesine basın.';

  FBoard.Invalidate;
end;

procedure TChessMainForm.LoadFEN(Sender: TObject);
var
  FEN: string;
begin
  FEN := InputBox('FEN Yükle', 'FEN dizesini yapıştırın:', FGame.FEN);
  if Trim(FEN) = '' then Exit;
  try
    FAITimer.Enabled := False;
    CancelSearch;
    FGame.LoadFEN(FEN);
    ResetHighlights;
    FAnalysis.Lines.Text := 'FEN yüklendi.';
    UpdateUI;
    MaybeComputerMove;
  except
    on E: Exception do ShowMessage('FEN okunamadı: ' + E.Message);
  end;
end;

procedure TChessMainForm.CopyFEN(Sender: TObject);
begin
  if Clipboard = nil then Exit;
  Clipboard.AsText := FGame.FEN;
  ShowMessage('FEN panoya kopyalandı.');
end;

procedure TChessMainForm.SavePGN(Sender: TObject);
var
  SD: TSaveDialog;
  SL: TStringList;
  i: Integer;
  Line, ResStr: string;
begin
  SD := TSaveDialog.Create(Self);
  try
    SD.Title := 'PGN kaydet';
    SD.Filter := 'PGN dosyası|*.pgn|Tüm dosyalar|*.*';
    SD.DefaultExt := 'pgn';
    SD.FileName := 'oyun.pgn';
    if not SD.Execute then Exit;

    SL := TStringList.Create;
    try
      SL.Add('[Event "Lazarus Satranç"]');
      SL.Add('[Site "Yerel Oyun"]');
      SL.Add('[Date "' + FormatDateTime('yyyy.mm.dd', Now) + '"]');
      SL.Add('[White "Beyaz"]');
      SL.Add('[Black "Siyah"]');
      ResStr := FGame.ResultCode;
      SL.Add('[Result "' + ResStr + '"]');
      SL.Add('[FEN "' + FGame.InitialFEN + '"]');
      SL.Add('');
      Line := '';
      for i := 0 to FGame.SanCount - 1 do
      begin
        if (i mod 2) = 0 then Line := Line + IntToStr(i div 2 + 1) + '. ';
        Line := Line + FGame.SanItem(i) + ' ';
        if (i mod 2) = 1 then
        begin
          SL.Add(Trim(Line));
          Line := '';
        end;
      end;
      if Line <> '' then SL.Add(Trim(Line));
      SL.Add(ResStr);
      SL.SaveToFile(SD.FileName);
    finally
      SL.Free;
    end;
  finally
    SD.Free;
  end;
end;

procedure TChessMainForm.FlipChanged(Sender: TObject);
var
  NewValue: Boolean;
begin
  // Menü tıklamasında checkbox değişmediği için Sender'a bakılmalı.
  if Sender = FMnuFlip then NewValue := not FBoard.Flipped
  else NewValue := FFlipCheck.Checked;
  FBoard.Flipped := NewValue;
  FFlipCheck.Checked := NewValue;
  FMnuFlip.Checked := NewValue;
end;

procedure TChessMainForm.LegalChanged(Sender: TObject);
var
  NewValue: Boolean;
begin
  if Sender = FMnuLegal then NewValue := not FBoard.ShowLegal
  else NewValue := FLegalCheck.Checked;
  FBoard.ShowLegal := NewValue;
  FLegalCheck.Checked := NewValue;
  FMnuLegal.Checked := NewValue;
end;

procedure TChessMainForm.ExitApp(Sender: TObject);
begin
  Close;
end;

procedure TChessMainForm.ShowHelpClick(Sender: TObject);
begin
  ShowMessage(
    'Kullanım:'#13#10#13#10 +
    '• Taşa tıklayıp hedef kareye tıklayın veya taşı sürükleyin.'#13#10 +
    '• Mavi kare seçili taşı, yeşil noktalar geçerli hedefleri gösterir.'#13#10 +
    '• "Analiz Et" motorun önerdiği hamleyi yeşil karelerle gösterir.'#13#10 +
    '• Rakip combo kutusundan bilgisayarla oynamayı açıp kapatabilirsiniz.'#13#10 +
    '• Ctrl+N yeni oyun, Ctrl+Z hamleyi geri al, Ctrl+E pozisyon düzenleyici.'#13#10 +
    '• Terfi durumunda yeni taşı seçmeniz istenir.'#13#10 +
    '• "Analiz Et" en iyi 5 hamleyi ve değerlendirmelerini listeler.'#13#10#13#10 +
    'Kurallar: rok, en passant, terfi, şah/şah mat, pat, 50 hamle ve üç tekrar.');
end;

procedure TChessMainForm.BuildEditorPanel;
const
  Caps: array[0..12] of string =
    ('(boş)', '♙', '♘', '♗', '♖', '♕', '♔',
     '♟', '♞', '♝', '♜', '♛', '♚');
  CastleCaps: array[0..3] of string = ('K', 'Q', 'k', 'q');
var
  L: TLabel;
  B: TButton;
  i: Integer;
begin
  FEditPanel := TPanel.Create(Self);
  FEditPanel.Parent := Self;
  FEditPanel.Align := alLeft;
  FEditPanel.Width := 244;
  FEditPanel.BevelOuter := bvNone;
  FEditPanel.Color := RGBToColor(48, 50, 55);
  FEditPanel.Visible := False;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 8; L.Width := 228;
  L.Caption := 'Pozisyon Düzenleyici';
  L.Font.Style := [fsBold]; L.Font.Color := clWhite;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 30; L.Width := 228;
  L.Caption := 'Fırça: sola tık = koy, sağa tık = sil';
  L.Font.Color := RGBToColor(200, 205, 215);

  for i := 0 to 12 do
  begin
    B := TButton.Create(FEditPanel);
    B.Parent := FEditPanel;
    B.Left := 8 + (i mod 7) * 32;
    B.Top := 50 + (i div 7) * 34;
    B.Width := 30; B.Height := 30;
    B.Caption := Caps[i];
    B.Tag := i;
    B.OnClick := @PaletteClick;
    FPaletteBtns[i] := B;
  end;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 124; L.Width := 55;
  L.Caption := 'Sıra:'; L.Font.Color := clWhite;

  FEditSide := TComboBox.Create(FEditPanel);
  FEditSide.Parent := FEditPanel;
  FEditSide.Left := 68; FEditSide.Top := 120; FEditSide.Width := 164;
  FEditSide.Style := csDropDownList;
  FEditSide.Items.Add('Beyaz');
  FEditSide.Items.Add('Siyah');
  FEditSide.ItemIndex := 0;
  FEditSide.OnChange := @EditSideChange;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 160; L.Width := 50;
  L.Caption := 'Rok:'; L.Font.Color := clWhite;
  for i := 0 to 3 do
  begin
    FEditCastle[i] := TCheckBox.Create(FEditPanel);
    FEditCastle[i].Parent := FEditPanel;
    FEditCastle[i].Left := 56 + i * 40;
    FEditCastle[i].Top := 158;
    FEditCastle[i].Width := 38;
    FEditCastle[i].Caption := CastleCaps[i];
    FEditCastle[i].Font.Color := clWhite;
    FEditCastle[i].OnChange := @EditCastleChange;
  end;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 194; L.Width := 90;
  L.Caption := 'En passant:'; L.Font.Color := clWhite;

  FEditEP := TEdit.Create(FEditPanel);
  FEditEP.Parent := FEditPanel;
  FEditEP.Left := 100; FEditEP.Top := 190; FEditEP.Width := 80;
  FEditEP.Text := '-';
  FEditEP.OnChange := @EditEPChange;

  L := TLabel.Create(FEditPanel);
  L.Parent := FEditPanel; L.Left := 8; L.Top := 224; L.Width := 228;
  L.Caption := 'FEN (canlı):'; L.Font.Color := RGBToColor(190, 195, 205);

  FEditFen := TMemo.Create(FEditPanel);
  FEditFen.Parent := FEditPanel;
  FEditFen.Left := 8; FEditFen.Top := 242; FEditFen.Width := 228; FEditFen.Height := 56;
  FEditFen.ReadOnly := True;
  FEditFen.WordWrap := True;
  FEditFen.ScrollBars := ssVertical;
  FEditFen.Color := RGBToColor(36, 38, 42);
  FEditFen.Font.Color := clWhite;

  B := TButton.Create(FEditPanel);
  B.Parent := FEditPanel; B.Left := 8; B.Top := 306; B.Width := 110; B.Height := 30;
  B.Caption := 'Başlangıç'; B.OnClick := @EditStart;

  B := TButton.Create(FEditPanel);
  B.Parent := FEditPanel; B.Left := 126; B.Top := 306; B.Width := 110; B.Height := 30;
  B.Caption := 'Tahtayı Temizle'; B.OnClick := @EditClear;

  B := TButton.Create(FEditPanel);
  B.Parent := FEditPanel; B.Left := 8; B.Top := 342; B.Width := 228; B.Height := 32;
  B.Caption := 'Oyuna Yükle ve Analiz Et';
  B.Font.Style := [fsBold];
  B.OnClick := @EditApply;

  B := TButton.Create(FEditPanel);
  B.Parent := FEditPanel; B.Left := 8; B.Top := 380; B.Width := 228; B.Height := 28;
  B.Caption := 'İptal (oyuna dön)'; B.OnClick := @ExitEditMode;
end;

procedure TChessMainForm.SyncEditControls;
var
  P: TPosition;
  S: string;
begin
  P := FBoard.EditPosition;
  FEditSide.ItemIndex := Ord(P.Side);
  FEditCastle[0].Checked := (P.Castle and 1) <> 0;
  FEditCastle[1].Checked := (P.Castle and 2) <> 0;
  FEditCastle[2].Checked := (P.Castle and 4) <> 0;
  FEditCastle[3].Checked := (P.Castle and 8) <> 0;
  if P.EP < 0 then S := '-' else S := SqName(P.EP);
  FEditEP.Text := S;
end;

procedure TChessMainForm.EditChanged(Sender: TObject);
var
  P: TPosition;
  S: string;
begin
  if FEditPanel = nil then Exit;
  P := FBoard.EditPosition;
  if FEditSide.ItemIndex = 1 then P.Side := coBlack else P.Side := coWhite;

  P.Castle := 0;
  if FEditCastle[0].Checked then P.Castle := P.Castle or 1;
  if FEditCastle[1].Checked then P.Castle := P.Castle or 2;
  if FEditCastle[2].Checked then P.Castle := P.Castle or 4;
  if FEditCastle[3].Checked then P.Castle := P.Castle or 8;

  P.EP := -1;
  S := LowerCase(Trim(FEditEP.Text));
  if (Length(S) = 2) and (S[1] in ['a'..'h']) and (S[2] in ['1'..'8']) then
    P.EP := (Ord(S[1]) - Ord('a')) + 8 * (Ord(S[2]) - Ord('1'));

  P.Halfmove := 0;
  P.Fullmove := 1;
  FBoard.EditPosition := P;
  FEditFen.Text := PosToFEN(P);
end;

procedure TChessMainForm.EditSideChange(Sender: TObject);
begin
  EditChanged(Sender);
end;

procedure TChessMainForm.EditCastleChange(Sender: TObject);
begin
  EditChanged(Sender);
end;

procedure TChessMainForm.EditEPChange(Sender: TObject);
begin
  EditChanged(Sender);
end;

procedure TChessMainForm.PaletteClick(Sender: TObject);
var
  i: Integer;
begin
  FBoard.Brush := TPiece(TButton(Sender).Tag);
  FPaletteSelected := TButton(Sender);
  for i := 0 to 12 do
  begin
    if FPaletteBtns[i] = FPaletteSelected then
    begin
      FPaletteBtns[i].Color := RGBToColor(90, 130, 190);
      FPaletteBtns[i].Font.Color := clWhite;
      FPaletteBtns[i].Font.Style := [fsBold];
    end
    else
    begin
      FPaletteBtns[i].Color := clBtnFace;
      FPaletteBtns[i].Font.Color := clBlack;
      FPaletteBtns[i].Font.Style := [];
    end;
  end;
end;

procedure TChessMainForm.EnterEditMode(Sender: TObject);
begin
  if FBoard.EditMode then Exit;
  FAITimer.Enabled := False;
  CancelSearch;
  FBoard.EditMode := True;
  FEditPanel.Visible := True;
  SyncEditControls;
  PaletteClick(FPaletteBtns[1]);
  EditChanged(Self);
  UpdateUI;   // düzenleme modunda oyun butonlarını pasifleştirir
  FStatus.Caption := 'Pozisyon düzenleme modu — kareye tıklayarak taş yerleştirin';
  FAnalysis.Lines.Text :=
    'Düzenleme modu: fırçayı seçin, kareye tıklayın. ' + #13#10 +
    'Sağ tık ile taş silinir. "Oyuna Yükle" ile analiz edilebilir pozisyon oluşur.';
end;

procedure TChessMainForm.ExitEditMode(Sender: TObject);
begin
  if not FBoard.EditMode then Exit;
  FBoard.EditMode := False;
  FEditPanel.Visible := False;
  UpdateUI;
end;

procedure TChessMainForm.EditStart(Sender: TObject);
begin
  FBoard.EditPosition := StartPos;
  SyncEditControls;
  EditChanged(Self);
end;

procedure TChessMainForm.EditClear(Sender: TObject);
var
  P: TPosition;
  i: Integer;
begin
  FillChar(P, SizeOf(P), 0);
  for i := 0 to 63 do P.Board[i] := pcEmpty;
  P.Side := coWhite;
  P.Castle := 0;
  P.EP := -1;
  P.Halfmove := 0;
  P.Fullmove := 1;
  FBoard.EditPosition := P;
  SyncEditControls;
  EditChanged(Self);
end;

procedure TChessMainForm.EditApply(Sender: TObject);
var
  P: TPosition;
  WhiteK, BlackK, i: Integer;
begin
  P := FBoard.EditPosition;
  WhiteK := 0;
  BlackK := 0;
  for i := 0 to 63 do
  begin
    if P.Board[i] = pcWK then Inc(WhiteK);
    if P.Board[i] = pcBK then Inc(BlackK);
  end;
  if (WhiteK <> 1) or (BlackK <> 1) then
  begin
    ShowMessage('Pozisyonu oyuna yüklemek için tahtada bir beyaz ve bir siyah şah bulunmalı.');
    Exit;
  end;

  FAITimer.Enabled := False;
  CancelSearch;
  FGame.SetPosition(P);
  FBoard.EditMode := False;
  FEditPanel.Visible := False;
  ResetHighlights;
  FAnalysis.Lines.Text := 'Pozisyon yüklendi. Analiz için "Analiz Et" düğmesine basın.';
  UpdateUI;
  MaybeComputerMove;
end;

end.
