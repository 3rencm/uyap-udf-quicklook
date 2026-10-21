#!/bin/bash
#
# Uygulamayı kurar, QuickLook eklentisini kaydeder ve önbelleği yeniler.
#
#   bash scripts/install.sh                -> /Applications (yazılabiliyorsa), aksi halde ~/Applications
#   bash scripts/install.sh ~/Applications  -> yalnızca kullanıcı için
#   bash scripts/install.sh /Applications  -> sistem geneli (sudo gerekebilir)
#
# ÖNEMLİ: Uygulamayı kopyalamak tek başına yeterli değildir. Preview Extension'ın
# PlugInKit veritabanına "pluginkit -a" ile eklenmesi gerekir; aksi halde QuickLook
# eklentiyi bulsa bile önizleme isteğini iletemez.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UYAP UDF Onizleme"
SOURCE_APP="$ROOT/build/$APP_NAME.app"

# Varsayılan hedef: /Applications yazılabiliyorsa orası, değilse ~/Applications
if [[ $# -ge 1 ]]; then
    TARGET_DIR="$1"
elif [[ -w /Applications ]]; then
    TARGET_DIR="/Applications"
else
    TARGET_DIR="$HOME/Applications"
fi

TARGET_APP="$TARGET_DIR/$APP_NAME.app"
APPEX="$TARGET_APP/Contents/PlugIns/UDFPreview.appex"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Önce derleyin:  bash \"$ROOT/scripts/build.sh\"" >&2
    exit 1
fi

echo "==> Kuruluyor: $TARGET_APP"
mkdir -p "$TARGET_DIR"
ditto "$SOURCE_APP" "$TARGET_APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> LaunchServices'a kaydediliyor"
"$LSREGISTER" -f "$TARGET_APP"

echo "==> QuickLook önbelleği yenileniyor"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "==> QuickLook eklentisi kaydediliyor"
# Preview Extension'ın PlugInKit veritabanına eklenmesi gerekir; aksi halde
# QuickLook eklentiyi keşfeder ama isteği iletemez.
# Uygulama kopyalandıktan hemen sonra eklenti taraması devrede olabildiği için
# kayıt doğrulanana kadar birkaç kez denenir.
PLUGIN_ID="com.3rencm.udfquicklook.preview"
for attempt in 1 2 3 4 5; do
    pluginkit -a "$APPEX" >/dev/null 2>&1 || true
    if pluginkit -m -A -D -i "$PLUGIN_ID" 2>/dev/null | grep -q "$PLUGIN_ID"; then
        echo "    eklenti kaydedildi (deneme $attempt)"
        break
    fi
    sleep 2
done

if ! pluginkit -m -A -D -i "$PLUGIN_ID" 2>/dev/null | grep -q "$PLUGIN_ID"; then
    echo "    UYARI: eklenti kaydedilemedi. Şu komutu elle çalıştırın:" >&2
    echo "      pluginkit -a \"$APPEX\"" >&2
fi

echo
echo "Kurulum tamamlandı."
echo "Finder önizleme panelinde görmek için bir .udf dosyası seçin."
echo "Finder'ı yeniden başlatmak isterseniz:  killall Finder"
echo "Hızlı önizleme için:                      qlmanage -p /path/to/belge.udf"
echo "Belgeyi arayüz olmadan incelemek için:    \"$TARGET_APP/Contents/MacOS/udf-inspect\" /path/to/belge.udf"
