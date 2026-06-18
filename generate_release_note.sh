#!/bin/bash

# 檔名: generate_release_note.sh
# 功能: 產生 Git Release Note，依模組分組，列出檔案變更，模組標題旁加檔案統計摘要
# 過濾 Merge commit
# 使用: ./generate_release_note.sh <start_commit_short_hash>
# 輸出: ./output/FEP_RELEASE_NOTE_yyyy-mm-dd.md

declare -A commit_written

if [ $# -ne 1 ]; then
    echo "Usage: $0 <start_commit_short_hash>"
    exit 1
fi

START_COMMIT=$1
END_COMMIT="HEAD"

FULL_START=$(git rev-parse $START_COMMIT)
FULL_END=$(git rev-parse $END_COMMIT)

DATE=$(date +%Y-%m-%d)

# 取得 script 執行路徑
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$BASEDIR/output"

mkdir -p "$OUTDIR"

RELEASE_FILE="$OUTDIR/FEP_RELEASE_NOTE_${DATE}.md"

# -------------------------------
# 1. Release Note 標題
# -------------------------------
{
echo "## Release Note - ${DATE}"
echo ""
echo "**Commit Range:** $FULL_START .. $FULL_END"
echo ""
} > "$RELEASE_FILE"

# -------------------------------
# 2. 取得 commit hash (排除 merge commit)
# -------------------------------
COMMITS=$(git log ${START_COMMIT}..${END_COMMIT} --no-merges --pretty=format:"%H")

declare -A module_counts_added
declare -A module_counts_modified
declare -A module_counts_deleted
declare -A module_counts_renamed
declare -A module_written

# -------------------------------
# 3. 逐 commit 處理
# -------------------------------
for commit in $COMMITS; do
    SHORT_HASH=$(git rev-parse --short $commit)
    DATE_COMMIT=$(git show -s --format=%ad --date=short $commit)
    SUBJECT=$(git show -s --format=%s $commit)

    git show --name-status --pretty="" $commit | while read -r line; do
        STATUS=$(echo $line | awk '{print $1}')
        FILE=$(echo $line | awk '{print $2}')

        [ -z "$FILE" ] && continue

        MODULE=$(echo $FILE | cut -d'/' -f3)
        [ -z "$MODULE" ] && MODULE="Others"

        case "$STATUS" in
            A) module_counts_added["$MODULE"]=$(( ${module_counts_added["$MODULE"]:-0} + 1 )) ;;
            M) module_counts_modified["$MODULE"]=$(( ${module_counts_modified["$MODULE"]:-0} + 1 )) ;;
            D) module_counts_deleted["$MODULE"]=$(( ${module_counts_deleted["$MODULE"]:-0} + 1 )) ;;
            R*) module_counts_renamed["$MODULE"]=$(( ${module_counts_renamed["$MODULE"]:-0} + 1 )) ;;
        esac

        if [ -z "${module_written["$MODULE"]}" ]; then
            echo "" >> "$RELEASE_FILE"
            echo "### Module: $MODULE" >> "$RELEASE_FILE"
            module_written["$MODULE"]=1
        fi

        if [ -z "${commit_written["$MODULE|$commit"]}" ]; then
            echo "- $SHORT_HASH | $DATE_COMMIT | $SUBJECT" >> "$RELEASE_FILE"
            commit_written["$MODULE|$commit"]=1
        fi

        echo -e "$STATUS\t$FILE" >> "$RELEASE_FILE"
    done
done

# -------------------------------
# 4. 在模組標題旁加檔案統計摘要
# -------------------------------
for MODULE in "${!module_written[@]}"; do
    ADDED=${module_counts_added["$MODULE"]:-0}
    MODIFIED=${module_counts_modified["$MODULE"]:-0}
    DELETED=${module_counts_deleted["$MODULE"]:-0}
    RENAMED=${module_counts_renamed["$MODULE"]:-0}

    sed -i "" "s/^### Module: $MODULE/### Module: $MODULE (Added: $ADDED, Modified: $MODIFIED, Deleted: $DELETED, Renamed: $RENAMED)/" "$RELEASE_FILE" 2>/dev/null || \
    sed -i "s/^### Module: $MODULE/### Module: $MODULE (Added: $ADDED, Modified: $MODIFIED, Deleted: $DELETED, Renamed: $RENAMED)/" "$RELEASE_FILE"
done

echo "✅ Release note generated:"
echo "   $RELEASE_FILE"
