#!/usr/bin/env bash
# watch-and-source.sh
# Watch paths (files or directories); when they change, queue paths for the
# interactive shell to source. A child process cannot source your terminal —
# run the watcher in the background, then in ~/.bashrc:
#
#   source /path/to/autosource.sh --shell-hook
#   PROMPT_COMMAND="_autosource_drain${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
#
# Optional: AUTOSOURCE_QUEUE (default: ~/.local/state/autosource/pending)
#
# Usage:
#   autosource.sh [-q FILE] [-t SECONDS] PATH [PATH ...]   # watcher (enqueue only)
#   source autosource.sh --shell-hook [-q FILE]             # define _autosource_drain

DEFAULT_QUEUE="${XDG_STATE_HOME:-$HOME/.local/state}/autosource/pending"
AUTOSOURCE_QUEUE="${AUTOSOURCE_QUEUE:-$DEFAULT_QUEUE}"

if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" == "--shell-hook" ]]; then
    echo "This must be sourced so reloading runs in your interactive shell:" >&2
    echo "  source ${0##*/} --shell-hook [-q FILE]" >&2
    exit 1
fi

# Sourced one-liner: defines _autosource_drain for PROMPT_COMMAND.
if [[ "${BASH_SOURCE[0]}" != "${0}" && "${1:-}" == "--shell-hook" ]]; then
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--queue)
                AUTOSOURCE_QUEUE="${2:?missing value for $1}"
                shift 2
                ;;
            -h|--help)
                echo "Usage: source ${BASH_SOURCE[0]##*/} --shell-hook [-q FILE]"
                echo "  Defines _autosource_drain; add to PROMPT_COMMAND to reload queued files in this shell."
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done
    _autosource_drain() {
        local _as_def="${XDG_STATE_HOME:-$HOME/.local/state}/autosource/pending"
        local q="${AUTOSOURCE_QUEUE:-$_as_def}"
        [[ -s "$q" ]] || return 0
        local tmp
        tmp=$(mktemp "${TMPDIR:-/tmp}/autosource.XXXXXX") || return 1
        if ! mv "$q" "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            return 0
        fi
        local line lines=()
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            [[ -n "$line" ]] && lines+=("$line")
        done < "$tmp"
        rm -f "$tmp"
        local f
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            # shellcheck disable=SC1090
            source "$f"
            echo "Sourced: $f" >&2
        done < <(printf '%s\n' "${lines[@]}" | sort -u)
    }
    return 0 2>/dev/null || exit 0
fi

DEBOUNCE=2
WATCH_PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--debounce)
            DEBOUNCE="${2:?missing value for $1}"
            shift 2
            ;;
        -q|--queue)
            AUTOSOURCE_QUEUE="${2:?missing value for $1}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: ${0##*/} [-q FILE] [-t SECONDS] PATH [PATH ...]"
            echo "  Watcher: enqueue changed files for your shell (see header comments)."
            echo "  source ${0##*/} --shell-hook [-q FILE]  — define _autosource_drain for PROMPT_COMMAND."
            echo "  -q, --queue FILE    Pending list (default: $DEFAULT_QUEUE)"
            echo "  -t, --debounce SEC  Debounce interval in seconds (default: 2)"
            exit 0
            ;;
        --)
            shift
            WATCH_PATHS+=("$@")
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: ${0##*/} [-q FILE] [-t SECONDS] PATH [PATH ...]" >&2
            exit 1
            ;;
        *)
            WATCH_PATHS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#WATCH_PATHS[@]} -eq 0 ]]; then
    echo "Usage: ${0##*/} [-q FILE] [-t SECONDS] PATH [PATH ...]" >&2
    exit 1
fi

for p in "${WATCH_PATHS[@]}"; do
    if [[ ! -e "$p" ]]; then
        echo "Not found: $p" >&2
        exit 1
    fi
    if [[ ! -f "$p" && ! -d "$p" ]]; then
        echo "Not a file or directory: $p" >&2
        exit 1
    fi
done

mkdir -p "$(dirname -- "$AUTOSOURCE_QUEUE")"

enqueue_path() {
    local f="$1"
    printf '%s\n' "$f" >>"$AUTOSOURCE_QUEUE"
    echo "Queued: $f" >&2
}

# True if $2 is the immediate parent directory of $1 (after resolving paths).
is_direct_child_of_dir() {
    local f="$1" dir="$2" parent
    parent=$(cd "$(dirname -- "$f")" 2>/dev/null && pwd -P) || return 1
    dir=$(cd -- "$dir" 2>/dev/null && pwd -P) || return 1
    [[ "$parent" == "$dir" ]]
}

should_source_path() {
    local f="$1" p
    [[ -f "$f" ]] || return 1
    for p in "${WATCH_PATHS[@]}"; do
        if [[ -f "$p" && "$f" == "$p" ]]; then
            return 0
        fi
        if [[ -d "$p" ]] && is_direct_child_of_dir "$f" "$p"; then
            return 0
        fi
    done
    return 1
}

# check for inotifywait
if command -v inotifywait >/dev/null 2>&1; then
    inotify_opts=(-e close_write,moved_to,create -q)
    for p in "${WATCH_PATHS[@]}"; do
        if [[ -d "$p" ]]; then
            inotify_opts+=(-r)
            break
        fi
    done
    while true; do
        IFS= read -r changed < <(
            inotifywait "${inotify_opts[@]}" "${WATCH_PATHS[@]}" --format '%w%f'
        ) || continue
        [[ -n "$changed" ]] || continue
        sleep "$DEBOUNCE"
        should_source_path "$changed" || continue
        enqueue_path "$changed"
    done
else
    echo "inotifywait not found, using polling fallback" >&2
    declare -A mtimes
    while true; do
        sleep "$DEBOUNCE"
        for target in "${WATCH_PATHS[@]}"; do
            files=()
            if [[ -f "$target" ]]; then
                files=("$target")
            elif [[ -d "$target" ]]; then
                shopt -s nullglob dotglob
                for f in "$target"/*; do
                    [[ -f "$f" ]] && files+=("$f")
                done
                shopt -u nullglob dotglob
            fi
            for f in "${files[@]}"; do
                mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
                if [[ "${mtimes[$f]:-}" != "$mtime" ]]; then
                    mtimes[$f]=$mtime
                    enqueue_path "$f"
                fi
            done
        done
    done
fi
