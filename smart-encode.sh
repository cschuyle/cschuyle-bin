#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR line $LINENO: $BASH_COMMAND" >&2' ERR

############################
# CONFIG / ENV
############################

if [[ -n "${HANDBRAKE_CLI_BIN:-}" ]]; then
  HB_BIN="$HANDBRAKE_CLI_BIN"
elif command -v HandBrakeCLI >/dev/null 2>&1; then
  HB_BIN="$(command -v HandBrakeCLI)"
elif command -v HandBrakeCLI.exe >/dev/null 2>&1; then
  HB_BIN="$(command -v HandBrakeCLI.exe)"
else
  HB_BIN=""
fi

PRESET_DEFAULT="${HANDBRAKE_PRESET:-Preset Not Defined}"

############################
# ARGS
############################

output=""
preset="$PRESET_DEFAULT"
# Preset listing: 0=off, 1=-l (names + sections), 2+=-ll / -l -l (full + descriptions)
list_presets=0

while getopts "o:p:l" opt; do
  case $opt in
    o) output="$OPTARG" ;;
    p) preset="$OPTARG" ;;
    l) list_presets=$((list_presets + 1)) ;;
    *) exit 1 ;;
  esac
done

shift $((OPTIND - 1))

if [[ "$list_presets" -ge 1 ]]; then
  [[ -n "$HB_BIN" ]] && command -v "$HB_BIN" >/dev/null 2>&1 || {
    echo "Missing HandBrakeCLI or HandBrakeCLI.exe (set HANDBRAKE_CLI_BIN)" >&2
    exit 1
  }
  echo "=== Presets (built-in + custom from HandBrake GUI) ==="
  if [[ "$list_presets" -ge 2 ]]; then
    "$HB_BIN" --preset-import-gui --preset-list
  else
    # HandBrakeCLI prints PresetDescription as extra lines indented one level past
    # the preset name; keep folder lines (name/) and name lines only.
    "$HB_BIN" --preset-import-gui --preset-list 2>&1 | awk '
      BEGIN { last = -1 }
      {
        gsub(/\r/, "", $0)
        indent = match($0, /^ */) ? RLENGTH : 0
        content = substr($0, indent + 1)
        if (last >= 0 && indent > last) next
        print
        if (content ~ /\/$/) last = -1
        else last = indent
      }'
  fi
  exit 0
fi

[[ $# -ne 1 ]] && {
  echo "Usage: $0 [-l|-ll]   # list presets (no input); -ll includes descriptions" >&2
  echo "       $0 [-o out] [-p preset] <input>" >&2
  exit 1
}

input="$1"

############################
# PATH NORMALIZATION + PLANNED OUTPUTS (before ffmpeg / encode work)
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

build_tasks() {
  if [[ -f "$input" ]]; then
    echo "$input"
  else
    find "$input" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" \) | sort -u
  fi
}

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

existing_out=0
declare -A existing_out_seen=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  f="${f%$'\r'}"
  out="$(map_output "$f")"
  if [[ -e "$out" ]]; then
    existing_out=1
    if [[ -z ${existing_out_seen["$out"]+x} ]]; then
      existing_out_seen["$out"]=1
      echo "ERROR: output already exists: $out" >&2
    fi
  fi
done < <(build_tasks)
(( existing_out == 0 )) || exit 1
unset existing_out_seen

############################
# DEPENDENCY CHECKS
############################

command -v ffmpeg >/dev/null || {
  echo "Missing ffmpeg" >&2
  exit 1
}

[[ -n "$HB_BIN" ]] && command -v "$HB_BIN" >/dev/null 2>&1 || {
  echo "Missing HandBrakeCLI or HandBrakeCLI.exe (set HANDBRAKE_CLI_BIN)" >&2
  exit 1
}

[[ -z "$preset" ]] && {
  echo "No preset set (-p or HANDBRAKE_PRESET)" >&2
  exit 1
}

############################
# REMUX TEST (LOUD)
############################

can_remux() {
  # Do not read stdin: the main loop feeds task paths on stdin (< <(build_tasks)).
  ffmpeg -nostdin -v error -i "$1" -c copy -f mp4 -y /dev/null </dev/null
}

# Status to stderr; if stderr is not a TTY (piped/captured), also try /dev/tty.
# Writing to both when they are the same device would duplicate every line.
emit_status() {
  local s
  for s in "$@"; do
    printf '%s\n' "$s" >&2
    if [[ ! -t 2 ]]; then
      printf '%s\n' "$s" >/dev/tty 2>/dev/null || true
    fi
  done
}

############################
# PROCESS FILE
############################

process_file() {
  local in="$1"
  local out="$2"

  if [[ -e "$out" ]]; then
    echo "ERROR: output already exists: $out" >&2
    return 1
  fi

  mkdir -p "$(dirname "$out")"

  emit_status "[IN ] $in" "[OUT] $out"

  emit_status "INFO: probing whether MP4 stream-copy (remux) is possible..."
  if can_remux "$in"; then
    emit_status \
      "----------------------------------------------------------------" \
      "INFO: MODE=REMUX  (ffmpeg -c copy to MP4; no re-encode)" \
      "----------------------------------------------------------------"

    ffmpeg -nostdin -i "$in" \
      -map 0 \
      -c copy \
      -movflags +faststart \
      "$out" </dev/null

  else
    emit_status \
      "----------------------------------------------------------------" \
      "INFO: MODE=ENCODE  (HandBrakeCLI; preset: $preset)" \
      "----------------------------------------------------------------"

    "$HB_BIN" \
      -i "$in" \
      -o "$out" \
      --preset="$preset" </dev/null
  fi
}

############################
# RUN (sequential, foreground)
############################
# Task list is on stdin; encoders must not read stdin or they consume the next path.

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  f="${f%$'\r'}"
  out="$(map_output "$f")"
  process_file "$f" "$out"
done < <(build_tasks)

echo "=== DONE ===" >&2
