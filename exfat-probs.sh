#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"
root="${root%/}"   # strip trailing slash

reserved_regex='^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$'
invalid_chars='[<>:"\\|?*\x00-\x1F]'

declare -A seen_ci
bad=0

normalize_path() {
    local path="$1"
    local IFS='/'
    local parts=()
    read -ra parts <<< "$path"

    local norm_parts=()
    for part in "${parts[@]}"; do
        # strip trailing dots/spaces (Windows semantics)
        part="$(printf '%s' "$part" | sed 's/[. ]*$//')"
        # case-fold (ASCII; good enough for most cases)
        part="$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]')"
        norm_parts+=("$part")
    done

    (IFS=/; printf '%s' "${norm_parts[*]}")
}

while IFS= read -r -d '' path; do
    rel="${path#"$root"/}"
    base="$(basename "$rel")"

    # 1. Invalid characters
    if [[ "$rel" =~ $invalid_chars ]]; then
        echo "INVALID_CHARS: $path"
        ((bad++))
    fi

    # 2. Trailing space or dot (Windows semantics)
    trimmed="$(printf '%s' "$base" | sed 's/[. ]*$//')"
    if [[ "$base" != "$trimmed" ]]; then
        echo "TRAILING_DOT_OR_SPACE: $path"
        ((bad++))
    fi

    # 3. Reserved names (per path component)
    IFS='/' read -ra parts <<< "$rel"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ $reserved_regex ]]; then
            echo "RESERVED_NAME: $path"
            ((bad++))
            break
        fi
    done

    # 4. Path length (conservative Windows limit)
    if (( ${#rel} > 259 )); then
        echo "PATH_TOO_LONG: $path (${#rel})"
        ((bad++))
    fi

    # 5. Symlinks
    if [[ -L "$path" ]]; then
        echo "SYMLINK: $path"
    fi

    # 6. Case-insensitive + Windows-normalized collisions
    norm="$(normalize_path "$rel")"
    if [[ -n "${seen_ci[$norm]:-}" ]]; then
        echo "CASE_COLLISION:"
        echo "  $path"
        echo "  ${seen_ci[$norm]}"
        ((bad++))
    else
        seen_ci["$norm"]="$path"
    fi

done < <(find "$root" -mindepth 1 -print0)

if (( bad > 0 )); then
    echo "Found $bad blocking issue(s)."
    exit 1
else
    echo "No blocking issues found."
fi
