#!/usr/bin/env python3
import os
import sys
import json
import hashlib
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "."
JOBS = int(os.environ.get("JOBS", os.cpu_count()))

# Step 1: Walk tree and collect all file paths
all_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    for f in filenames:
        all_files.append(os.path.join(dirpath, f))

# Step 2: Function to compute SHA256 for a file
def file_info(path):
    size = os.path.getsize(path)
    mtime = os.path.getmtime(path)
    h = hashlib.sha256()
    with open(path, "rb") as fd:
        while chunk := fd.read(1024*1024):
            h.update(chunk)
    return path, size, mtime, h.hexdigest()

# Step 3: Compute hashes in parallel
file_data = {}
with ThreadPoolExecutor(max_workers=JOBS) as executor:
    for path, size, mtime, sha256 in executor.map(file_info, all_files):
        file_data[path] = {"size": size, "mtime": mtime, "sha256": sha256}

# Step 4: Recursive function to build tree
def build_tree(dir_path):
    children = []
    total_size = 0

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
        info = file_data[full_path]
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

# Step 5: Build tree and output JSON
tree = build_tree(ROOT)
output = {"root": ROOT, "tree": tree}

print(json.dumps(output, indent=2))
