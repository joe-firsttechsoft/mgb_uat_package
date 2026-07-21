#!/bin/bash
set -e

# 檔名: collect_files.sh
# 功能: 將 export_files 內檔案收集到 files 資料夾（扁平化）
#       會先排除 src/test（保留例外）與 fep-release-note 路徑下的檔案，
#       排除規則跟 generate_release_xlsx.mjs 的「異動清單」共用同一份 release_exclude.mjs，
#       確保實際收集到的檔案跟 xlsx 文件內容同步。
# 顯示收集前與收集後檔案數量（因應同檔名覆蓋）

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
SRCDIR="$BASEDIR/outputs/export_files"
DESTDIR="$BASEDIR/outputs/files"

if [ ! -d "$SRCDIR" ]; then
  echo "❌ Source directory not found: $SRCDIR"
  exit 1
fi

# 每次重新收集前清空舊的 files/，避免殘留上次執行的檔案（例如舊版排除規則收集到的測試檔）
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"

echo "▶ Scanning files to collect..."

# 1️⃣ 計算原始檔案數
TOTAL_SRC=$(find "$SRCDIR" -type f | wc -l | tr -d ' ')
echo "📄 Files before collect: $TOTAL_SRC"

# 2️⃣ 產生排除 src/test（保留例外）與 fep-release-note 後應收集的清單
MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT
node "$BASEDIR/list_collect_files.mjs" "$SRCDIR" > "$MANIFEST"

TOTAL_FILTERED=$(wc -l < "$MANIFEST" | tr -d ' ')
TOTAL_EXCLUDED=$((TOTAL_SRC - TOTAL_FILTERED))
echo "🚫 Excluded (src/test, fep-release-note): $TOTAL_EXCLUDED"

# 3️⃣ 收集檔案（扁平化，允許覆蓋）
while IFS= read -r REL; do
  [ -z "$REL" ] && continue
  base=$(basename "$REL")
  cp -f "$SRCDIR/$REL" "$DESTDIR/$base"
done < "$MANIFEST"

TOTAL_DEST=$(find "$DESTDIR" -type f | wc -l | tr -d ' ')

echo "📦 Files after collect : $TOTAL_DEST"

# 4️⃣ 覆蓋提示（跟排除後的清單比對，避免把「排除」誤判成「檔名覆蓋」）
if [ "$TOTAL_FILTERED" -ne "$TOTAL_DEST" ]; then
  echo "⚠️  Detected filename overwrite:"
  echo "   Files after exclude : $TOTAL_FILTERED"
  echo "   Collected           : $TOTAL_DEST"
else
  echo "✅ No filename conflict detected"
fi
