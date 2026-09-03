#!/bin/bash
set -e
# Usage: ./export_commit_range.sh <prev_release_commit_or_tag> <end_commit>
# Example: ./export_commit_range.sh v1.2.2 HEAD
if [ $# -ne 2 ]; then
  echo "Usage: $0 <prev_release_commit_or_tag> <end_commit>"
  exit 1
fi
START=$1
END=$2
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${MGBFEP_PROJECT_DIR:-$HOME/Repo/idea_clone/mgbfep-UAT}"
OUTDIR="$BASEDIR/outputs"
FILEDIR="$OUTDIR/export_files"
CSV="$OUTDIR/changes.csv"
COMMITS="$OUTDIR/commits.csv"
PATCH="$OUTDIR/changes.patch"

# ── 切換到指定專案 repo root，確保所有 git 路徑一致 ──
if [ ! -e "$PROJECT_DIR/.git" ]; then
  echo "Project git directory not found: $PROJECT_DIR"
  echo "Set MGBFEP_PROJECT_DIR to the MGBFEP repository path."
  exit 1
fi

REPOROOT=$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel)
cd "$REPOROOT"

# 若 outputs 已存在且非空，詢問是否清空
if [ -d "$OUTDIR" ] && [ "$(ls -A "$OUTDIR")" ]; then
  read -p "⚠️ outputs not empty, clear and continue? (y/n): " ans
  [ "$ans" != "y" ] && exit 1
  rm -rf "$OUTDIR"/*
fi
mkdir -p "$FILEDIR"

# ── 計算含 START 本身的 log 範圍 ──
if git rev-parse --verify "${START}~1" > /dev/null 2>&1; then
  LOG_RANGE="${START}~1..${END}"
else
  LOG_RANGE="${END}"
fi

echo "檔案名稱,檔案路徑,動作,Commit Message" > "$CSV"
echo "Commit,Author,Date,Message" > "$COMMITS"

echo "Collecting commit list..."
git -c core.quotepath=false log "$LOG_RANGE" \
  --pretty=format:'"%H","%an","%ad","%s"' \
  --date=iso >> "$COMMITS"

echo "Exporting patch..."
git diff "$START" "$END" > "$PATCH"

echo "Collecting changed files..."

while IFS= read -r -d '' STATUS; do
  case "$STATUS" in
    A|M|D)
      IFS= read -r -d '' FILE
      case "$STATUS" in
        A) ACTION="新增" ;;
        M) ACTION="修改" ;;
        D) ACTION="刪除" ;;
      esac
      TARGET="$FILE"
      ;;
    R*)
      IFS= read -r -d '' OLD
      IFS= read -r -d '' NEW
      ACTION="重新命名"
      TARGET="$NEW"
      ;;
    C*)
      IFS= read -r -d '' OLD
      IFS= read -r -d '' NEW
      ACTION="複製"
      TARGET="$NEW"
      ;;
    *)
      IFS= read -r -d '' FILE
      ACTION="$STATUS"
      TARGET="$FILE"
      ;;
  esac

  NAME=$(basename "$TARGET")
  DIR=$(dirname "$TARGET")

  # ── 取得 commit message（路徑現在與 repo root 一致）──
  MSG=$(git -c core.quotepath=false log --format="%s" "$LOG_RANGE" -- "$TARGET" 2>/dev/null | tr '\n' '; ' | sed 's/; $//')
  MSG=$(printf '%s' "$MSG" | sed 's/"/""/g')

  echo "\"$NAME\",\"$DIR\",\"$ACTION\",\"$MSG\"" >> "$CSV"

  # 刪除的不匯出
  if [ "$ACTION" != "刪除" ]; then
    mkdir -p "$FILEDIR/$DIR"
    git show "$END:$TARGET" > "$FILEDIR/$TARGET" 2>/dev/null || true
  fi

done < <(git -c core.quotepath=false diff --name-status -z "$START" "$END")

echo ""
echo "Done."
echo "Output directory:"
echo "$OUTDIR"
