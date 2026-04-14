#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR line $LINENO: $BASH_COMMAND" >&2' ERR

############################
# CONFIG / ENV
############################

HB_BIN="${HANDBRAKE_CLI_BIN:-HandBrakeCLI}"
PRESET_DEFAULT="${HANDBRAKE_PRESET:-Preset Not Defined}"

PARALLEL_JOBS="${TRANSCODE_JOBS:-3}"   # good for RTX 3060
LOG_FILE="${TRANSCODE_LOG:-./transcode.log}"

mkdir -p "$(dirname "$LOG_FILE")"
echo "=== RUN $(date) ===" >> "$LOG_FILE"

############################
# DEPENDENCY CHECKS
############################

command -v ffmpeg >/dev/null || {
  echo "Missing ffmpeg"
  exit 1
}

command -v "$HB_BIN" >/dev/null || {
  echo "Missing HandBrakeCLI"
  exit 1
}

############################
# ARGS
############################

output=""
preset="$PRESET_DEFAULT"
list_presets=false

while getopts "o:p:l" opt; do
  case $opt in
    o) output="$OPTARG" ;;
    p) preset="$OPTARG" ;;
    l) list_presets=true ;;
    *) exit 1 ;;
  esac
done

shift $((OPTIND - 1))

[[ $# -ne 1 ]] && {
  echo "Usage: $0 [-o out] [-p preset] [-l] <input>"
  exit 1
}

input="$1"

############################
# PRESET LIST
############################

if [[ "$list_presets" == true ]]; then
  echo "=== Built-in Presets ==="
  "$HB_BIN" --preset-list
  exit 0
fi

[[ -z "$preset" ]] && {
  echo "No preset set (-p or HANDBRAKE_PRESET)"
  exit 1
}

############################
# PATH NORMALIZATION
############################

resolve_path() {
  local p="$1"
  if [[ -d "$p" || -f "$p" ]]; then
    cd "$(dirname "$p")" && echo "$(pwd)/$(basename "$p")"
  else
    echo "$p"
  fi
}

input="$(resolve_path "$input")"
is_dir=false
[[ -d "$input" ]] && is_dir=true

############################
# REMUX TEST (LOUD)
############################

can_remux() {
  ffmpeg -v error -i "$1" -c copy -f mp4 -y /dev/null
}

############################
# PROCESS FILE
############################

process_file() {
  local in="$1"
  local out="$2"

  mkdir -p "$(dirname "$out")"

  if [[ -f "$out" ]]; then
    echo "[SKIP] $in" | tee -a "$LOG_FILE"
    return 0
  fi

  echo "[IN ] $in" | tee -a "$LOG_FILE"
  echo "[OUT] $out" | tee -a "$LOG_FILE"

  if can_remux "$in"; then
    echo "[MODE] remux" | tee -a "$LOG_FILE"

    ffmpeg -i "$in" \
      -map 0 \
      -c copy \
      -movflags +faststart \
      "$out" \
      2>&1 | tee -a "$LOG_FILE"

  else
    echo "[MODE] encode ($preset)" | tee -a "$LOG_FILE"

    "$HB_BIN" \
      -i "$in" \
      -o "$out" \
      --preset="$preset" \
      2>&1 | tee -a "$LOG_FILE"
  fi
}

export -f process_file
export -f can_remux
export LOG_FILE HB_BIN preset

############################
# FILE ENUMERATION
############################

build_tasks() {
  if [[ -f "$input" ]]; then
    echo "$input"
  else
    find "$input" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" \)
  fi
}

############################
# OUTPUT MAPPING
############################

map_output() {
  local f="$1"

  if [[ -n "$output" && -d "$output" ]]; then
    rel="${f#$input/}"
    echo "$output/${rel%.*}.mp4"
  elif [[ -n "$output" ]]; then
    echo "$output"
  else
    echo "${f%.*}.mp4"
  fi
}

############################
# PARALLEL EXECUTION
############################

echo "Jobs: $PARALLEL_JOBS" | tee -a "$LOG_FILE"

build_tasks | while IFS= read -r f; do
  out="$(map_output "$f")"

  # run with controlled parallelism
  (
    process_file "$f" "$out"
  ) &

  # throttle
  while [[ $(jobs -rp | wc -l) -ge "$PARALLEL_JOBS" ]]; do
    sleep 0.2
  done
done

wait

echo "=== DONE ===" | tee -a "$LOG_FILE"