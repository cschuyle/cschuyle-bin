#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: case-insensitive-dups.sh [-r|--recursive] [DIR ...]"
}

recursive=0
dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: case-insensitive-dups.sh [-r|--recursive] [DIR ...]

Report files in each DIR (default: .) whose names collide when compared
case-insensitively. By default only the top level of each DIR is checked;
-r/--recursive checks every directory in each tree. Exits 1 if any
duplicates are found.
EOF
      exit 0
      ;;
    -r|--recursive)
      recursive=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      dirs+=("${1%/}")
      shift
      ;;
  esac
done

if (( ${#dirs[@]} == 0 )); then
  dirs=(.)
fi

declare -A seen
declare -A originals

found=0

find_args=("${dirs[@]}" -mindepth 1)
if (( ! recursive )); then
  find_args+=(-maxdepth 1)
fi

while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    parent="$(dirname "$path")"

    # normalize for case-insensitive FS; include parent so recursive
    # mode only treats siblings as collisions
    key="$parent/$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"

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

done < <(find "${find_args[@]}" -print0)

if (( found )); then
    exit 1
fi

if (( recursive )); then
    echo "No case-insensitive duplicates found."
else
    echo "No case-insensitive duplicates found at top level."
fi
