#!/bin/bash

# 檔名: generate_release_note.sh
# 功能: 產生 Git Release Note，依模組分組，列出檔案變更，模組標題旁加檔案統計摘要
# 過濾 Merge commit
# 使用: ./generate_release_note.sh <start_commit_short_hash>
# 輸出: ./output/FEP_RELEASE_NOTE_yyyy-mm-dd.md

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <start_commit_short_hash>"
    exit 1
fi

START_COMMIT=$1
END_COMMIT="HEAD"

FULL_START=$(git rev-parse "$START_COMMIT")
FULL_END=$(git rev-parse "$END_COMMIT")

DATE=$(date +%Y-%m-%d)

# 取得 script 執行路徑
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$BASEDIR/output"

mkdir -p "$OUTDIR"

RELEASE_FILE="$OUTDIR/FEP_RELEASE_NOTE_${DATE}.md"
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/fep_release_note.XXXXXX")
TMPDIR=$WORKDIR
BODY_FILE="$TMPDIR/body.md"
MODULES_FILE="$TMPDIR/modules.txt"
COUNTS_FILE="$TMPDIR/counts.tsv"
COMMIT_MODULES_FILE="$TMPDIR/commit_modules.txt"

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$TMPDIR"
: > "$BODY_FILE"
: > "$MODULES_FILE"
: > "$COUNTS_FILE"
: > "$COMMIT_MODULES_FILE"

csv_escape() {
    printf '%s' "$1" | sed 's/[][\.^$*\/]/\\&/g'
}

count_for() {
    module=$1
    action=$2
    awk -F '\t' -v module="$module" -v action="$action" \
        '$1 == module && $2 == action { total += $3 } END { print total + 0 }' "$COUNTS_FILE"
}

add_count() {
    module=$1
    action=$2
    printf '%s\t%s\t1\n' "$module" "$action" >> "$COUNTS_FILE"
}

module_seen() {
    grep -Fxq "$1" "$MODULES_FILE"
}

mark_module_seen() {
    printf '%s\n' "$1" >> "$MODULES_FILE"
}

commit_module_seen() {
    grep -Fxq "$1" "$COMMIT_MODULES_FILE"
}

mark_commit_module_seen() {
    printf '%s\n' "$1" >> "$COMMIT_MODULES_FILE"
}

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
COMMITS=$(git log "${START_COMMIT}..${END_COMMIT}" --no-merges --pretty=format:"%H")

# -------------------------------
# 3. 逐 commit 處理
# -------------------------------
for commit in $COMMITS; do
    SHORT_HASH=$(git rev-parse --short "$commit")
    DATE_COMMIT=$(git show -s --format=%ad --date=short "$commit")
    SUBJECT=$(git show -s --format=%s "$commit")
    CHANGES_FILE="$TMPDIR/${commit}.changes"

    git show --name-status --pretty="" "$commit" > "$CHANGES_FILE"

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        STATUS=$(printf '%s\n' "$line" | awk '{print $1}')
        FILE=$(printf '%s\n' "$line" | awk '{print $2}')

        case "$STATUS" in
            R*|C*)
                FILE=$(printf '%s\n' "$line" | awk '{print $3}')
                ;;
        esac

        [ -z "$FILE" ] && continue

        MODULE=$(printf '%s\n' "$FILE" | cut -d'/' -f3)
        [ -z "$MODULE" ] && MODULE="Others"

        case "$STATUS" in
            A) add_count "$MODULE" "A" ;;
            M) add_count "$MODULE" "M" ;;
            D) add_count "$MODULE" "D" ;;
            R*) add_count "$MODULE" "R" ;;
        esac

        if ! module_seen "$MODULE"; then
            echo "" >> "$BODY_FILE"
            echo "### Module: $MODULE" >> "$BODY_FILE"
            mark_module_seen "$MODULE"
        fi

        COMMIT_MODULE_KEY="$MODULE|$commit"
        if ! commit_module_seen "$COMMIT_MODULE_KEY"; then
            echo "- $SHORT_HASH | $DATE_COMMIT | $SUBJECT" >> "$BODY_FILE"
            mark_commit_module_seen "$COMMIT_MODULE_KEY"
        fi

        printf '%s\t%s\n' "$STATUS" "$FILE" >> "$BODY_FILE"
    done < "$CHANGES_FILE"
done

cat "$BODY_FILE" >> "$RELEASE_FILE"

# -------------------------------
# 4. 在模組標題旁加檔案統計摘要
# -------------------------------
while IFS= read -r MODULE; do
    [ -z "$MODULE" ] && continue

    ADDED=$(count_for "$MODULE" "A")
    MODIFIED=$(count_for "$MODULE" "M")
    DELETED=$(count_for "$MODULE" "D")
    RENAMED=$(count_for "$MODULE" "R")

    ESCAPED_MODULE=$(csv_escape "$MODULE")
    sed -i "" "s/^### Module: $ESCAPED_MODULE$/### Module: $MODULE (Added: $ADDED, Modified: $MODIFIED, Deleted: $DELETED, Renamed: $RENAMED)/" "$RELEASE_FILE" 2>/dev/null || \
    sed -i "s/^### Module: $ESCAPED_MODULE$/### Module: $MODULE (Added: $ADDED, Modified: $MODIFIED, Deleted: $DELETED, Renamed: $RENAMED)/" "$RELEASE_FILE"
done < "$MODULES_FILE"

echo "✅ Release note generated:"
echo "   $RELEASE_FILE"
