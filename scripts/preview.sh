#!/bin/bash
#
# Verilen .udf dosyasının önizlemesini QuickLook penceresinde açar.
#   bash scripts/preview.sh /path/to/belge.udf
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "Kullanım: bash scripts/preview.sh /path/to/belge.udf" >&2
    exit 1
fi

echo "Açılıyor: $FILE"
qlmanage -p "$FILE"
