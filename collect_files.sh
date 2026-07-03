#!/bin/bash

# 檔名: collect_files.sh
# 功能: 將 export_files 內所有檔案收集到 files 資料夾（扁平化）
# 顯示收集前與收集後檔案數量（因應同檔名覆蓋）

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
SRCDIR="$BASEDIR/outputs/export_files"
DESTDIR="$BASEDIR/outputs/files"

if [ ! -d "$SRCDIR" ]; then
  echo "❌ Source directory not found: $SRCDIR"
  exit 1
fi

mkdir -p "$DESTDIR"

echo "▶ Scanning files to collect..."

# 1️⃣ 計算原始檔案數
TOTAL_SRC=$(find "$SRCDIR" -type f | wc -l | tr -d ' ')
echo "📄 Files before collect: $TOTAL_SRC"

# 2️⃣ 收集檔案（扁平化，允許覆蓋）
COLLECTED=0

find "$SRCDIR" -type f -print0 | while IFS= read -r -d '' file; do
  base=$(basename "$file")
  cp -f "$file" "$DESTDIR/$base"
  COLLECTED=$((COLLECTED + 1))
done

# ⚠️ subshell 問題，重新計算實際結果
TOTAL_DEST=$(find "$DESTDIR" -type f | wc -l | tr -d ' ')

echo "📦 Files after collect : $TOTAL_DEST"

# 3️⃣ 覆蓋提示
if [ "$TOTAL_SRC" -ne "$TOTAL_DEST" ]; then
  echo "⚠️  Detected filename overwrite:"
  echo "   Source files : $TOTAL_SRC"
  echo "   Collected    : $TOTAL_DEST"
else
  echo "✅ No filename conflict detected"
fi
