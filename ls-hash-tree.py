#!/usr/bin/env python3
import argparse
import datetime
import os
import sys
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import time
import signal

''' Setup instructions:
# bash:

# Onetime setup:

# If you have a setup with multiple python version then maybe this or similar:
alias python3=python3.14
# Assuming $DIR is where you write the Python venv definition, for example: 
DIR="$HOME"
source $DIR/LS-HASH-TREE-PY-VENV/bin/activate
python3 -m venv $DIR/LS-HASH-TREE-PY-VENV
python3 -m pip install blake3
python3 -m pip install pathspec

# After all the above once, this is all you need:

source $DIR/LS-HASH-TREE-PY-VENV/bin/activate
# If you have a setup with multiple python version then maybe this or similar:
alias python=python3.9
alias python3=python3.9

# Now you should be able to run this script.
'''
# ------------------ Imports ------------------
try:
    import pathspec
except ImportError:
    print("Package pathspec not found. Install with: python3 -m pip install [--user] pathspec", file=sys.stderr)
    sys.exit(1)

# ------------------ CLI ------------------
_parser = argparse.ArgumentParser(
    description="Walk a directory tree and emit JSON (stats by default; use --hash for BLAKE3)."
)
_parser.add_argument(
    "--hash",
    action="store_true",
    help="Compute BLAKE3 hash for each file (requires blake3 package).",
)
_parser.add_argument("root", nargs="?", default=".", help="Root directory to scan")
_parser.add_argument(
    "ignore_file",
    nargs="?",
    default=".myignore",
    help="Gitwildmatch ignore file (default: .myignore)",
)
_args = _parser.parse_args()

DO_HASH = _args.hash
blake3 = None
if DO_HASH:
    try:
        import blake3 as _blake3_mod
        blake3 = _blake3_mod
    except ImportError:
        print("Package blake3 not found. Install with: python3 -m pip install [--user] blake3", file=sys.stderr)
        print("  Or run without --hash to skip computing hashes.", file=sys.stderr)
        sys.exit(1)

# ------------------ Configuration ------------------
ROOT = os.path.abspath(_args.root)
IGNORE_FILE = _args.ignore_file
JOBS = int(os.environ.get("JOBS", os.cpu_count()))
CHUNK_SIZE = 16 * 1024 * 1024  # 16 MB read chunks
EMA_ALPHA = 0.2  # smoothing factor for ETA
TRACE_ENABLED = bool(os.environ.get("TRACE"))

# ------------------ Ctrl-C handling ------------------
interrupted = False

def signal_handler(sig, frame):
    global interrupted
    interrupted = True
    print("\n[INFO] Ctrl-C detected, shutting down...", file=sys.stderr)

signal.signal(signal.SIGINT, signal_handler)

# ------------------ Load ignore file ------------------
if os.path.exists(IGNORE_FILE):
    with open(IGNORE_FILE, "r") as f:
        spec = pathspec.PathSpec.from_lines("gitwildmatch", f)
    print(f"[INFO] Loaded ignore file: {IGNORE_FILE}", file=sys.stderr)
else:
    spec = pathspec.PathSpec([])

def ignored(path):
    rel = os.path.relpath(path, ROOT)
    return spec.match_file(rel)

# ------------------ Collect files ------------------
all_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not ignored(os.path.join(dirpath, d))]
    for f in filenames:
        full_path = os.path.join(dirpath, f)
        if ignored(full_path):
            continue
        all_files.append(full_path)

print(f"[INFO] Found {len(all_files)} files to process under {ROOT}", file=sys.stderr)


def mtime_human(ts):
    """Format modification time as local wall-clock string for JSON \"update-time\" field."""
    try:
        if ts == 0:
            return ""
        return datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OSError, OverflowError):
        return ""


# ------------------ Per-file work (hash optional) ------------------
def file_info(path):
    try:
        size = os.path.getsize(path)
        mtime_raw = os.path.getmtime(path)
        mtime = mtime_human(mtime_raw)
        if DO_HASH:
            h = blake3.blake3()
            with open(path, "rb") as fd:
                while chunk := fd.read(CHUNK_SIZE):
                    h.update(chunk)
            digest = h.hexdigest()
            print(f"[HASHED] {path}", file=sys.stderr)
        else:
            digest = None
            if TRACE_ENABLED:
                print(f"[STAT] {path}", file=sys.stderr)
        return path, size, mtime, digest
    except Exception as e:
        print(f"[ERROR] {path}: {e}", file=sys.stderr)
        return path, 0, "", None

# ------------------ Parallel hashing with smart ETA ------------------
file_data = {}
start_time = time()
ema_file_time = None
last_progress_time = start_time
last_progress_count = 0

with ThreadPoolExecutor(max_workers=JOBS) as executor:
    futures = {executor.submit(file_info, path): path for path in all_files}
    try:
        for i, fut in enumerate(as_completed(futures), 1):
            if interrupted:
                for f in futures:
                    f.cancel()
                raise KeyboardInterrupt

            path, size, mtime, blake3_hash = fut.result()
            if DO_HASH:
                file_data[path] = {"size-bytes": size, "update-time": mtime, "blake3-hash": blake3_hash}
            else:
                file_data[path] = {"size-bytes": size, "update-time": mtime}

            # ETA calculation with EMA
            elapsed = time() - start_time
            per_file_time = elapsed / i
            if ema_file_time is None:
                ema_file_time = per_file_time
            else:
                ema_file_time = EMA_ALPHA * per_file_time + (1 - EMA_ALPHA) * ema_file_time
            eta_seconds = ema_file_time * (len(all_files) - i)

            # Human-readable ETA
            hrs = int(eta_seconds // 3600)
            mins = int((eta_seconds % 3600) // 60)
            secs = int(eta_seconds % 60)

            # Progress logic: max one progress line every 3 seconds.
            # Always print on the last file.
            elapsed_since_last = time() - last_progress_time
            files_since_last = i - last_progress_count
            if i == len(all_files) or elapsed_since_last >= 3:
                verb = "hashed" if DO_HASH else "processed"
                print(f"[PROGRESS] {i}/{len(all_files)} files {verb} "
                      f"({elapsed:.1f}s elapsed, ETA ~{hrs}h {mins}m {secs}s)",
                      file=sys.stderr)
                last_progress_time = time()
                last_progress_count = i

    except KeyboardInterrupt:
        print("[INFO] Aborted by user. Exiting...", file=sys.stderr)
        sys.exit(1)

# ------------------ Build hierarchical tree ------------------
def build_tree(dir_path):
    children = []
    total_size = 0
    if TRACE_ENABLED:
        print(f"[DIR] Processing directory {dir_path}", file=sys.stderr)

    dir_name = os.path.basename(dir_path)
    dir_node = {
        "name": dir_name,
        "type": "dir",
        "children": children,
        "total_size": total_size,
    }
    if any(ord(ch) > 127 for ch in dir_name):
        dir_node["name-unicode"] = dir_name

    # Subdirectories
    subdirs = sorted([d for d in os.listdir(dir_path) 
                      if os.path.isdir(os.path.join(dir_path, d)) and not ignored(os.path.join(dir_path, d))])
    for d in subdirs:
        subtree = build_tree(os.path.join(dir_path, d))
        total_size += subtree["total_size"]
        children.append(subtree)

    # Files
    files = sorted([f for f in os.listdir(dir_path) 
                    if os.path.isfile(os.path.join(dir_path, f)) and not ignored(os.path.join(dir_path, f))])
    for f in files:
        full_path = os.path.join(dir_path, f)
        if DO_HASH:
            info = file_data.get(
                full_path, {"size-bytes": 0, "update-time": "", "blake3-hash": None}
            )
        else:
            info = file_data.get(full_path, {"size-bytes": 0, "update-time": ""})
        node = {
            "name": f,
            "type": "file",
            "size-bytes": info["size-bytes"],
            "update-time": info["update-time"],
        }
        if any(ord(ch) > 127 for ch in f):
            node["name-unicode"] = f
        if DO_HASH:
            node["blake3-hash"] = info.get("blake3-hash")
        children.append(node)
        total_size += info["size-bytes"]

    dir_node["total_size"] = total_size
    dir_node["children"] = children
    return dir_node

# ------------------ Output JSON ------------------
tree = build_tree(ROOT)
output = {"root": ROOT, "tree": tree}
print(json.dumps(output, indent=2))
