#!/bin/bash
# Dağıtım paketi (zip) oluşturur.
#
#   bash scripts/package.sh
#
# Çıktı: ../UYAP-UDF-Onizleme-<sürüm>.zip
# Paket içeriği: uygulama paketi + README + kısa kurulum kılavuzu

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="1.0.0"
APP_NAME="UYAP UDF Onizleme.app"
OUT_DIR="$(dirname "$PROJECT_DIR")"
OUT="$OUT_DIR/UYAP-UDF-Onizleme-${VERSION}.zip"
STAGE="$(mktemp -d)"

cleanup() { cd /tmp; rm -rf "$STAGE"; }
trap cleanup EXIT

if [ ! -d "$PROJECT_DIR/build/$APP_NAME" ]; then
    echo "HATA: $PROJECT_DIR/build/$APP_NAME bulunamadı. Önce 'bash scripts/build.sh' çalıştırın." >&2
    exit 1
fi

echo "==> Paket hazırlanıyor"
cp -R "$PROJECT_DIR/build/$APP_NAME" "$STAGE/"
cp "$PROJECT_DIR/README.md" "$STAGE/README.md"
cp "$PROJECT_DIR/docs/KURULUM.txt" "$STAGE/KURULUM.txt"
# README'deki ekran görüntüleri bağlantıları zip içinde de çalışsın diye
# ekran görüntüleri de aynı yol yapısıyla pakete eklenir
# (gizlilik için bulanıklaştırılmış halleri).
mkdir -p "$STAGE/docs"
cp -R "$PROJECT_DIR/docs/screenshots" "$STAGE/docs/screenshots"

echo "==> Zip oluşturuluyor: $OUT"
rm -f "$OUT"
cd "$STAGE"
zip -r -X -9 "$OUT" "$APP_NAME" README.md KURULUM.txt docs > /dev/null

echo
echo "Tamamlandı: $OUT"
ls -lh "$OUT"
