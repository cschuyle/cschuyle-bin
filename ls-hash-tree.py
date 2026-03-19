#!/usr/bin/env python3
import os
import sys
import json
import hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
from time import time

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "."
JOBS = int(os.environ.get("JOBS", os.cpu_count()))

# Step 1: Walk tree and collect all file paths
all_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    for f in filenames:
        full_path = os.path.join(dirpath, f)
        all_files.append(full_path)

print(f"[INFO] Found {len(all_files)} files under {ROOT}", file=sys.stderr)

# Step 2: Function to compute SHA256 for a file with logging to stderr
def file_info(path):
    try:
        size = os.path.getsize(path)
        mtime = os.path.getmtime(path)
        h = hashlib.sha256()
        with open(path, "rb") as fd:
            while chunk := fd.read(1024*1024):
                h.update(chunk)
        print(f"[HASHED] {path}", file=sys.stderr)
        return path, size, mtime, h.hexdigest()
    except Exception as e:
        print(f"[ERROR] {path}: {e}", file=sys.stderr)
        return path, 0, 0, None

# Step 3: Compute hashes in parallel
file_data = {}
start_time = time()
with ThreadPoolExecutor(max_workers=JOBS) as executor:
    futures = {executor.submit(file_info, path): path for path in all_files}
    for i, fut in enumerate(as_completed(futures), 1):
        path, size, mtime, sha256 = fut.result()
        file_data[path] = {"size": size, "mtime": mtime, "sha256": sha256}
        if i % 50 == 0 or i == len(all_files):
            print(f"[PROGRESS] {i}/{len(all_files)} files hashed ({time()-start_time:.1f}s elapsed)", file=sys.stderr)

# Step 4: Recursive function to build tree
def build_tree(dir_path):
    children = []
    total_size = 0

    print(f"[DIR] Processing directory {dir_path}", file=sys.stderr)

    # Directories first, sorted
    subdirs = sorted(
        [d for d in os.listdir(dir_path) if os.path.isdir(os.path.join(dir_path, d))]
    )
    for d in subdirs:
        subtree = build_tree(os.path.join(dir_path, d))
        total_size += subtree["total_size"]
        children.append(subtree)

    # Files next, sorted
    files = sorted(
        [f for f in os.listdir(dir_path) if os.path.isfile(os.path.join(dir_path, f))]
    )
    for f in files:
        full_path = os.path.join(dir_path, f)
        info = file_data.get(full_path, {"size": 0, "mtime": 0, "sha256": None})
        children.append({
            "name": f,
            "type": "file",
            "size": info["size"],
            "mtime": info["mtime"],
            "sha256": info["sha256"]
        })
        total_size += info["size"]

    return {
        "name": os.path.basename(dir_path),
        "type": "dir",
        "children": children,
        "total_size": total_size
    }

# Step 5: Build tree and output JSON to stdout
tree = build_tree(ROOT)
output = {"root": ROOT, "tree": tree}
print(json.dumps(output, indent=2))
