#!/usr/bin/env python3
import os
import sys
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import time

try:
    import blake3
except ImportError:
    print("Please install blake3: python3 -m pip install --user blake3", file=sys.stderr)
    sys.exit(1)

try:
    import pathspec
except ImportError:
    print("Please install pathspec: python3 -m pip install --user pathspec", file=sys.stderr)
    sys.exit(1)

# Config
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "."
IGNORE_FILE = sys.argv[2] if len(sys.argv) > 2 else ".myignore"
JOBS = int(os.environ.get("JOBS", os.cpu_count()))

# Load ignore file
if os.path.exists(IGNORE_FILE):
    with open(IGNORE_FILE, "r") as f:
        spec = pathspec.PathSpec.from_lines("gitwildmatch", f)
    print(f"[INFO] Loaded ignore file: {IGNORE_FILE}", file=sys.stderr)
else:
    spec = pathspec.PathSpec([])

def ignored(path):
    rel = os.path.relpath(path, ROOT)
    return spec.match_file(rel)

# Walk tree and collect files
all_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if not ignored(os.path.join(dirpath, d))]
    for f in filenames:
        full_path = os.path.join(dirpath, f)
        if ignored(full_path):
            continue
        all_files.append(full_path)

print(f"[INFO] Found {len(all_files)} files to process under {ROOT}", file=sys.stderr)

# Function to hash a single file using BLAKE3
def file_info(path):
    try:
        size = os.path.getsize(path)
        mtime = os.path.getmtime(path)
        h = blake3.blake3()
        with open(path, "rb") as fd:
            while chunk := fd.read(16*1024*1024):  # 16 MB chunks
                h.update(chunk)
        print(f"[HASHED] {path}", file=sys.stderr)
        return path, size, mtime, h.hexdigest()
    except Exception as e:
        print(f"[ERROR] {path}: {e}", file=sys.stderr)
        return path, 0, 0, None

# Parallel hashing
file_data = {}
start_time = time()
with ThreadPoolExecutor(max_workers=JOBS) as executor:
    futures = {executor.submit(file_info, path): path for path in all_files}
    for i, fut in enumerate(as_completed(futures), 1):
        path, size, mtime, blake3_hash = fut.result()
        file_data[path] = {"size": size, "mtime": mtime, "blake3-hash": blake3_hash}
        if i % 50 == 0 or i == len(all_files):
            print(f"[PROGRESS] {i}/{len(all_files)} files hashed ({time()-start_time:.1f}s elapsed)", file=sys.stderr)

# Recursive tree builder
def build_tree(dir_path):
    children = []
    total_size = 0
    print(f"[DIR] Processing directory {dir_path}", file=sys.stderr)

    subdirs = sorted([d for d in os.listdir(dir_path) 
                      if os.path.isdir(os.path.join(dir_path, d)) and not ignored(os.path.join(dir_path, d))])
    for d in subdirs:
        subtree = build_tree(os.path.join(dir_path, d))
        total_size += subtree["total_size"]
        children.append(subtree)

    files = sorted([f for f in os.listdir(dir_path) 
                    if os.path.isfile(os.path.join(dir_path, f)) and not ignored(os.path.join(dir_path, f))])
    for f in files:
        full_path = os.path.join(dir_path, f)
        info = file_data.get(full_path, {"size": 0, "mtime": 0, "blake3-hash": None})
        children.append({
            "name": f,
            "type": "file",
            "size": info["size"],
            "mtime": info["mtime"],
            "blake3-hash": info["blake3-hash"]
        })
        total_size += info["size"]

    return {
        "name": os.path.basename(dir_path),
        "type": "dir",
        "children": children,
        "total_size": total_size
    }

# Build tree and output JSON
tree = build_tree(ROOT)
output = {"root": ROOT, "tree": tree}
print(json.dumps(output, indent=2))
