#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
JOBS="${JOBS:-$(nproc)}"
TMP="$(mktemp -d)"

ROOT="$(realpath "$ROOT")"

FILES="$TMP/files"
HASHES="$TMP/hashes"

# 1. Collect files WITH size and mtime (null-safe)
# Format: size<TAB>mtime<TAB>path\0
find "$ROOT" -type f -printf '%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\0' > "$FILES"

# 2. Extract just paths for hashing
cut -z -f3- "$FILES" | xargs -0 -n 32 -P "$JOBS" sha256sum > "$HASHES"

# 3. Prepare JSON output
# Read hashes into array
declare -A HASHES_MAP
while IFS= read -r line; do
    hash="${line%% *}"
    path="${line#* }"
    HASHES_MAP["$path"]="$hash"
done < "$HASHES"

# Begin JSON
echo "{"
echo "  \"root\": \"$ROOT\","
echo "  \"files\": ["

# Iterate over file list
FIRST=true
while IFS= read -r -d '' entry; do
    size="${entry%%$'\t'*}"
    rest="${entry#*$'\t'}"
    mtime="${rest%%$'\t'*}"
    path="${rest#*$'\t'}"
    hash="${HASHES_MAP[$path]}"

    # Escape quotes in path
    esc_path="${path//\"/\\\"}"

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo ","
    fi

    printf "    {\"path\": \"%s\", \"size\": %s, \"mtime\": \"%s\", \"sha256\": \"%s\"}" \
        "$esc_path" "$size" "$mtime" "$hash"

done < "$FILES"

# End JSON
echo ""
echo "  ]"
echo "}"

# Cleanup
rm -rf "$TMP"
