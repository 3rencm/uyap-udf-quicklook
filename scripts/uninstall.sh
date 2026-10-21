#!/bin/bash
#
# Uygulamayı kaldırır ve QuickLook eklentisini temizler.
#
#   bash scripts/uninstall.sh              -> /Applications ve ~/Applications altındaki kopyaları siler
#   bash scripts/uninstall.sh ~/Applications -> yalnızca belirtilen konumu temizler
set -euo pipefail

APP_NAME="UYAP UDF Onizleme"
PLUGIN_ID="com.3rencm.udfquicklook.preview"

if [[ $# -ge 1 ]]; then
    TARGET_DIRS=("$1")
else
    TARGET_DIRS=("/Applications" "$HOME/Applications")
fi

for TARGET_DIR in "${TARGET_DIRS[@]}"; do
    TARGET_APP="$TARGET_DIR/$APP_NAME.app"
    APPEX="$TARGET_APP/Contents/PlugIns/UDFPreview.appex"

    if [[ -d "$APPEX" ]]; then
        pluginkit -r "$APPEX" >/dev/null 2>&1 || true
    fi

    if [[ -d "$TARGET_APP" ]]; then
        echo "==> Kaldırılıyor: $TARGET_APP"
        rm -rf "$TARGET_APP"
    else
        echo "Bulunamadı: $TARGET_APP"
    fi

    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$LSREGISTER" -u "$TARGET_APP" >/dev/null 2>&1 || true
done

qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "Kaldırma tamamlandı."
