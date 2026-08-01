# Shared helpers for move-file-list and copy-file-list.

file_list_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

file_list_unescape_backslashes() {
  local input="$1"
  local out="" i c len=${#input}

  for (( i = 0; i < len; i++ )); do
    c=${input:i:1}
    if [[ "$c" == '\' ]] && (( i + 1 < len )); then
      (( i++ ))
      c=${input:i:1}
      case "$c" in
        n) out+=$'\n' ;;
        r) out+=$'\r' ;;
        t) out+=$'\t' ;;
        *) out+="$c" ;;
      esac
    else
      out+="$c"
    fi
  done

  printf '%s' "$out"
}

file_list_parse_line() {
  local line="$1"
  local len inner_len

  line="$(file_list_trim "$line")"
  [[ -z "$line" ]] && return 1

  len=${#line}
  inner_len=$((len - 2))

  if (( len >= 2 )) && [[ ${line:0:1} == "'" && ${line: -1} == "'" ]]; then
    printf '%s' "${line:1:inner_len}"
    return 0
  fi

  if (( len >= 2 )) && [[ ${line:0:1} == '"' && ${line: -1} == '"' ]]; then
    file_list_unescape_backslashes "${line:1:inner_len}"
    return 0
  fi

  file_list_unescape_backslashes "$line"
}

file_list_run_or_warn() {
  local action="$1"
  local path="$2"
  local target_dir="$3"
  shift 3
  local err

  if ! err=$("$@" -- "$path" "$target_dir" 2>&1); then
    echo "warning: could not $action '$path' to '$target_dir': $err" >&2
    return 1
  fi
}
