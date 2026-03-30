#!/usr/bin/env bash
set -euo pipefail

filter="${1:-}"

# List all Synology share names, and their corresponding directories

shares=$(synoshare --enum | awk '
/Listed:/ {flag=1; next}
flag && NF {print $1}
')

for share in $shares; do
    # If filter provided, skip non-matching shares
    if [[ -n "$filter" && "$share" != "$filter" ]]; then
        continue
    fi

    info=$(synoshare --getmap "$share")

    path=$(echo "$info" | awk '
    /Path/ {
        if (match($0, /\[([^\]]+)\]/, m)) {
            print m[1]
        }
    }')

    if [[ -n "${path:-}" ]]; then
        echo "$share $path"
    else
        echo "$share <no path>"
    fi
done
