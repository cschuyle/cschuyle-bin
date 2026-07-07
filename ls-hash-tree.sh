#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ls-hash-tree.sh [ROOT]

Walk ROOT (default: .) and emit a JSON directory tree with per-node total_size and sha256 per file.
EOF
  exit 0
fi

ROOT="${1:-.}"
JOBS="${JOBS:-$(nproc)}"
TMP="$(mktemp -d)"

ROOT="$(realpath "$ROOT")"
FILES="$TMP/files"
HASHES="$TMP/hashes"

# 1. Collect files with size and mtime (null-safe)
find "$ROOT" -type f -printf '%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\0' > "$FILES"

# 2. Extract just paths for hashing (parallel)
cut -z -f3- "$FILES" | xargs -0 -n 32 -P "$JOBS" sha256sum > "$HASHES"

# 3. Load hashes into associative array
declare -A HASHES_MAP
while IFS= read -r line; do
    hash="${line%% *}"
    path="${line#* }"
    HASHES_MAP["$path"]="$hash"
done < "$HASHES"

# 4. Load size + mtime into associative array
declare -A FILEINFO
while IFS=$'\t' read -r size mtime path; do
    FILEINFO["$path"]="$size"$'\t'"$mtime"
done < <(tr '\0' '\n' < "$FILES")

# 5. Recursive function to build JSON tree with total_size
function json_tree() {
    local dir="$1"
    local indent="$2"
    local first=true
    local dir_total=0

    echo "${indent}{"
    echo "${indent}  \"name\": \"$(basename "$dir")\","
    echo "${indent}  \"type\": \"dir\","
    echo "${indent}  \"children\": ["

    # Directories first (from FILEINFO keys)
    mapfile -t subdirs < <(
        printf '%s\n' "${!FILEINFO[@]}" | grep "^$dir/" | sed -E 's@/[^/]+$@@' | sort -u
    )

    for d in "${subdirs[@]}"; do
        # Skip if this is the current dir itself
        [ "$d" != "$dir" ] || continue

        if [ "$first" = true ]; then first=false; else echo ","; fi

        child_json="$(json_tree "$d" "  $indent")"
        child_size="$(echo "$child_json" | grep '"total_size":' | tail -n1 | awk -F: '{gsub(/[, ]/,"",$2); print $2}')"
        dir_total=$((dir_total + child_size))

        echo "$child_json"
    done

    # Files in this directory
    mapfile -t files < <(
        printf '%s\n' "${!FILEINFO[@]}" | grep "^$dir/" | sort
    )

    for f in "${files[@]}"; do
        # Only immediate files
        [[ "$(dirname "$f")" == "$dir" ]] || continue

        IFS=$'\t' read -r size mtime <<< "${FILEINFO[$f]}"
        hash="${HASHES_MAP[$f]:-}"

        esc_name="${f##*/}"
        esc_name="${esc_name//\"/\\\"}"

        if [ "$first" = true ]; then first=false; else echo ","; fi

        printf '%s    { "name": "%s", "type": "file", "size": %s, "mtime": "%s", "sha256": "%s" }' \
            "$indent" "$esc_name" "$size" "$mtime" "$hash"

        dir_total=$((dir_total + size))
    done

    echo ""
    echo "${indent}  ],"
    echo "${indent}  \"total_size\": $dir_total"
    echo -n "${indent}}"
}

# 6. Print full JSON
echo "{"
echo "  \"root\": \"$ROOT\","
echo "  \"tree\":"
json_tree "$ROOT" "  "
echo ""
echo "}"

# 7. Cleanup
rm -rf "$TMP"
