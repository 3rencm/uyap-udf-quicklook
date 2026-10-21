#!/bin/bash
#
# UDF QuickLook Preview Extension paketini derler:
#   build/UYAP UDF Onizleme.app
#     Contents/MacOS/UDFQuickLook              -> ana uygulama (extension barındırıcısı)
#     Contents/PlugIns/UDFPreview.appex        -> QuickLook Preview Extension
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UYAP UDF Onizleme"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/UDFPreview.appex"

echo "==> Swift derlemesi (release)"
swift build -c release --package-path "$ROOT"

echo "==> App paketi hazırlanıyor"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

# Ana uygulama
cp "$ROOT/.build/release/UDFQuickLook" "$APP/Contents/MacOS/UDFQuickLook"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/UDFQuickLook"

# Komut satırı inceleme aracı (sandbox'sız)
cp "$ROOT/.build/release/UDFInspect" "$APP/Contents/MacOS/udf-inspect"
chmod +x "$APP/Contents/MacOS/udf-inspect"

# Preview Extension
cp "$ROOT/.build/release/UDFPreviewExtension" "$APPEX/Contents/MacOS/UDFPreviewExtension"
cp "$ROOT/Resources/PreviewExtension-Info.plist" "$APPEX/Contents/Info.plist"
printf '????' > "$APPEX/Contents/PkgInfo"
chmod +x "$APPEX/Contents/MacOS/UDFPreviewExtension"

echo "==> Uygulama ikonu üretiliyor"
if ! swift "$ROOT/Tools/makeicon.swift" "$APP/Contents/Resources/AppIcon.icns"; then
    echo "    (ikon üretilemedi, paket onsiz devam ediyor)"
fi

echo "==> İmza atılıyor (önce extension, sonra ana uygulama)"
# macOS 27'de eklentilerin sandbox'lanması zorunludur; bu yüzden entitlements ekleniyor.
codesign --force --sign - \
    --entitlements "$ROOT/Resources/UDFPreview.entitlements" \
    "$APPEX" 2>/dev/null || echo "    (extension imzası atlanadı)"
# Ana uygulama sandbox'lanmaz: QuickLook eklentisini PlugInKit'e kaydedebilmelidir.
codesign --force --sign - "$APP" 2>/dev/null || echo "    (uygulama imzası atlanadı)"

# İnceleme aracı sandbox'sız çalışmalı (komut satırından dosya okuyabilmeli).
codesign --force --sign - "$APP/Contents/MacOS/udf-inspect" 2>/dev/null || true

echo
echo "Derleme tamamlandı: $APP"
echo "Kurulum için:  bash \"$ROOT/scripts/install.sh\""
