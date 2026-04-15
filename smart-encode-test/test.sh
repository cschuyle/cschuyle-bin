#!/usr/bin/env bash
# Run smart-encode.sh on this fixture tree and assert expected MP4 outputs exist
# and look like valid remuxes/encodes (container, codecs, duration vs source).
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
encoder="$repo/smart-encode.sh"

die() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found (install ffmpeg)"
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found"
[[ -f "$encoder" ]] || die "smart-encode.sh not found at $encoder"
run_smart_encode() {
  if [[ -x "$encoder" ]]; then
    "$encoder" "$@"
  else
    bash "$encoder" "$@"
  fi
}

# Builtin preset if remux is not used (must exist in HandBrakeCLI --preset-list).
preset="${SMART_ENCODE_TEST_PRESET:-Very Fast 720p30}"

clean_outputs() {
  ( cd "$here" && find . -type f \( -iname '*.mp4' \) -print -delete )
}

duration_of() {
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1"
}

assert_mp4_matches_source() {
  local src=$1 out=$2
  [[ -f "$out" ]] || die "missing output file: $out"
  [[ -s "$out" ]] || die "empty output file: $out"

  local fmt vc ac
  fmt=$(ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$out")
  [[ "$fmt" == *mp4* || "$fmt" == *iso* ]] || die "$out: expected MP4-ish format_name, got '$fmt'"

  vc=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$out")
  [[ -n "$vc" ]] || die "$out: no video stream"
  [[ "$vc" == h264* ]] || die "$out: expected h264 video, got '$vc'"

  ac=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$out" || true)
  [[ -n "$ac" ]] || die "$out: no audio stream"
  [[ "$ac" == aac* ]] || die "$out: expected aac audio, got '$ac'"

  local ds do
  ds=$(duration_of "$src")
  do=$(duration_of "$out")
  awk -v s="$ds" -v o="$do" 'BEGIN {
    if (s == "" || o == "") exit 1
    sd = s + 0; od = o + 0
    if (sd <= 0 || od <= 0) exit 1
    d = (sd > od) ? (sd - od) : (od - sd)
    exit (d > 0.25) ? 1 : 0
  }' || die "$out: duration $do too far from source $ds"
}

echo "== smart-encode self-test in $here"
clean_outputs
ok "removed prior *.mp4 under fixture"

echo "== running: $encoder -p '$preset' $here"
run_smart_encode -p "$preset" "$here"

expect=(
  "$here/Title 1.mkv|$here/Title 1.mp4"
  "$here/Features/Feature.mkv|$here/Features/Feature.mp4"
)

for pair in "${expect[@]}"; do
  IFS='|' read -r src out <<<"$pair"
  [[ -f "$src" ]] || die "fixture missing: $src"
  assert_mp4_matches_source "$src" "$out"
  ok "$(basename "$out") matches $(basename "$src")"
done

echo "== all checks passed"
