#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
JOBS="${JOBS:-$(nproc)}"
TMP="$(mktemp)"

# Normalize root path
ROOT="$(realpath "$ROOT")"

# 1. Collect file list (null-safe)
find "$ROOT" -type f -print0 > "$TMP.files"

# 2. Hash in parallel (batched)
cat "$TMP.files" | \
  xargs -0 -n 32 -P "$JOBS" sha256sum > "$TMP.hashes"

# 3. Build JSON
awk -v root="$ROOT" '
BEGIN {
  print "{"
  print "  \"root\": \"" root "\","
  print "  \"files\": ["
}
{
  hash=$1
  $1=""
  sub(/^ +/, "", $0)
  path=$0

  # escape quotes
  gsub(/"/, "\\\"", path)

  printf "    {\"path\": \"%s\", \"sha256\": \"%s\"}", path, hash

  if (NR != total) print ","
}
END {
  print ""
  print "  ]"
  print "}"
}
' total="$(wc -l < "$TMP.hashes")" "$TMP.hashes"

# cleanup
rm -f "$TMP" "$TMP.files" "$TMP.hashes"
