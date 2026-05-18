#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR_FISSION="$SCRIPT_DIR/../dir-fission"

pass=0
fail=0

# ── helpers ───────────────────────────────────────────────────────────────────

ok()  { echo "  PASS: $*"; ((pass++)); }
bad() { echo "  FAIL: $*"; ((fail++)); }

assert_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then ok "exists:  $path"
    else                       bad "missing: $path"
    fi
}

assert_absent() {
    local path="$1"
    if [[ ! -e "$path" ]]; then ok "absent:  $path"
    else                        bad "present (should be gone): $path"
    fi
}

make_src() {           # make_src <dest-path>  — copy SourceDir fixture there
    cp -r "$SCRIPT_DIR/SourceDir" "$1"
}

cleanup() { rm -rf "$SCRIPT_DIR"/tmp_test_*; }
trap cleanup EXIT

# ── test: top-level directory is preserved ────────────────────────────────────

test_top_dir_preserved() {
    echo "Test: top-level source directory is preserved in destination"
    local tmp; tmp=$(mktemp -d "$SCRIPT_DIR/tmp_test_XXXXXX")
    make_src "$tmp/MyShow"
    local dst="$tmp/dest"

    DIR_FISSION_DEST_DIR="$dst" "$DIR_FISSION" "$tmp/MyShow"

    # Video files must land under dest/MyShow/
    assert_exists "$dst/MyShow/a.mkv"
    assert_exists "$dst/MyShow/a.avi"
    assert_exists "$dst/MyShow/a.MOV"
    assert_exists "$dst/MyShow/hi spaces.mkv"
    assert_exists "$dst/MyShow/subdir/b.mov"

    # Video files must be gone from source
    assert_absent "$tmp/MyShow/a.mkv"
    assert_absent "$tmp/MyShow/subdir/b.mov"

    # Non-video files must remain in source, not appear in dest
    assert_exists "$tmp/MyShow/a.mp4"
    assert_exists "$tmp/MyShow/a.m4v"
    assert_exists "$tmp/MyShow/b.txt"
    assert_exists "$tmp/MyShow/hi spaces.mp4"
    assert_exists "$tmp/MyShow/hi spaces.txt"
    assert_exists "$tmp/MyShow/subdir/subsubdir/c.gif"
    assert_exists "$tmp/MyShow/subdir/subsubdir/c.mp4"
    assert_exists "$tmp/MyShow/subdir/subsubdir/c.nfo"
    assert_absent "$dst/MyShow/a.mp4"
    assert_absent "$dst/MyShow/b.txt"
}

# ── test: trailing slash on source arg ────────────────────────────────────────

test_trailing_slash() {
    echo "Test: trailing slash still preserves top-level directory"
    local tmp; tmp=$(mktemp -d "$SCRIPT_DIR/tmp_test_XXXXXX")
    make_src "$tmp/ShowWithSlash"
    local dst="$tmp/dest"

    DIR_FISSION_DEST_DIR="$dst" "$DIR_FISSION" "$tmp/ShowWithSlash/"

    assert_exists "$dst/ShowWithSlash/a.mkv"
    assert_absent "$tmp/ShowWithSlash/a.mkv"
}

# ── test: multiple source directories ─────────────────────────────────────────

test_multiple_sources() {
    echo "Test: multiple source directories each appear under destination"
    local tmp; tmp=$(mktemp -d "$SCRIPT_DIR/tmp_test_XXXXXX")
    make_src "$tmp/ShowA"
    make_src "$tmp/ShowB"
    local dst="$tmp/dest"

    DIR_FISSION_DEST_DIR="$dst" "$DIR_FISSION" "$tmp/ShowA" "$tmp/ShowB"

    assert_exists "$dst/ShowA/a.mkv"
    assert_exists "$dst/ShowB/a.mkv"
    assert_absent "$tmp/ShowA/a.mkv"
    assert_absent "$tmp/ShowB/a.mkv"
}

# ── test: -o flag overrides dest ──────────────────────────────────────────────

test_o_flag() {
    echo "Test: -o flag sets destination directory"
    local tmp; tmp=$(mktemp -d "$SCRIPT_DIR/tmp_test_XXXXXX")
    make_src "$tmp/MyShow"
    local dst="$tmp/custom_dest"

    "$DIR_FISSION" -o "$dst" "$tmp/MyShow"

    assert_exists "$dst/MyShow/a.mkv"
    assert_absent "$tmp/MyShow/a.mkv"
}

# ── run ───────────────────────────────────────────────────────────────────────

test_top_dir_preserved
test_trailing_slash
test_multiple_sources
test_o_flag

echo ""
if [[ $fail -eq 0 ]]; then
    echo "All $pass assertions passed."
    exit 0
else
    echo "$pass passed, $fail FAILED."
    exit 1
fi
