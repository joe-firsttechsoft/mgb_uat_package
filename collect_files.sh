#!/bin/bash
set -e

# 檔名: collect_files.sh
# 功能: 依 export_files 內容，排除 src/test（保留例外）、
#       source/fep/** 下的 .properties 後（fep-release-note 不排除，照常收集），同時產生兩種收集結果：
#         - files/         扁平化（僅保留檔名，同檔名會互相覆蓋，方便單純瀏覽/比對檔名）
#         - release_files/ 保留原始目錄結構（實際交付/覆蓋客戶環境請用這份，不會有同檔名覆蓋問題）
#       排除規則跟 generate_release_xlsx.mjs 的「異動清單」共用同一份 release_exclude.mjs，
#       確保實際收集到的檔案跟 xlsx 文件內容同步。
# 顯示收集前與收集後檔案數量（因應同檔名覆蓋）

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
SRCDIR="$BASEDIR/outputs/export_files"
DESTDIR="$BASEDIR/outputs/files"
STRUCTDIR="$BASEDIR/outputs/release_files"

if [ ! -d "$SRCDIR" ]; then
  echo "❌ Source directory not found: $SRCDIR"
  exit 1
fi

# 每次重新收集前清空舊的輸出，避免殘留上次執行的檔案（例如舊版排除規則收集到的測試檔）
rm -rf "$DESTDIR" "$STRUCTDIR"
mkdir -p "$DESTDIR" "$STRUCTDIR"

echo "▶ Scanning files to collect..."

# 1️⃣ 計算原始檔案數
TOTAL_SRC=$(find "$SRCDIR" -type f | wc -l | tr -d ' ')
echo "📄 Files before collect: $TOTAL_SRC"

# 2️⃣ 產生排除後應收集的清單
MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT
node "$BASEDIR/list_collect_files.mjs" "$SRCDIR" > "$MANIFEST"

TOTAL_FILTERED=$(wc -l < "$MANIFEST" | tr -d ' ')
TOTAL_EXCLUDED=$((TOTAL_SRC - TOTAL_FILTERED))
echo "🚫 Excluded (src/test, .properties): $TOTAL_EXCLUDED"

# 3️⃣ 收集檔案：files/ 扁平化、release_files/ 保留目錄結構
while IFS= read -r REL; do
  [ -z "$REL" ] && continue
  base=$(basename "$REL")
  cp -f "$SRCDIR/$REL" "$DESTDIR/$base"

  mkdir -p "$STRUCTDIR/$(dirname "$REL")"
  cp -f "$SRCDIR/$REL" "$STRUCTDIR/$REL"
done < "$MANIFEST"

TOTAL_DEST=$(find "$DESTDIR" -type f | wc -l | tr -d ' ')
TOTAL_STRUCT=$(find "$STRUCTDIR" -type f | wc -l | tr -d ' ')

echo "📦 Files after collect (files/, 扁平化)         : $TOTAL_DEST"
echo "📁 Files after collect (release_files/, 保留目錄): $TOTAL_STRUCT"

# 4️⃣ 覆蓋提示（跟排除後的清單比對，避免把「排除」誤判成「檔名覆蓋」；只有扁平化的 files/ 會有覆蓋問題）
if [ "$TOTAL_FILTERED" -ne "$TOTAL_DEST" ]; then
  echo "⚠️  Detected filename overwrite in files/（release_files/ 保留目錄結構不受影響）:"
  echo "   Files after exclude : $TOTAL_FILTERED"
  echo "   Collected (flat)    : $TOTAL_DEST"
else
  echo "✅ No filename conflict detected"
fi
