#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR line $LINENO: $BASH_COMMAND" >&2' ERR

############################
# CONFIG / ENV
############################

if [[ -z "${BH_HANDBRAKE_CLI_BIN:-}" ]]; then
  if command -v HandBrakeCLI >/dev/null 2>&1; then
    BH_HANDBRAKE_CLI_BIN="$(command -v HandBrakeCLI)"
  elif command -v HandBrakeCLI.exe >/dev/null 2>&1; then
    BH_HANDBRAKE_CLI_BIN="$(command -v HandBrakeCLI.exe)"
  else
    BH_HANDBRAKE_CLI_BIN=""
  fi
fi

_bh_default_preset_note=0
[[ -n "${BH_DEFAULT_PRESET:-}" ]] && _bh_default_preset_note=1
: "${BH_DEFAULT_PRESET:=Preset Not Defined}"

############################
# ARGS
############################

# Long-only --pattern (getopts does not handle long options).
# Default glob for directory input; overridden by --pattern= / --pattern or -P.
file_pattern="${BH_FILE_PATTERN:-}"
filtered_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pattern=*)
      file_pattern="${1#*=}"
      shift
      ;;
    --pattern)
      shift
      [[ $# -ge 1 ]] || {
        echo "ERROR: --pattern requires a value (e.g. --pattern='*.mkv')" >&2
        exit 1
      }
      file_pattern="$1"
      shift
      ;;
    *)
      filtered_args+=("$1")
      shift
      ;;
  esac
done
set -- "${filtered_args[@]}"

output=""
preset="$BH_DEFAULT_PRESET"
# Preset listing: 0=off, 1=-l (names + sections), 2+=-ll / -l -l (full + descriptions)
list_presets=0

while getopts "o:p:lP:" opt; do
  case $opt in
    o) output="$OPTARG" ;;
    p) preset="$OPTARG" ;;
    l) list_presets=$((list_presets + 1)) ;;
    P) file_pattern="$OPTARG" ;;
    *) exit 1 ;;
  esac
done

shift $((OPTIND - 1))

if [[ "$list_presets" -ge 1 ]]; then
  [[ -n "$BH_HANDBRAKE_CLI_BIN" ]] && command -v "$BH_HANDBRAKE_CLI_BIN" >/dev/null 2>&1 || {
    echo "Missing HandBrakeCLI or HandBrakeCLI.exe (set BH_HANDBRAKE_CLI_BIN)" >&2
    exit 1
  }
  echo "=== Presets (built-in + custom from HandBrake GUI) ==="
  if [[ "$list_presets" -ge 2 ]]; then
    "$BH_HANDBRAKE_CLI_BIN" --preset-import-gui --preset-list 2>&1 | awk '
      { gsub(/\r/, "", $0)
        if ($0 ~ /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/) next
        print
      }'
  else
    # HandBrakeCLI prints PresetDescription as extra lines indented one level past
    # the preset name; keep folder lines (name/) and name lines only.
    # Drop libhb startup lines like [14:23:19] ...
    "$BH_HANDBRAKE_CLI_BIN" --preset-import-gui --preset-list 2>&1 | awk '
      BEGIN { last = -1 }
      {
        gsub(/\r/, "", $0)
        if ($0 ~ /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/) next
        indent = match($0, /^ */) ? RLENGTH : 0
        content = substr($0, indent + 1)
        if (last >= 0 && indent > last) next
        print
        if (content ~ /\/$/) last = -1
        else last = indent
      }'
  fi

  echo
  echo "NOTE: CLI Default is NOT what you think it is."
  if [[ "$_bh_default_preset_note" -eq 1 ]]; then
    echo "NOTE: BH_DEFAULT_PRESET is set; default encode preset is: ${BH_DEFAULT_PRESET}"
  fi
  exit 0
fi

[[ $# -ne 1 ]] && {
  echo "Usage: $0 [-l|-ll]   # list presets (no input); -ll includes descriptions" >&2
  echo "       $0 [-o out] [-p preset] [-P|--pattern <filename pattern>] <input file(s)/directory(ies)>" >&2
  echo "  -P --pattern: when <input> is a directory, only encode files matching the glob." >&2
  echo >&2
  echo "Environment:" >&2
  echo "  BH_HANDBRAKE_CLI_BIN                  HandBrakeCLI path (when not found on PATH)" >&2
  echo "  BH_DEFAULT_PRESET      -p             Use HandBrake preset (else: Preset Not Defined)" >&2
  echo "  BH_FILE_PATTERN        -P,--pattern   Encode only filenames matching pattern (when <input> is a directory)" >&2
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
  elif [[ -n "${file_pattern:-}" ]]; then
    find "$input" -type f -iname "$file_pattern" | sort -u
  else
    find "$input" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" \) | sort -u
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

# Path for user messages: wrap in single quotes; internal ' shown as '\''
path_sq() {
  local s=$1 r i
  r="'"
  for (( i = 0; i < ${#s}; i++ )); do
    case "${s:i:1}" in
      \') r+="'\''" ;;
      *) r+="${s:i:1}" ;;
    esac
  done
  r+="'"
  printf '%s' "$r"
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
      echo "ERROR: output already exists: $(path_sq "$out")" >&2
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

[[ -n "$BH_HANDBRAKE_CLI_BIN" ]] && command -v "$BH_HANDBRAKE_CLI_BIN" >/dev/null 2>&1 || {
  echo "Missing HandBrakeCLI or HandBrakeCLI.exe (set BH_HANDBRAKE_CLI_BIN)" >&2
  exit 1
}

[[ -z "$preset" ]] && {
  echo "No preset set (-p or BH_DEFAULT_PRESET)" >&2
  exit 1
}

############################
# ENCODER WRAPPER (quiet unless failure)
############################

# Run a command with stdout+stderr captured; print the log only on non-zero exit.
encoder_run() {
  # Restore caller's -e / -E on return so intentional non-zero returns do not fire
  # the global ERR trap (bash runs ERR on `return n` from functions when -E is on).
  local -
  set +eE
  local log st
  log="$(mktemp "${TMPDIR:-/tmp}/better-handbrake.XXXXXX")" || return 1
  # Do not use `if cmd; then ... fi; st=$?`: when cmd fails and there is no else,
  # bash sets the if's exit status to 0, so $? after `fi` is wrong.
  "$@" >"$log" 2>&1
  st=$?
  if (( st == 0 )); then
    rm -f "$log"
    return 0
  fi
  echo "ERROR: encoder failed (exit $st)" >&2
  cat "$log" >&2
  rm -f "$log"
  return "$st"
}

# Collapse HandBrake --json repeated "Progress: { ... }" blocks to one \r line (ETA + %).
# Optional: BH_PROGRESS_FILE (input basename), BH_PROGRESS_INDEX / BH_PROGRESS_TOTAL
# for a "(n/m) name    " prefix before ETA (set by the main task loop).
handbrake_json_progress_filter() {
  awk -v fname="${BH_PROGRESS_FILE:-}" \
      -v cur="${BH_PROGRESS_INDEX:-0}" \
      -v tot="${BH_PROGRESS_TOTAL:-0}" '
  BEGIN { inblk = 0; dep = 0; buf = "" }
  function count_braces(s,    i, c, n) {
    n = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "{") n++
      if (c == "}") n--
    }
    return n
  }
  function emit_eta(buf,    eta, pct, rate, rateavg, tmp, n, i, em, es, pct100, pref, fpss) {
    # Idle/scan/finished blocks often include Progress: 0 with no ETA — skip or we
    # overwrite the last good line with "HandBrake: 0.0%" and look hung.
    if (!match(buf, /"State"[[:space:]]*:[[:space:]]*"WORKING"/)) return
    if ((tot + 0) > 0 && (cur + 0) > 0 && length(fname) > 0)
      pref = sprintf("HandBrake: (%d/%d) %s    ", cur + 0, tot + 0, fname)
    else if (length(fname) > 0)
      pref = "HandBrake: " fname "  "
    else if ((tot + 0) > 0 && (cur + 0) > 0)
      pref = sprintf("HandBrake: (%d/%d)  ", cur + 0, tot + 0)
    else
      pref = "HandBrake: "
    eta = -1
    pct = -1
    rate = -1
    rateavg = -1
    if (match(buf, /"ETASeconds"[[:space:]]*:[[:space:]]*([0-9]+)/)) {
      tmp = substr(buf, RSTART, RLENGTH)
      if (match(tmp, /[0-9]+/)) eta = substr(tmp, RSTART, RLENGTH) + 0
    }
    n = split(buf, lines, /\n/)
    for (i = 1; i <= n; i++) {
      if (match(lines[i], /"Progress"[[:space:]]*:[[:space:]]*([0-9.eE+-]+)/)) {
        tmp = substr(lines[i], RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", tmp)
        pct = tmp + 0
      }
      if (match(lines[i], /"RateAvg"[[:space:]]*:[[:space:]]*([0-9.eE+-]+)/)) {
        tmp = substr(lines[i], RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", tmp)
        rateavg = tmp + 0
      }
      if (match(lines[i], /"Rate"[[:space:]]*:[[:space:]]*([0-9.eE+-]+)/)) {
        tmp = substr(lines[i], RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", tmp)
        rate = tmp + 0
      }
    }
    if (eta < 0 && pct < 0) return
    pct100 = (pct >= 0) ? pct * 100 : -1
    fpss = ""
    if (rate >= 0 && rateavg >= 0)
      fpss = sprintf("  %.1f fps (avg %.1f)", rate, rateavg)
    else if (rate >= 0)
      fpss = sprintf("  %.1f fps", rate)
    else if (rateavg >= 0)
      fpss = sprintf("  avg %.1f fps", rateavg)
    if (eta >= 0 && pct >= 0) {
      if (eta >= 3600) {
        printf "\r%sETA ~%dh %dm %ds  %.1f%%%s     ", pref, int(eta/3600), int((eta%3600)/60), int(eta%60), pct100, fpss
      } else {
        em = int(eta/60)
        es = int(eta % 60)
        printf "\r%sETA ~%dm %ds  %.1f%%%s     ", pref, em, es, pct100, fpss
      }
    } else if (eta >= 0) {
      if (eta >= 3600) {
        printf "\r%sETA ~%dh %dm %ds%s     ", pref, int(eta/3600), int((eta%3600)/60), int(eta%60), fpss
      } else {
        em = int(eta/60)
        es = int(eta % 60)
        printf "\r%sETA ~%dm %ds%s     ", pref, em, es, fpss
      }
    } else {
      printf "\r%s%.1f%%%s     ", pref, pct100, fpss
    }
    fflush()
  }
  /^Progress:[[:space:]]*\{/ {
    inblk = 1
    buf = $0 "\n"
    dep = count_braces($0)
    if (dep <= 0) {
      emit_eta(buf)
      inblk = 0
      buf = ""
    }
    next
  }
  inblk {
    buf = buf $0 "\n"
    dep += count_braces($0)
    if (dep > 0) next
    emit_eta(buf)
    inblk = 0
    buf = ""
    next
  }
  { print }
  END { printf "\n" }
  '
}

# HandBrakeCLI: progress and scan noise can be on stdout and/or stderr; when stderr
# is not a TTY, HB often omits \r progress. Merge streams with 2>&1 | tee so both
# land in the log and on the console; use PIPESTATUS[0] for HandBrake's exit code.
encoder_run_handbrake() {
  local -
  set +eE
  local log st _hb_streamed_stderr
  log="$(mktemp "${TMPDIR:-/tmp}/better-handbrake.XXXXXX")" || return 1
  _hb_streamed_stderr=0
  if [[ -t 2 ]]; then
    _hb_streamed_stderr=1
    "$@" 2>&1 | tee -a "$log" | handbrake_json_progress_filter >&2
    st=${PIPESTATUS[0]}
  elif : >/dev/tty 2>/dev/null; then
    _hb_streamed_stderr=1
    "$@" 2>&1 | tee -a "$log" | handbrake_json_progress_filter >/dev/tty
    st=${PIPESTATUS[0]}
  else
    "$@" >"$log" 2>&1
    st=$?
  fi
  if (( st == 0 )); then
    rm -f "$log"
    return 0
  fi
  echo "ERROR: encoder failed (exit $st)" >&2
  if grep -q "Invalid preset" "$log" 2>/dev/null; then
    echo "HINT: preset name must match HandBrake GUI (custom presets need import; list: $BH_HANDBRAKE_CLI_BIN --preset-import-gui --preset-list)." >&2
  fi
  if ((_hb_streamed_stderr)); then
    echo "INFO: stderr was already shown above; not repeating the full log." >&2
  else
    cat "$log" >&2
  fi
  rm -f "$log"
  return "$st"
}

############################
# REMUX TEST
############################

# On failure, last non-empty ffmpeg error lines are stored in _BH_REMUX_PROBE_ERR
# (for process_file to print). Do not read stdin: the main loop feeds task paths
# on stdin (< <(build_tasks)). Must match the real remux (-map 0): without it,
# ffmpeg may omit streams and falsely pass here while -map 0 then fails.
can_remux() {
  local -
  set +eE
  local log st
  _BH_REMUX_PROBE_ERR=""
  log="$(mktemp "${TMPDIR:-/tmp}/better-handbrake.XXXXXX")" || return 1
  ffmpeg -nostdin -hide_banner -loglevel error -nostats \
    -i "$1" -map 0 -c copy -f mp4 -y /dev/null </dev/null >"$log" 2>&1
  st=$?
  if (( st == 0 )); then
    rm -f "$log"
    return 0
  fi
  _BH_REMUX_PROBE_ERR="$(grep -v '^[[:space:]]*$' "$log" | tail -n 40)"
  rm -f "$log"
  return 1
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
    echo "ERROR: output already exists: $(path_sq "$out")" >&2
    return 1
  fi

  local outdir tmpdir tmpout
  outdir="$(dirname "$out")"
  tmpdir="$outdir/temp"
  tmpout="$tmpdir/$(basename "$out")"

  mkdir -p "$outdir" || {
    echo "ERROR: cannot create output directory: $(path_sq "$outdir")" >&2
    return 1
  }
  if ! mkdir -p "$tmpdir"; then
    echo "ERROR: cannot create temp directory: $(path_sq "$tmpdir")" >&2
    return 1
  fi

  emit_status "[IN ] $in" "[OUT] $out"

  emit_status "INFO: probing whether MP4 stream-copy (remux) is possible..."
  if can_remux "$in"; then
    emit_status \
      "----------------------------------------------------------------" \
      "INFO: MODE=REMUX  (ffmpeg -c copy to MP4; no re-encode)" \
      "----------------------------------------------------------------"

    encoder_run ffmpeg -nostdin -hide_banner -loglevel error -nostats -i "$in" \
      -map 0 \
      -c copy \
      -movflags +faststart \
      "$tmpout" </dev/null
    mv "$tmpout" "$out"

  else
    emit_status "INFO: MP4 stream-copy (remux) is not possible for this file."
    if [[ -n "${_BH_REMUX_PROBE_ERR:-}" ]]; then
      emit_status "INFO: ffmpeg:"
      local _line
      while IFS= read -r _line || [[ -n "${_line:-}" ]]; do
        emit_status "  $_line"
      done <<< "$_BH_REMUX_PROBE_ERR"
    fi
    emit_status \
      "----------------------------------------------------------------" \
      "INFO: MODE=ENCODE  (HandBrakeCLI; preset: $preset)" \
      "----------------------------------------------------------------"

    # Windows HandBrakeCLI.exe expects Z:\... paths, not /mnt/z/... (WSL) or MSYS POSIX.
    local hb_in_arg="$in" hb_out_arg="$tmpout"
    if [[ "${BH_HANDBRAKE_CLI_BIN,,}" == *.exe ]]; then
      if command -v cygpath >/dev/null 2>&1; then
        hb_in_arg=$(cygpath -w "$in" 2>/dev/null || printf '%s\n' "$in")
        hb_out_arg=$(cygpath -w "$tmpout" 2>/dev/null || printf '%s\n' "$tmpout")
      elif command -v wslpath >/dev/null 2>&1; then
        hb_in_arg=$(wslpath -w "$in" 2>/dev/null || printf '%s\n' "$in")
        hb_out_arg=$(wslpath -w "$tmpout" 2>/dev/null || printf '%s\n' "$tmpout")
      fi
    fi

    BH_PROGRESS_FILE="${in##*/}" \
    encoder_run_handbrake "$BH_HANDBRAKE_CLI_BIN" \
      --preset-import-gui \
      --json \
      -i "$hb_in_arg" \
      -o "$hb_out_arg" \
      --preset="$preset" </dev/null
    mv "$tmpout" "$out"
  fi
  # Remove staging dir when empty (successful mv moved the only file out).
  rmdir "$tmpdir" 2>/dev/null || true
}

############################
# RUN (sequential, foreground)
############################
# Task list is on stdin; encoders must not read stdin or they consume the next path.

mapfile -t _BH_TASKS < <(build_tasks)
_BH_TASK_N="${#_BH_TASKS[@]}"
for ((_bh_i = 0; _bh_i < _BH_TASK_N; _bh_i++)); do
  f="${_BH_TASKS[_bh_i]}"
  [[ -z "$f" ]] && continue
  f="${f%$'\r'}"
  out="$(map_output "$f")"
  BH_PROGRESS_INDEX=$((_bh_i + 1)) BH_PROGRESS_TOTAL="$_BH_TASK_N" process_file "$f" "$out"
done

