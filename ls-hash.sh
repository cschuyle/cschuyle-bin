#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: ls-hash.sh [ROOT]

Walk ROOT (default: .) and emit JSON listing every file with size, mtime, and sha256.
EOF
  exit 0
fi

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

# 5. Begin JSON
echo "{"
echo "  \"root\": \"$ROOT\","
echo "  \"files\": ["

FIRST=true
for path in "${!FILEINFO[@]}"; do
    IFS=$'\t' read -r size mtime <<< "${FILEINFO[$path]}"
    hash="${HASHES_MAP[$path]:-}"  # Safe default if missing

    # Escape quotes in path
    esc_path="${path//\"/\\\"}"

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo ","
    fi

    printf '    { "path": "%s", "size": %s, "mtime": "%s", "sha256": "%s" }' \
        "$esc_path" "$size" "$mtime" "$hash"
done

echo ""
echo "  ]"
echo "}"

# 6. Cleanup
rm -rf "$TMP"
