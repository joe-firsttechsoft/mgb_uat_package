#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <previous_release_tag_or_commit>"
  exit 1
fi

PREV_RELEASE=$1
END_COMMIT="HEAD"

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

echo "=================================="
echo " Release from $PREV_RELEASE -> HEAD"
echo "=================================="

# 1️⃣ 先匯出「整個過版區間」的檔案（會清 output）
"$BASEDIR/export_commit_range.sh" "$PREV_RELEASE" "$END_COMMIT" || exit 1

# 2️⃣ 再產生 Release Note（補文件）
"$BASEDIR/generate_release_note.sh" "$PREV_RELEASE" || exit 1

# 3⃣ 產生 收集檔案（移除路徑結構, 方便交付）
"$BASEDIR/collect_files.sh" || exit 1

echo "=================================="
echo " ✅ Release package generated"
echo " output/"
echo "=================================="
