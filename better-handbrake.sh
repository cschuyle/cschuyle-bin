#!/usr/bin/env bash
set -euo pipefail

_bh_now() { date '+%Y-%m-%d %H:%M:%S'; }

trap 'printf "%s: ERROR line %s: %s\n" "$(_bh_now)" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Each argument may contain multiple lines; every line gets its own timestamp on stderr
# (and /dev/tty when stderr is not a TTY, same as before).
emit_status() {
  local s line ts
  for s in "$@"; do
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      ts="$(_bh_now)"
      printf '%s: %s\n' "$ts" "$line" >&2
      if [[ ! -t 2 ]]; then
        printf '%s: %s\n' "$ts" "$line" >/dev/tty 2>/dev/null || true
      fi
    done <<< "$s"
  done
}

# Timestamped lines on stdout (e.g. preset list).
_bh_ts_out() {
  local s line ts
  for s in "$@"; do
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      ts="$(_bh_now)"
      printf '%s: %s\n' "$ts" "$line"
    done <<< "$s"
  done
}

# Timestamp each line from stdin (pipeline tail).
_bh_ts_pipe_stdout() {
  local line ts
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    ts="$(_bh_now)"
    printf '%s: %s\n' "$ts" "$line"
  done
}

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
continue_mode=0
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
        emit_status "ERROR: --pattern requires a value (e.g. --pattern='*.mkv')"
        exit 1
      }
      file_pattern="$1"
      shift
      ;;
    --continue)
      continue_mode=1
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

while getopts "co:p:lP:" opt; do
  case $opt in
    c) continue_mode=1 ;;
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
    emit_status "Missing HandBrakeCLI or HandBrakeCLI.exe (set BH_HANDBRAKE_CLI_BIN)"
    exit 1
  }
  _bh_ts_out "=== Presets (built-in + custom from HandBrake GUI) ==="
  if [[ "$list_presets" -ge 2 ]]; then
    "$BH_HANDBRAKE_CLI_BIN" --preset-import-gui --preset-list 2>&1 | awk '
      { gsub(/\r/, "", $0)
        if ($0 ~ /^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/) next
        print
      }' | _bh_ts_pipe_stdout
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
      }' | _bh_ts_pipe_stdout
  fi

  printf '\n'
  _bh_ts_out "NOTE: CLI Default is NOT what you think it is."
  if [[ "$_bh_default_preset_note" -eq 1 ]]; then
    _bh_ts_out "NOTE: BH_DEFAULT_PRESET is set; default encode preset is: ${BH_DEFAULT_PRESET}"
  fi
  exit 0
fi

[[ $# -ne 1 ]] && {
  emit_status "Usage: $0 [-l|-ll]   # list presets (no input); -ll includes descriptions"
  emit_status "       $0 [-c|--continue] [-o out] [-p preset] [-P|--pattern <filename pattern>] <input file(s)/directory(ies)>"
  emit_status "  -c --continue: skip inputs whose final output already exists; rename stale temp outputs to .OLD-<timestamp>."
  emit_status "  -P --pattern: when <input> is a directory, only encode files matching the glob."
  emit_status ""
  emit_status "Environment:"
  emit_status "  BH_HANDBRAKE_CLI_BIN                  HandBrakeCLI path (when not found on PATH)"
  emit_status "  BH_DEFAULT_PRESET      -p             Use HandBrake preset (else: Preset Not Defined)"
  emit_status "  BH_FILE_PATTERN        -P,--pattern   Encode only filenames matching pattern (when <input> is a directory)"
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
    find "$input" \( -type d -name '@*' -prune \) -o \
      \( -type f -not -name '._*' -iname "$file_pattern" -print \) | sort -u
  else
    find "$input" \( -type d -name '@*' -prune \) -o \
      \( -type f -not -name '._*' \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" \) -print \) | sort -u
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

if [[ "$continue_mode" -eq 0 ]]; then
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
        emit_status "ERROR: output already exists: $(path_sq "$out")"
      fi
    fi
  done < <(build_tasks)
  (( existing_out == 0 )) || exit 1
  unset existing_out_seen
fi

############################
# DEPENDENCY CHECKS
############################

command -v ffmpeg >/dev/null || {
  emit_status "Missing ffmpeg"
  exit 1
}

[[ -n "$BH_HANDBRAKE_CLI_BIN" ]] && command -v "$BH_HANDBRAKE_CLI_BIN" >/dev/null 2>&1 || {
  emit_status "Missing HandBrakeCLI or HandBrakeCLI.exe (set BH_HANDBRAKE_CLI_BIN)"
  exit 1
}

[[ -z "$preset" ]] && {
  emit_status "No preset set (-p or BH_DEFAULT_PRESET)"
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
  emit_status "ERROR: encoder failed (exit $st)"
  local _elog
  while IFS= read -r _elog || [[ -n "${_elog:-}" ]]; do
    emit_status "$_elog"
  done <"$log"
  rm -f "$log"
  return "$st"
}

# Collapse HandBrake --json repeated "Progress: { ... }" blocks to one \r line (ETA + %).
# Optional: BH_PROGRESS_FILE (input basename), BH_PROGRESS_INDEX / BH_PROGRESS_TOTAL
# for a "(n/m) name    " prefix before ETA (set by the main task loop).
# All other HandBrake lines (scan, JSON job dump, job config) are suppressed; one
# timestamped summary line is printed when encoding starts (preset, size/fps, duration).
handbrake_json_progress_filter() {
  awk -v fname="${BH_PROGRESS_FILE:-}" \
      -v cur="${BH_PROGRESS_INDEX:-0}" \
      -v tot="${BH_PROGRESS_TOTAL:-0}" '
  BEGIN {
    inblk = 0; dep = 0; buf = ""
    summary_emitted = 0
    hb_preset = ""; hb_dur = ""; hb_geo = ""
  }
  function count_braces(s,    i, c, n) {
    n = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "{") n++
      if (c == "}") n--
    }
    return n
  }
  function tsline(l,    dcmd, t, e) {
    dcmd = "date \"+%Y-%m-%d %H:%M:%S\""
    e = (dcmd | getline t)
    close(dcmd)
    if (e > 0) print t ": " l
    else print l
    fflush()
  }
  function sniff_meta(line) {
    gsub(/\r/, "", line)
    if (match(line, /Using preset:[[:space:]]*/)) {
      hb_preset = substr(line, RSTART + RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", hb_preset)
    }
    if (match(line, /\+[[:space:]]+duration:[[:space:]]*/)) {
      hb_dur = substr(line, RSTART + RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", hb_dur)
    }
    if (match(line, /\+[[:space:]]+size:[[:space:]]*/)) {
      hb_geo = substr(line, RSTART + RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", hb_geo)
      if (length(hb_geo) > 120) hb_geo = substr(hb_geo, 1, 117) "..."
    }
  }
  function emit_hb_summary_once(    sum, x) {
    if (summary_emitted) return
    summary_emitted = 1
    sum = "HandBrake"
    if ((tot + 0) > 0 && (cur + 0) > 0)
      sum = sum sprintf(" (%d/%d)", cur + 0, tot + 0)
    if (length(fname) > 0) sum = sum " " fname
    x = ""
    if (length(hb_preset) > 0) x = x (x == "" ? "" : " | ") hb_preset
    if (length(hb_geo) > 0) x = x (x == "" ? "" : " | ") hb_geo
    if (length(hb_dur) > 0) x = x (x == "" ? "" : " | ") hb_dur
    if (length(x) > 0) sum = sum ": " x
    else sum = sum ": encode started"
    tsline(sum)
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
    emit_hb_summary_once()
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
  {
    sniff_meta($0)
    if ($0 ~ /Starting Task:/) emit_hb_summary_once()
    next
  }
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
  emit_status "ERROR: encoder failed (exit $st)"
  if grep -q "Invalid preset" "$log" 2>/dev/null; then
    emit_status "HINT: preset name must match HandBrake GUI (custom presets need import; list: $BH_HANDBRAKE_CLI_BIN --preset-import-gui --preset-list)."
  fi
  if ((_hb_streamed_stderr)); then
    emit_status "INFO: stderr was already shown above; not repeating the full log."
  else
    local _elog
    while IFS= read -r _elog || [[ -n "${_elog:-}" ]]; do
      emit_status "$_elog"
    done <"$log"
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

# File size in bytes (0 if missing); GNU stat first, then BSD.
_bh_file_size_bytes() {
  local f="$1" sz
  [[ -f "$f" ]] || {
    printf '%s\n' 0
    return
  }
  if sz=$(stat -c%s -- "$f" 2>/dev/null); then
    printf '%s\n' "$sz"
  elif sz=$(stat -f%z "$f" 2>/dev/null); then
    printf '%s\n' "$sz"
  else
    printf '%s\n' 0
  fi
}

# Human-readable byte size (binary Ki/Mi/Gi/Ti or plain B).
_bh_hr_bytes() {
  local b="$1"
  [[ "$b" =~ ^[0-9]+$ ]] || b=0
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$b" 2>/dev/null && return
  fi
  local n div=1 i
  local -a suf=(B Ki Mi Gi Ti)
  for ((i = 0; i < ${#suf[@]}; i++)); do
    if ((b < 1024 * div || i == ${#suf[@]} - 1)); then
      if ((i == 0)); then
        printf '%d%s\n' "$b" "${suf[i]}"
      else
        n=$((b * 100 / div))
        printf '%d.%02d%s\n' $((n / 100)) $((n % 100)) "${suf[i]}"
      fi
      return
    fi
    ((div *= 1024))
  done
}

_bh_fmt_elapsed() {
  local t=$1 s m h
  ((t < 0)) && t=0
  if ((t < 60)); then
    printf '%ds' "$t"
  elif ((t < 3600)); then
    m=$((t / 60))
    s=$((t % 60))
    printf '%dm %ds' "$m" "$s"
  else
    h=$((t / 3600))
    m=$(((t % 3600) / 60))
    s=$((t % 60))
    printf '%dh %dm %ds' "$h" "$m" "$s"
  fi
}

############################
# PROCESS FILE
############################

process_file() {
  local in="$1"
  local out="$2"
  local _bh_ptag=""
  if [[ -n "${BH_PROGRESS_TOTAL:-}" ]] && [[ "${BH_PROGRESS_TOTAL}" =~ ^[0-9]+$ ]] &&
    ((BH_PROGRESS_TOTAL > 0)) && [[ -n "${BH_PROGRESS_INDEX:-}" ]] &&
    [[ "${BH_PROGRESS_INDEX}" =~ ^[0-9]+$ ]]; then
    _bh_ptag="[${BH_PROGRESS_INDEX}/${BH_PROGRESS_TOTAL}]: "
  fi

  if [[ -e "$out" ]]; then
    if [[ "${continue_mode:-0}" -eq 1 ]]; then
      if [[ -n ${_BH_ALREADY_DONE_OUT["$out"]+x} ]]; then
        return 0
      fi
      _BH_ALREADY_DONE_OUT["$out"]=1
      emit_status "INFO: ${_bh_ptag}already done: $(path_sq "$out")"
      return 0
    fi
    emit_status "ERROR: output already exists: $(path_sq "$out")"
    return 1
  fi

  local outdir tmpdir tmpout
  outdir="$(dirname "$out")"
  tmpdir="$outdir/temp"
  tmpout="$tmpdir/$(basename "$out")"

  mkdir -p "$outdir" || {
    emit_status "ERROR: cannot create output directory: $(path_sq "$outdir")"
    return 1
  }
  if ! mkdir -p "$tmpdir"; then
    emit_status "ERROR: cannot create temp directory: $(path_sq "$tmpdir")"
    return 1
  fi

  if [[ "${continue_mode:-0}" -eq 1 && -e "$tmpout" ]]; then
    local _old_ts _old_dest
    _old_ts="$(date '+%Y%m%d%H%M%S')"
    _old_dest="${tmpout}.OLD-${_old_ts}"
    if [[ -e "$_old_dest" ]]; then
      _old_dest="${tmpout}.OLD-${_old_ts}-$$"
    fi
    mv -- "$tmpout" "$_old_dest" || {
      emit_status "ERROR: cannot rename stale temp file: $(path_sq "$tmpout")"
      return 1
    }
  fi

  local _bh_t0
  _bh_t0=$SECONDS

  local _in_start_b _in_start_hr
  _in_start_b="$(_bh_file_size_bytes "$in")"
  _in_start_hr="$(_bh_hr_bytes "$_in_start_b")"
  emit_status "INFO: ${_bh_ptag}[IN ] $in (${_in_start_hr})"
  emit_status "INFO: ${_bh_ptag}[OUT] $out"

  emit_status "INFO: ${_bh_ptag}probing whether MP4 stream-copy (remux) is possible..."
  if can_remux "$in"; then
    emit_status "INFO: ${_bh_ptag}MODE=REMUX  (ffmpeg -c copy to MP4; no re-encode)"

    encoder_run ffmpeg -nostdin -hide_banner -loglevel error -nostats -i "$in" \
      -map 0 \
      -c copy \
      -movflags +faststart \
      "$tmpout" </dev/null
    mv "$tmpout" "$out"

  else
    emit_status "INFO: ${_bh_ptag}MP4 stream-copy (remux) is not possible for this file."
    if [[ -n "${_BH_REMUX_PROBE_ERR:-}" ]]; then
      emit_status "INFO: ${_bh_ptag}ffmpeg:"
      local _line
      while IFS= read -r _line || [[ -n "${_line:-}" ]]; do
        emit_status "  $_line"
      done <<< "$_BH_REMUX_PROBE_ERR"
    fi
    emit_status "INFO: ${_bh_ptag}MODE=ENCODE  (HandBrakeCLI; preset: $preset)"

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

  local _in_b _out_b _in_hr _out_hr _el_s _el_hr
  _in_b="$(_bh_file_size_bytes "$in")"
  _out_b="$(_bh_file_size_bytes "$out")"
  _in_hr="$(_bh_hr_bytes "$_in_b")"
  _out_hr="$(_bh_hr_bytes "$_out_b")"
  _el_s=$((SECONDS - _bh_t0))
  _el_hr="$(_bh_fmt_elapsed "$_el_s")"
  emit_status "INFO: ${_bh_ptag}--- Done --- [IN: ${_in_hr}] [OUT: ${_out_hr}]  [elapsed: ${_el_hr}]"
  rmdir "$tmpdir" 2>/dev/null || true
}

############################
# RUN (sequential, foreground)
############################
# Task list is on stdin; encoders must not read stdin or they consume the next path.

mapfile -t _BH_TASKS < <(build_tasks)
if [[ "${continue_mode:-0}" -eq 1 ]]; then
  declare -A _bh_skip_logged=()
  _BH_TODO=()
  for ((_bh_j = 0; _bh_j < ${#_BH_TASKS[@]}; _bh_j++)); do
    f="${_BH_TASKS[_bh_j]}"
    [[ -z "$f" ]] && continue
    f="${f%$'\r'}"
    out="$(map_output "$f")"
    if [[ -e "$out" ]]; then
      if [[ -z ${_bh_skip_logged["$out"]+x} ]]; then
        _bh_skip_logged["$out"]=1
        emit_status "INFO: already done: $(path_sq "$out")"
      fi
    else
      _BH_TODO+=("$f")
    fi
  done
  _BH_TASKS=("${_BH_TODO[@]}")
  unset _bh_skip_logged
fi
_BH_TASK_N="${#_BH_TASKS[@]}"
declare -A _BH_ALREADY_DONE_OUT=()
for ((_bh_i = 0; _bh_i < _BH_TASK_N; _bh_i++)); do
  f="${_BH_TASKS[_bh_i]}"
  [[ -z "$f" ]] && continue
  f="${f%$'\r'}"
  out="$(map_output "$f")"
  BH_PROGRESS_INDEX=$((_bh_i + 1)) BH_PROGRESS_TOTAL="$_BH_TASK_N" process_file "$f" "$out"
done

