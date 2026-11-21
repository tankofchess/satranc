#!/usr/bin/env bash
# Satranç — kullanıcı bazlı kurulum (root gerekmez)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
APP="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

mkdir -p "$BIN" "$APP" "$ICON_DIR"
install -m 755 "$HERE/chess" "$BIN/satranj"
install -m 644 "$HERE/satranj.svg" "$ICON_DIR/satranj.svg"

cat > "$APP/satranj.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Satranç
GenericName=Satranç Oyunu ve Analiz
Comment=Tam kurallı satranç oyunu, analiz ve ilk beş hamle önerisi
Exec=$BIN/satranj
TryExec=$BIN/satranj
Icon=satranj
Categories=Game;BoardGame;
Terminal=false
StartupNotify=true
NoDisplay=false
Hidden=false
EOF

chmod 644 "$APP/satranj.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP" >/dev/null 2>&1 || true
fi
if command -v update-icon-caches >/dev/null 2>&1; then
  update-icon-caches "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
elif command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Kurulum tamamlandı: $BIN/satranj"
echo "Uygulamalar menüsünde 'Satranç' olarak görünecek."
echo "Kaldırmak için: rm -f '$BIN/satranj' '$APP/satranj.desktop' '$ICON_DIR/satranj.svg'"
