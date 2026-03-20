#!/usr/bin/env bash
# Run `git pull -r` in each immediate subdirectory of the current directory that is a git repo.
set -u
shopt -s nullglob

err() {
  printf '%s\n' "$*" >&2
}

if ! command -v git >/dev/null 2>&1; then
  err "error: git is not installed or not in PATH"
  exit 1
fi

if ! root=$(pwd -P); then
  err "error: could not determine current directory"
  exit 1
fi

failed_names=()

for entry in "$root"/*; do
  if [[ ! -d "$entry" ]]; then
    continue
  fi
  if [[ ! -d "$entry/.git" ]]; then
    continue
  fi

  name=$(basename "$entry")
  printf '==> %s\n' "$entry" >&2
  output=$(cd "$entry" && git pull -r 2>&1) || status=$?
  printf '%s\n' "$output" >&2
  if [[ ${status:-0} -ne 0 ]]; then
    failed_names+=("$name")
  fi
  unset status
done

if ((${#failed_names[@]} > 0)); then
  err ""
  err "=== Failed repos (${#failed_names[@]}) ==="
  for n in "${failed_names[@]}"; do
    err "  $n"
  done
  err "error: ${#failed_names[@]} repo(s) failed"
  exit 1
fi

exit 0
