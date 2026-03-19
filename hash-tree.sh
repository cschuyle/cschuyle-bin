#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
JOBS="${JOBS:-$(nproc)}"
TMP="$(mktemp -d)"

ROOT="$(realpath "$ROOT")"

FILES="$TMP/files"
HASHES="$TMP/hashes"

# 1. Collect files WITH size (null-safe)
# Format: size<TAB>path\0
find "$ROOT" -type f -printf '%s\t%p\0' > "$FILES"

# 2. Extract just paths for hashing
cut -z -f2- "$FILES" | \
  xargs -0 -n 32 -P "$JOBS" sha256sum > "$HASHES"

# 3. Join size + hash + path and emit JSON
# Convert FILES to newline-delimited safely
tr '\0' '\n' < "$FILES" | \
awk -F'\t' '
NR==FNR {
  # Read hashes: "hash  path"
  hash=$1
  $1=""
  sub(/^ +/, "", $0)
  hashes[$0]=hash
  next
}
{
  size=$1
  path=$2

  # escape quotes
  gsub(/"/, "\\\"", path)

  printf "    {\"path\": \"%s\", \"size\": %s, \"sha256\": \"%s\"}", path, size, hashes[path]

  if (NR != total + FNR_offset) print ","
}
END {}
' "$HASHES" - | \
awk -v root="$ROOT" '
BEGIN {
  print "{"
  print "  \"root\": \"" root "\","
  print "  \"files\": ["
}
{
  print
}
END {
  print ""
  print "  ]"
  print "}"
}'
