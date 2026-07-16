#!/usr/bin/env bash
set -euo pipefail

# Repo root = parent of this directory
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# Encode script in repo root (use better-handbreak.sh here if you rename the file).
SE="$ROOT/better-handbrake.sh"

echo "== better-handbrake self-test in $HERE"

# Show / remove prior outputs from a previous run
find "$HERE" -type f -name '*.mp4' 2>/dev/null | sed "s|^$HERE/||" || true
echo "OK: removed prior *.mp4 under fixture"
find "$HERE" -type f -name '*.mp4' -delete 2>/dev/null || true

if [[ ! -r "$SE" ]]; then
  echo "ERROR: missing or unreadable $SE" >&2
  exit 1
fi

echo "== running: $(basename "$SE") -p 'Very Fast 720p30' $HERE"
# Always invoke with bash (POSIX sh does not support set -o pipefail).
exec bash "$SE" -p 'Very Fast 720p30' "$HERE"
