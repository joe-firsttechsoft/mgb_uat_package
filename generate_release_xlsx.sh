#!/bin/bash
set -e

# 檔名: generate_release_xlsx.sh
# 功能: 呼叫 generate_release_xlsx.mjs，將 outputs/changes.csv 轉成
#       「<yyyyMMdd>-P1-2 兆豐UAT異動項目.xlsx」，輸出到 outputs/
# 使用: ./generate_release_xlsx.sh [changes.csv 路徑]

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$BASEDIR/outputs"
CSV="${1:-$OUTDIR/changes.csv}"
DATE_COMPACT=$(date +%Y%m%d)
OUTXLSX="$OUTDIR/${DATE_COMPACT}-P1-2 兆豐UAT異動項目.xlsx"

if [ ! -f "$CSV" ]; then
  echo "找不到 CSV 檔案: $CSV"
  exit 1
fi

if [ ! -d "$BASEDIR/node_modules/exceljs" ]; then
  echo "安裝 xlsx 產生所需套件 (exceljs)..."
  (cd "$BASEDIR" && npm install --no-audit --no-fund) || exit 1
fi

mkdir -p "$OUTDIR"
node "$BASEDIR/generate_release_xlsx.mjs" "$CSV" "$OUTXLSX"

echo "✅ Release xlsx generated:"
echo "   $OUTXLSX"
