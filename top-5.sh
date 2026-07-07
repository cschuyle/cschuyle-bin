#!/usr/bin/env bash
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: top-5.sh [DIR]

List the four largest files under DIR (default: .) with human-readable sizes.
EOF
  exit 0
fi

DIR="${1:-.}"

find "$DIR" -type f -printf '%s\t%p\n' \
| sort -nr \
| head -n 4 \
| awk -F'\t' '
{
    size=$1
    path=$2

    split("B KB MB GB TB", units)
    i=1
    while (size>=1024 && i<5) {
        size/=1024
        i++
    }

    printf "%.2f %s\t%s\n", size, units[i], path
}'
