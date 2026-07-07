#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: case-insensitive-dups.sh [DIR]

Report top-level files in DIR (default: .) whose names collide when compared
case-insensitively. Exits 1 if any duplicates are found.
EOF
  exit 0
fi

dir="${1:-.}"
dir="${dir%/}"

declare -A seen
declare -A originals

found=0

while IFS= read -r -d '' path; do
    name="$(basename "$path")"

    # normalize for case-insensitive FS
    key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"

    if [[ -n "${seen[$key]:-}" ]]; then
        if [[ "${seen[$key]}" == "1" ]]; then
            echo "CASE-INSENSITIVE DUPLICATES for: $name"
            echo "  ${originals[$key]}"
            seen["$key"]=2
        fi
        echo "  $path"
        found=1
    else
        seen["$key"]=1
        originals["$key"]="$path"
    fi

done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0)

if (( found )); then
    exit 1
fi

echo "No case-insensitive duplicates found at top level."
