#!/bin/bash
# Ekran görüntülerini yeniden çeker.
#
#   bash scripts/shots.sh                       -> varsayılan imzalı belge
#   bash scripts/shots.sh /path/to/belge.udf    -> belirli bir belge
#
# Çıktı: docs/screenshots/*.png (4 adet)
#   01-finder-onizleme-paneli.png  -> Finder önizleme paneli
#   02-hizli-onizleme.png          -> hızlı önizleme penceresi (Boşluk)
#   03-uygulama.png                -> uygulama penceresi
#   04-imzasiz-belge.png           -> imzasız belge (sentetik test belgesi)
#
# NOT: Üretilen görseller kişisel veri içerebilir (taraf isimleri, imza bilgisi).
# Yayına çıkmadan önce gerekli alanları bulanıklaştırın.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SHOTS_DIR="$PROJECT_DIR/docs/screenshots"
WORK_DIR="/tmp/UDFShots"
APP="/Applications/UYAP UDF Onizleme.app"

# Örnek belgeler: deponun DIŞINDA tutulur (kazara commit edilmesinler diye).
SAMPLES_DIR="/Users/ecmeyva/Dosyalar/minimax-code/uyap-samples"

# İmzalı belge: verilirse onu kullan, yoksa örnek klasöründeki düzenlenmiş belge.
SOURCE_FILE="${1:-$SAMPLES_DIR/Dava_Dilekcesi.udf}"
SIGNED="$WORK_DIR/Dava_Dilekcesi.udf"
UNSIGNED="$WORK_DIR/test_imzasiz.udf"

mkdir -p "$WORK_DIR" "$SHOTS_DIR"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "HATA: Belge bulunamadı: $SOURCE_FILE" >&2
    exit 1
fi
# Aynı dosya ise kopyalama (dosya kendisiyle kopyalanamaz).
if [ "$(cd "$(dirname "$SOURCE_FILE")" && pwd)/$(basename "$SOURCE_FILE")" != "$SIGNED" ]; then
    cp "$SOURCE_FILE" "$SIGNED"
fi

# İmzasız örnek belge.
if [ -f "$SAMPLES_DIR/test_imzasiz.udf" ]; then
    cp "$SAMPLES_DIR/test_imzasiz.udf" "$UNSIGNED"
fi

echo "==> Kaynak belge: $SOURCE_FILE"
"$APP/Contents/MacOS/udf-inspect" "$SIGNED" 2>&1 | grep -E "^(Başlık|Mahkeme|Paragraf|İmza)" || true

list_windows() { swift "$PROJECT_DIR/Tools/listwindows.swift" "$@" 2>/dev/null; }

capture() { # <pencere filtresi> <cikti dosyasi> <aciklama>
    local filter="$1" out="$2" note="$3"
    local id
    id=$(list_windows "$filter" | awk -F'\t' '$3==0 && $4>200 {print $1; exit}')
    if [ -z "$id" ]; then
        echo "  ! $note: pencere bulunamadı (atlandı)" >&2
        return 1
    fi
    screencapture -x -o -l "$id" "$out"
    echo "  ✓ $note -> $(basename "$out") (pencere $id)"
}

# ---------------------------------------------------------------- 03: uygulama
echo "==> 03: uygulama penceresi"
open -a "$APP" 2>/dev/null
sleep 3
capture "UYAP UDF Önizleme" "$SHOTS_DIR/03-uygulama.png" "uygulama penceresi"

# ------------------------------------------------- 01: Finder önizleme paneli
echo "==> 01: Finder önizleme paneli"
open -R "$SIGNED"
sleep 4
# Finder penceresi dosya adıyla değil, dosyanın bulunduğu klasör adıyla listelenir.
FOLDER_NAME="$(basename "$(dirname "$SIGNED")")"
capture "$FOLDER_NAME" "$SHOTS_DIR/01-finder-onizleme-paneli.png" "Finder paneli"

# ------------------------------------------------------ 02: hızlı önizleme
echo "==> 02: hızlı önizleme penceresi"

quick_look_panel() { # hızlı önizleme panelini açar, pencere kimliğini yazar
    local qid=""
    # Önce açık bir panel varsa kapat (menü öğesi "Göz At" olarak dönmeli).
    if list_windows "finder" | awk -F'\t' '$3==3 && $4>500 {found=1} END{exit !found}'; then
        osascript -e 'tell application "System Events" to tell process "Finder" to key code 53' >/dev/null 2>&1 || true
        sleep 2
    fi

    open -R "$SIGNED"
    sleep 2
    osascript <<'OSA' >/dev/null 2>&1
tell application "Finder" to activate
delay 1
tell application "System Events" to tell process "Finder" to click menu item "Göz At" of menu 1 of menu bar item "Dosya" of menu bar 1
OSA
    sleep 5
    qid=$(list_windows "finder" | awk -F'\t' '$3==3 && $4>500 && $5>500 {print $1; exit}')
    echo "$qid"
}

QL_ID="$(quick_look_panel)"
if [ -z "$QL_ID" ]; then
    echo "  ! panel bulunamadı, yeniden deneniyor…" >&2
    QL_ID="$(quick_look_panel)"
fi
if [ -n "$QL_ID" ]; then
    screencapture -x -o -l "$QL_ID" "$SHOTS_DIR/02-hizli-onizleme.png"
    echo "  ✓ hızlı önizleme -> 02-hizli-onizleme.png (pencere $QL_ID)"
else
    echo "  ! hızlı önizleme penceresi bulunamadı (atlandı)" >&2
fi

# ------------------------------------------------------ 04: imzasız belge
if [ -f "$UNSIGNED" ]; then
    echo "==> 04: imzasız belge"
    pkill -f "qlmanage -p" 2>/dev/null || true
    sleep 1
    (qlmanage -p "$UNSIGNED" >/dev/null 2>&1 &)
    # Pencere geç açılabilir; pencere görünene kadar bekle.
    Q_ID=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        Q_ID=$(list_windows "qlmanage" | awk -F'\t' '$3==0 && $4>700 && $5>500 {print $1; exit}')
        [ -n "$Q_ID" ] && break
    done
    if [ -n "$Q_ID" ]; then
        screencapture -x -o -l "$Q_ID" "$SHOTS_DIR/04-imzasiz-belge.png"
        echo "  ✓ imzasız belge -> 04-imzasiz-belge.png (pencere $Q_ID)"
    else
        echo "  ! qlmanage penceresi bulunamadı (atlandı)" >&2
    fi
    pkill -f "qlmanage -p" 2>/dev/null || true
else
    echo "  ! imzasız test belgesi yok, 04 atlandı ($UNSIGNED)" >&2
fi

echo
echo "==> Üretilen görseller:"
ls -la "$SHOTS_DIR"
echo
echo "==> Sonraki adımlar:"
echo "   1) Kişisel veri içeren alanları bulanıklaştırın"
echo "   2) bash scripts/package.sh"
echo "   3) git add -A && git commit -m '...' && git push origin main"
echo "   4) gh release upload v1.0.0 ../UYAP-UDF-Onizleme-1.0.0.zip --clobber"
