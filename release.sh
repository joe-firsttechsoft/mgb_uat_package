#!/bin/bash

if [ $# -gt 1 ]; then
  echo "Usage: $0 [previous_release_tag_or_commit]"
  echo " 若省略參數，會自動尋找最新的 uat/release/yyMMdd tag 作為前次 release"
  exit 1
fi

PREV_RELEASE=$1
END_COMMIT="HEAD"

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${MGBFEP_PROJECT_DIR:-$HOME/Repo/idea_clone/mgbfep}"

if [ ! -d "$PROJECT_DIR/.git" ]; then
  echo "Project git directory not found: $PROJECT_DIR"
  echo "Set MGBFEP_PROJECT_DIR to the MGBFEP repository path."
  exit 1
fi

export MGBFEP_PROJECT_DIR="$PROJECT_DIR"
REPOROOT=$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel)

# 若未指定前次 release commit/tag，嘗試尋找最新的 uat/release/yyMMdd tag
if [ -z "$PREV_RELEASE" ]; then
  LAST_RELEASE_TAG=$(cd "$REPOROOT" && git tag -l 'uat/release/[0-9][0-9][0-9][0-9][0-9][0-9]' | sort | tail -n 1)
  if [ -z "$LAST_RELEASE_TAG" ]; then
    echo "未提供前次 release commit，且找不到符合 uat/release/yyMMdd 格式的 tag。"
    echo "Usage: $0 [previous_release_tag_or_commit]"
    exit 1
  fi
  PREV_RELEASE="$LAST_RELEASE_TAG"
  echo "未提供前次 release commit，使用最新 tag: $PREV_RELEASE"
fi

echo "=================================="
echo " Release from $PREV_RELEASE -> HEAD"
echo " Project directory: $PROJECT_DIR"
echo "=================================="

# 1️⃣ 先匯出「整個過版區間」的檔案（會清 outputs）
"$BASEDIR/export_commit_range.sh" "$PREV_RELEASE" "$END_COMMIT" || exit 1

# 2️⃣ 再產生 Release Note（補文件）
"$BASEDIR/generate_release_note.sh" "$PREV_RELEASE" || exit 1

# 3⃣ 產生 收集檔案（移除路徑結構, 方便交付）
"$BASEDIR/collect_files.sh" || exit 1

# 4⃣ 依 changes.csv 產生「兆豐UAT異動項目」xlsx（異動清單/設定檔/模組更新...）
"$BASEDIR/generate_release_xlsx.sh" || exit 1

# 5⃣ 標記本次 release tag，作為下次執行的前次 release 依據
NEW_RELEASE_TAG="uat/release/$(date +%y%m%d)"
if (cd "$REPOROOT" && git rev-parse -q --verify "refs/tags/$NEW_RELEASE_TAG" > /dev/null); then
  echo "⚠️  Tag $NEW_RELEASE_TAG 已存在，略過建立"
else
  (cd "$REPOROOT" && git tag "$NEW_RELEASE_TAG" "$END_COMMIT") || exit 1
  echo "🏷️  已建立 tag: $NEW_RELEASE_TAG"
fi

echo "=================================="
echo " ✅ Release package generated"
echo " outputs/"
echo "=================================="
