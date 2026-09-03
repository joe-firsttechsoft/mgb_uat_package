#!/bin/bash

# 這次過版預期使用的分支格式，非此格式時會詢問是否仍要繼續
# 格式：FEP_<版本>_UAT／FEP_<版本>_SIT（過版測試分支）或 FEP_<版本>（PROD 正式分支，無結尾字樣）
EXPECTED_BRANCH_PATTERN='^FEP_[0-9][0-9.-]*(_UAT|_SIT)?$'

if [ $# -gt 1 ]; then
  echo "Usage: $0 [previous_release_tag_or_commit]"
  echo " 若省略參數，會依目前分支（UAT/SIT/PROD）自動尋找最新的 uat|sit|prod/release/yyMMdd tag 作為前次 release"
  exit 1
fi

PREV_RELEASE=$1
END_COMMIT="HEAD"

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${MGBFEP_PROJECT_DIR:-$HOME/Repo/idea_clone/mgbfep-UAT}"

if [ ! -e "$PROJECT_DIR/.git" ]; then
  echo "Project git directory not found: $PROJECT_DIR"
  echo "Set MGBFEP_PROJECT_DIR to the MGBFEP repository path."
  exit 1
fi

export MGBFEP_PROJECT_DIR="$PROJECT_DIR"
REPOROOT=$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel)

# 確認目前分支，非預期格式時詢問是否仍要繼續
CURRENT_BRANCH=$(cd "$REPOROOT" && git rev-parse --abbrev-ref HEAD)
if ! [[ "$CURRENT_BRANCH" =~ $EXPECTED_BRANCH_PATTERN ]]; then
  echo "⚠️  目前分支為 '$CURRENT_BRANCH'，非預期的 FEP_<版本>[_UAT|_SIT] 格式"
  read -p "是否仍要繼續執行? (y/n): " ans
  if [ "$ans" != "y" ]; then
    echo "已取消。請切換到 FEP_<版本>_UAT / FEP_<版本>_SIT / FEP_<版本>（PROD）分支後再執行。"
    exit 1
  fi
fi

# 依目前分支決定 tag 前綴：*UAT -> uat/release、*SIT -> sit/release、
# FEP_<版本>（無結尾字樣，PROD 正式分支）-> prod/release，其餘不建立/不自動偵測 tag
case "$CURRENT_BRANCH" in
  *UAT) TAG_PREFIX="uat/release" ;;
  *SIT) TAG_PREFIX="sit/release" ;;
  FEP_[0-9]*) TAG_PREFIX="prod/release" ;;
  *) TAG_PREFIX="" ;;
esac

# 若未指定前次 release commit/tag，嘗試尋找最新的 ${TAG_PREFIX}/yyMMdd tag
# 注意：候選 tag 必須是目前 HEAD 的祖先（同一條分支歷史上），
# 避免誤選到其他分支上建立、名稱日期較新但實際不在此分支歷史內的 tag
if [ -z "$PREV_RELEASE" ]; then
  if [ -z "$TAG_PREFIX" ]; then
    echo "目前分支 '$CURRENT_BRANCH' 非 UAT/SIT/PROD 格式，無法自動判斷 tag 前綴，請手動指定前次 release commit/tag。"
    echo "Usage: $0 [previous_release_tag_or_commit]"
    exit 1
  fi
  LAST_RELEASE_TAG=""
  SKIPPED_TAGS=""
  for t in $(cd "$REPOROOT" && git tag -l "${TAG_PREFIX}/[0-9][0-9][0-9][0-9][0-9][0-9]" | sort -r); do
    if (cd "$REPOROOT" && git merge-base --is-ancestor "$t" HEAD 2>/dev/null); then
      LAST_RELEASE_TAG="$t"
      break
    fi
    SKIPPED_TAGS="$SKIPPED_TAGS $t"
  done
  if [ -z "$LAST_RELEASE_TAG" ]; then
    echo "未提供前次 release commit，且在目前分支歷史中找不到符合 ${TAG_PREFIX}/yyMMdd 格式的 tag。"
    echo "Usage: $0 [previous_release_tag_or_commit]"
    exit 1
  fi
  # 名稱較新卻不是目前 HEAD 祖先的 tag，代表它建立在其他分支上、還沒併回目前這條分支歷史，
  # 若這次沒把該分支併進來就直接比對，該分支上的異動會被漏算
  if [ -n "$SKIPPED_TAGS" ]; then
    echo "⚠️  發現名稱較新、但不在目前分支歷史中的 release tag:$SKIPPED_TAGS"
    echo "   這可能代表有分支已建立過較新的 release tag，但尚未併入目前的 '$CURRENT_BRANCH'，"
    echo "   若未併入就直接比對，該分支上的異動不會被計入這次的 diff。"
    read -p "是否仍要繼續執行? (y/n): " ans
    if [ "$ans" != "y" ]; then
      echo "已取消。請先確認上述 tag 所在分支是否需要併入 '$CURRENT_BRANCH' 後再執行。"
      exit 1
    fi
  fi
  PREV_RELEASE="$LAST_RELEASE_TAG"
  echo "未提供前次 release commit，使用最新 tag: $PREV_RELEASE"
fi

echo "=================================="
echo " Release from $PREV_RELEASE -> HEAD"
echo " Project directory: $PROJECT_DIR"
echo "=================================="

# 0️⃣ 若已有舊的 outputs/，依其建立日期改名保留，避免被下一步清空覆蓋
OUTDIR="$BASEDIR/outputs"
if [ -d "$OUTDIR" ]; then
  OUTDIR_DATE=$(stat -f '%SB' -t '%m%d' "$OUTDIR" 2>/dev/null || date +%m%d)
  ARCHIVE_DIR="$BASEDIR/outputs.$OUTDIR_DATE"
  SUFFIX=2
  while [ -e "$ARCHIVE_DIR" ]; do
    ARCHIVE_DIR="$BASEDIR/outputs.${OUTDIR_DATE}_${SUFFIX}"
    SUFFIX=$((SUFFIX + 1))
  done
  mv "$OUTDIR" "$ARCHIVE_DIR"
  echo "📦 既有 outputs/ 已改名保留為 $(basename "$ARCHIVE_DIR")"
fi

# 1️⃣ 先匯出「整個過版區間」的檔案（會清 outputs）
"$BASEDIR/export_commit_range.sh" "$PREV_RELEASE" "$END_COMMIT" || exit 1

# 2️⃣ 再產生 Release Note（補文件）
"$BASEDIR/generate_release_note.sh" "$PREV_RELEASE" || exit 1

# 3⃣ 產生 收集檔案（移除路徑結構, 方便交付）
"$BASEDIR/collect_files.sh" || exit 1

# 4⃣ 依 changes.csv 產生「兆豐UAT異動項目」xlsx（異動清單/設定檔/模組更新...）
"$BASEDIR/generate_release_xlsx.sh" || exit 1

# 5⃣ 標記本次 release tag（依分支決定前綴），作為下次執行的前次 release 依據
# 分支非 UAT/SIT/PROD 格式時不建立 tag
if [ -z "$TAG_PREFIX" ]; then
  echo "ℹ️  目前分支 '$CURRENT_BRANCH' 非 UAT/SIT/PROD 格式，不建立 release tag"
else
  NEW_RELEASE_TAG="${TAG_PREFIX}/$(date +%y%m%d)"
  if (cd "$REPOROOT" && git rev-parse -q --verify "refs/tags/$NEW_RELEASE_TAG" > /dev/null); then
    echo "⚠️  Tag $NEW_RELEASE_TAG 已存在，略過建立"
  else
    (cd "$REPOROOT" && git tag "$NEW_RELEASE_TAG" "$END_COMMIT") || exit 1
    echo "🏷️  已建立 tag: $NEW_RELEASE_TAG"
  fi
fi

echo "=================================="
echo " ✅ Release package generated"
echo " outputs/"
echo "=================================="
