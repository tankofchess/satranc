# Satranç — Oyun ve Analiz (Lazarus / Free Pascal)

Lazarus LCL ile yazılmış, tam kurallara sahip bir satranç uygulaması.
İnsan–insan veya insan–bilgisayar oynayabilir, pozisyonu analiz ettirebilirsiniz.

## Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `chess.lpi` / `chess.lpr` | Lazarus proje dosyaları |
| `ChessEngine.pas` | Kurallar, hamle üretimi, FEN, SAN, oyun sonu kontrolleri |
| `ChessAI.pas` | Alpha-beta arama, değerlendirme, analiz |
| `ChessBoardView.pas` | Grafik tahta bileşeni (sembol taşlar, tıklama/sürükleme) |
| `ChessMain.pas` | Ana pencere, menüler, geçmiş, FEN/PGN |
| `test_perft.pas` | Kural motoru doğrulama testi (6 referans pozisyonu) |
| `test_ai.pas` | Yapay zekâ motoru kısa testi |
| `kbn.res` | K+F+A, K+V, K+R, K+R+A, K+R+F, zıt renk K+F+F ve K+V vs K+R kesin oyun sonu tabloları (derlemeye gömülür) |
| `tools/kbn_gen.cpp` | K+F+A tablosunu yeniden üreten yardımcı program |
| `tools/basic_gen.cpp` | K+V ve K+R tablolarını yeniden üreten yardımcı program |
| `tools/krb_gen.cpp` | K+R+F tablosunu yeniden üreten yardımcı program |
| `tools/kbb_gen.cpp` | Zıt renk K+F+F tablosunu yeniden üreten yardımcı program |
| `tools/krn_gen.cpp` | K+R+A tablosunu yeniden üreten yardımcı program |
| `tools/kqkr_gen.cpp` | K+V vs K+R işaretli DTM tablosunu yeniden üreten yardımcı program |
| `paketleme/` | DEB, RPM ve taşınabilir kurulum için launcher, ikon ve paket tanım dosyaları |
| `eski/` | Önceki sürümün ikilileri ve dağıtım paketleri (karşılaştırma için ayrı tutulur) |

## Derleme

Lazarus IDE ile `chess.lpi` dosyasını açıp **Derle (F9)** yapın,
veya komut satırından:

```bash
lazbuild chess.lpi
./chess
```

`kbn.res` dosyası `ChessAI.pas` içindeki `{$R kbn.res}` yönergesiyle
derlemeye gömülür; yedi kesin bitiş tablosunu birlikte içerir ve kaynak
kopyasında bulunması zorunludur. Tabloları yeniden üretmek için `tools/`
altındaki üreteçleri çalıştırıp

```bash
lazres kbn.res kbn.z kq.z kr.z kqkr.z krb.z kbb.z krn.z
```

komutuyla kaynağı oluşturun.

### Windows sürümü

`dist/Windows/` klasöründe üç dağıtım dosyası var:

- `Satranc-Win64-v1.0.zip` — kaynak dosyaları ve `chess.exe` ikilisini içerir.
- `satranj.exe` — tek başına çalıştırılabilir **Windows 64-bit** ikilisi.
  Kurulum gerektirmez; kopyalayıp çalıştırın.
- `SatranjPortable.paf.exe` — PortableApps.com Format kurulum dosyası. Resmî
  PortableApps.com Installer 3.9.24 ile üretilmiştir ve paketin içinde yalnızca
  `satranj.exe`, PAF launcher'ı, ikonlar ve metadata vardır; Lazarus/Pascal
  kaynak kodu içermez.

İkili yalnızca Windows'un standart DLL'lerini (`kernel32`, `user32`, `gdi32`,
`comctl32`, `comdlg32`, `ole32`, `oleaut32`, `shell32`, `version`) kullanır.
Yedi kesin oyun sonu tablosu ve PGN düzeltmeleri bu ikili dosyadadır. Üç tekrar,
pat ve 50 hamle gibi beraberliklerde PGN sonucu `1/2-1/2`, matta `1-0` / `0-1`
yazılır. Yükleme kopyaları `github-yukleme/Windows/` klasöründedir. Eski Windows
derlemesi karşılaştırma için `eski/chess.exe` ve `eski/dist/` altında tutulur.

Linux üzerinden yeniden üretmek için (FPC 3.2.2 çapraz derleyici + LCL win32
gerekir):

```bash
lazbuild --os=win64 --cpu=x86_64 --ws=win32 \
  --compiler=/tmp/opencode/ppcwin64 -B chess.lpi
strip --strip-debug chess.exe
```

### Linux sürümü

`dist/Linux/` klasöründe üç dağıtım dosyası var:

- `Satranc-Linux64-v1.0.tar.gz` — taşınabilir paket. Açıp `kurulum.sh`
  dosyasını çalıştırın; uygulama `~/.local/bin/satranj` altına kurulur,
  `satranj.svg` ikonu kullanıcı ikon yoluna kopyalanır ve menüye `Satranç`
  olarak eklenir. Root gerekmez.
- `satranj_1.0_amd64.deb` — Debian / Ubuntu / Pardus için kurulabilir paket:

  ```bash
  sudo apt install ./satranj_1.0_amd64.deb
  ```

- `satranj-1.0-1.x86_64.rpm` — Fedora / openSUSE / Pardus RPM için kurulabilir
  paket:

  ```bash
  sudo dnf install ./satranj-1.0-1.x86_64.rpm
  # veya
  sudo zypper install ./satranj-1.0-1.x86_64.rpm
  ```

GTK2 tabanlıdır; Gtk2, standart X11 kütüphaneleri, `desktop-file-utils` ve
`hicolor-icon-theme` gerekir. Kurulumdan sonra menüde `Satranç` girişi ve
`satranj` komutu oluşur; masaüstü/ikon önbelleği paket betikleriyle tazelenir.
Yükleme kopyaları `github-yukleme/Linux/` klasöründedir. Her platform
klasöründe yalnızca o platformun dosyalarını kapsayan `SHA256SUMS.txt` vardır;
doğrulamak için ilgili klasörde `sha256sum -c SHA256SUMS.txt` çalıştırın.

RPM'i kaynaktan yeniden üretmek için `paketleme/satranj.spec` kullanılabilir:

```bash
mkdir -p ~/rpmbuild/{SOURCES,SPECS}
STAGE=$(mktemp -d)
mkdir -p "$STAGE/satranj-1.0"
install -m 0755 chess "$STAGE/satranj-1.0/satranj"
install -m 0644 paketleme/satranj.desktop paketleme/satranj.svg README.md "$STAGE/satranj-1.0/"
tar -C "$STAGE" -czf ~/rpmbuild/SOURCES/satranj-1.0.tar.gz satranj-1.0
cp paketleme/satranj.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/satranj.spec
```

## Özellikler

- **Tam kurallar:** rok, en passant, terfi (Vezir/Kale/Fil/At seçimi),
  şah/şah mat, pat, 50 hamle kuralı, üç tekrar.
- **Taş görünümü:** Mıknatıslı satranç tahtalarındaki standart semboller
  kullanılır — beyaz için açık hat şekilleri (♙♘♗♖♕♔), siyah için dolu
  şekiller (♟♞♝♜♛♚). Koyu mürekkep + açık halka sayesinde her iki karede
  de net okunur.
- **Arayüz:** Taşa tıklayıp hedefe tıklayarak veya sürükleyerek hamle yapma.
  Seçili kare mavi, geçerli hedefler nokta/halka, son hamle sarı,
  şah kırmızı, önerilen hamle yeşil gösterilir.
- **Pencere boyutu:** Tahta her zaman kare kalır ve kullanılabilir alanda
  otomatik ortalanır; araç çubuğu ve paneller pencereyle birlikte ölçeklenir
  (en küçük pencere 700×560). Analiz paneli 215 piksel yükseklikte ve
  yatay kaydırmalıdır, hamle listesi satırları kırpılmaz.
- **Oynama:** Rakip seçenekleri — iki oyuncu, bilgisayar siyah, bilgisayar beyaz.
  **Açılış kitabı kullanılmaz**; açılışta da gerçek arama oynar. Arama
  derinliği **1–6 yarım hamle** arasında ayarlanabilir. Arama arka plan
  thread’inde çalışır; arayüz donmaz. Arama sürerken aynı düğmeye tekrar basarak
  iptal edebilirsiniz. Varsayılan derinlik 3'tür. Arama seçilen derinlikte
  biter; süre dolmadan gereksiz düşünmez (derinlik 3 ~0,3 sn, derinlik 6
  ~0,6–1,4 sn). Null-move pruning, geç hamle indirimi (LMR),
  gelişme/merkez/erken vezir çıkışı terimleri ve quiescence sayesinde aynı
  derinlikte daha güçlü oynar.
- **Analiz:** `Analiz Et` düğmesi alpha-beta motorunun **en iyi 5 hamlesini**
  SAN ve centipawn değerlendirmesiyle listeler; derinliği ve ziyaret edilen
  düğüm sayısını gösterir. Motor **quiescence search**, **killer/history**
  sıralama, **Zobrist hash + transposition table** (131.072 girdi, en iyi hamle
  önerisi), **şah genişletmesi**, 50-hamle, üç tekrar ve **yetersiz malzeme**
  beraberlik kontrolleri kullanır. FIDE 5.2.2'ye göre K+F vs K, K+A vs K,
  aynı renk K+F+F vs K ve bütün filleri aynı renkte olan konumlar otomatik
  berabere sayılır. K+A vs K+A ve K+A+A vs K zorla mat getirmez ancak mat
  mümkün olduğu için otomatik berabere değildir; oyun üç tekrar ya da 50 hamle
  kuralına kadar devam eder. Farklı renk K+F+F vs K da devam eder. K+F+A,
  K+V, K+R, K+R+A, K+R+F, zıt renk K+F+F ve K+V vs K+R için toplam ~33 MB
  sıkıştırılmış kesin oyun sonu tabloları gömülüdür; matı en kısa yoldan
  zorlar. K+V vs K+R tablosu işaretlidir: vezir tarafı kazanırsa pozitif,
  kale tarafı kazanırsa negatif, zorla mat yoksa sıfır değer tutar; siyah
  vezir / beyaz kale konumları 180° aynayla aynı tabloya eşlenir. Rastgele
  500 K+V vs K+R konumunun tamamı tablo sonucuyla uyumlu bitmiştir
  (kazanma/kaybetme/beraberlik ayrımı dahil). En kötü DTM değerleri K+V'de 67,
  K+R'de 19, K+R+F'te 33, zıt renk K+F+F'te 39, K+R+A'da 33 ve K+V vs K+R'de
  101 yarı hamledir; K+V vs K+R'de 101 yarı hamle gereken konumlarda sonuç
  yine FIDE 50 hamle kuralı tarafından belirlenir. K+R+A tablosunda zorla mat
  olmayan (örneğin kale hemen alınabilen) konumlarda genel arama ve
  Chenard benzeri kralı köşeye sürme değerlendirmesi devreye girer; kale
  askıda olmayan 63 rastgele konumun tamamı tekrarsız matla bitmiştir. Aynı
  renk K+F+F vs K ise FIDE 5.2.2 gereği otomatik beraberliktir.
  Değerlendirme malzeme, taş-mevki tabloları, çift fil, piyon yapısı (çift/
  izole/geçmiş piyon), kale açık dosya/7. sıra, kral güvenliği ve **hareket
  alanı** (legal hamle başına 3 cp, oyun sonunda 1 cp; toplam en fazla 1 piyon
  = 100 cp) içerir. En iyi hamle tahtada yeşil dolu kare, ilk 5 hamlenin
  hedefleri ince yeşil çerçeveyle işaretlenir.
- **Elle pozisyon kurma:** `Pozisyon Düzenle (elle taş diz)` düğmesi veya
  `Ctrl+E` ile düzenleme moduna geçin. Fırçayı seçip kareye tıklayarak taş
  koyun, sağ tıklayarak silin. Sıra, rok hakları ve en passant karesini
  ayarlayabilir; FEN canlı güncellenir. `Oyuna Yükle ve Analiz Et` düğmesi
  oluşturduğunuz pozisyonu motora aktarır (bir beyaz ve bir siyah şah gerekir).
- **Diğer:** Hamle geçmişi (SAN), geri alma, FEN yükleme/kopyalama,
  PGN kaydetme (başlangıç FEN'i gerçek pozisyondan yazılır), tahtayı çevirme,
  geçerli hamle gösterimini açma/kapatma.

## Kısayollar

- `Ctrl+N` — Yeni oyun
- `Ctrl+Z` — Hamleyi geri al
- `Ctrl+E` — Pozisyon düzenleyiciyi aç

## Doğrulama

Kurallar 6 standart perft pozisyonunda 3. derinliğe kadar doğrulanmıştır:

```bash
fpc -Mobjfpc -Sh test_perft.pas && ./test_perft
```

Beklenen değerlerden biri: başlangıç pozisyonu → `20, 400, 8902`.

Ayrıca self-play regresyonlarında açılışta gerçek arama çalışır (ör. `1.Nf3`),
zıt renk K+F+F vs K 16 hamlede matla biter, K+V/K+R/K+R+F rastgele 20'şer
konumun tamamı matla sonuçlanır, K+R+F başlangıç konumu 10 hamlede, zıt renk
K+F+F başlangıç konumu 16 hamlede tekrarsız mat edilir; 134 beyaz ve 144 siyah
rastgele zorla-mat K+F+F konumunun tamamı matla biter, 500 rastgele
K+V vs K+R konumunun tamamı kesin tablo sonucuyla uyumludur ve kale askıda
olmayan 63 rastgele K+R+A konumunun tamamı ortalama 0,7 saniyede matla biter
(berabere/tekrar yok). Kullanıcının K+R+A pozisyonu 25 yarım hamlede, aynı
pozisyonun siyah saldiran aynası da 25 yarım hamlede matla sonuçlanır. Pat,
50 hamle, üç tekrar ve FIDE yetersiz malzeme kontrolleri ayrı testlerle
doğrulanır.
