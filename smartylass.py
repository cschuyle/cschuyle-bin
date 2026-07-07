#!/usr/bin/env python3

import os
import re
import json
import subprocess
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

# --------- CONFIG ---------
MAX_SAMPLE_FILES = 200
MAX_WORKERS = 8

CODE_EXT = {".py",".js",".ts",".java",".c",".cpp",".h",".go",".rs",".cs"}
AUDIO_EXT = {".mp3",".flac",".m4a",".aac",".wav"}
VIDEO_EXT = {".mp4",".mkv",".avi",".mov"}
BOOK_EXT = {".pdf",".epub",".mobi"}

# --------- UTILS ---------

def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode()
    except Exception:
        return ""


def human_time(seconds):
    try:
        seconds = int(float(seconds))
    except:
        return "?"
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"

# --------- SCAN ---------

def scan(path):
    files = []
    dirs = []

    for root, dnames, fnames in os.walk(path):
        dirs.append(root)
        for f in fnames:
            files.append(os.path.join(root, f))
            if len(files) > MAX_SAMPLE_FILES:
                return files, dirs
    return files, dirs

# --------- DETECTION ---------

def classify(files):
    counts = Counter()

    for f in files:
        ext = os.path.splitext(f)[1].lower()
        if ext in CODE_EXT:
            counts["code"] += 1
        elif ext in AUDIO_EXT:
            counts["audio"] += 1
        elif ext in VIDEO_EXT:
            counts["video"] += 1
        elif ext in BOOK_EXT:
            counts["books"] += 1

    if not counts:
        return "unknown"

    total = sum(counts.values())
    for k, v in counts.items():
        if v / total > 0.6:
            if k == "video":
                if is_series(files):
                    return "series"
                return "video"
            return k

    return counts.most_common(1)[0][0]


def is_series(files):
    pattern = re.compile(r"S\d{2}E\d{2}", re.I)
    return any(pattern.search(os.path.basename(f)) for f in files)

# --------- PARALLEL HELPERS ---------

def parallel_map(func, items, limit=20):
    results = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(func, item): item for item in items[:limit]}
        for f in as_completed(futures):
            try:
                results.append(f.result())
            except Exception:
                pass
    return results

# --------- SUMMARIZERS ---------

def probe_duration(f):
    out = run([
        "ffprobe","-v","error",
        "-show_entries","format=duration",
        "-of","default=noprint_wrappers=1:nokey=1",
        f
    ])
    try:
        return float(out.strip())
    except:
        return 0.0


def has_subs(f):
    streams = run([
        "ffprobe","-v","error",
        "-select_streams","s",
        "-show_entries","stream=index",
        "-of","csv=p=0",
        f
    ])
    return bool(streams.strip())


def pdf_pages(f):
    out = run(["pdfinfo", f])
    m = re.search(r"Pages:\s+(\d+)", out)
    return int(m.group(1)) if m else 0


def summarize_code(path):
    out = run(["tokei", path, "--output", "json"])
    if not out:
        return "Code dir (install tokei)"

    data = json.loads(out)
    total_lines = sum(lang.get("code", 0) for lang in data.values())
    langs = ", ".join(data.keys())

    return f"Type: Code ({langs})\nLOC: {total_lines}"


def summarize_audio(files):
    durations = parallel_map(probe_duration, files)
    total = sum(durations)

    return f"Type: Audio\nTracks(sample): {len(durations)}\nTotal length (est): {human_time(total)}"


def summarize_video(files):
    durations = parallel_map(probe_duration, files)
    subs_flags = parallel_map(has_subs, files)

    total = sum(durations)
    subs = sum(1 for s in subs_flags if s)
    coverage = subs / max(1, len(subs_flags))

    return f"Type: Video\nFiles(sample): {len(durations)}\nRuntime(est): {human_time(total)}\nSub coverage: {coverage:.0%}"


def summarize_series(files):
    seasons = defaultdict(int)
    pattern = re.compile(r"S(\d{2})E(\d{2})", re.I)

    for f in files:
        m = pattern.search(os.path.basename(f))
        if m:
            seasons[m.group(1)] += 1

    lines = ["Type: TV Series"]
    for s in sorted(seasons):
        lines.append(f"  S{s}: {seasons[s]} eps")

    return "\n".join(lines)


def summarize_books(files):
    pages_list = parallel_map(pdf_pages, [f for f in files if f.lower().endswith(".pdf")])
    total_pages = sum(pages_list)

    return f"Type: Books\nFiles(sample): {len(pages_list)}\nPages(est): {total_pages}"

# --------- MAIN ---------

def main(path):
    files, dirs = scan(path)
    kind = classify(files)

    print(f"\n{os.path.abspath(path)}")
    print("-"*40)

    if kind == "code":
        print(summarize_code(path))
    elif kind == "audio":
        print(summarize_audio(files))
    elif kind == "video":
        print(summarize_video(files))
    elif kind == "series":
        print(summarize_series(files))
    elif kind == "books":
        print(summarize_books(files))
    else:
        print("Type: Unknown")
        print(f"Files: {len(files)}")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: smartylass.py [PATH]")
        print("Classify PATH (default: .) as code, audio, video, TV series, or books and print a short summary.")
        sys.exit(0)
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
