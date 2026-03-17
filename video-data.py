#!/usr/bin/env python3
"""
Video file report: list size, duration, resolution, codec, audio/subtitle languages.
Usage: python3 video-data.py [-p|--pretty] [path ...]
  -p, --pretty  pretty-print JSON (default: compact)
  Each path may be a file or directory. Directories are recursed. Default: current dir.
Output: JSON array of video entries.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List

REQUIRED_COMMANDS = ["ffprobe"]  # ffprobe is from the ffmpeg package

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".m4v", ".webm"}


def get_size(path: str) -> int:
    """Return file size in bytes."""
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def get_duration(path: str) -> float:
    """Return duration in seconds."""
    try:
        out = subprocess.run(
            [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        raw = out.stdout.strip()
        if not raw:
            return 0.0
        return float(raw)
    except (subprocess.CalledProcessError, ValueError, FileNotFoundError):
        return 0.0


def get_resolution(path: str) -> str:
    """Return width x height or empty string."""
    try:
        out = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-of", "csv=s=x:p=0",
                path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip() or ""
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def get_vcodec(path: str) -> str:
    """Return video codec name or empty string."""
    try:
        out = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip() or ""
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def get_stream_langs(path: str, stream_type: str) -> str:
    """Return comma-separated language tags for stream type 'a' or 's'."""
    try:
        out = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", stream_type,
                "-show_entries", "stream_tags=language",
                "-of", "csv=p=0",
                path,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        lines = [line.strip() for line in out.stdout.strip().splitlines() if line.strip()]
        langs = sorted(set(lines))
        return ",".join(langs)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def find_videos(dirpath: Path):
    """Yield paths to video files under dirpath."""
    for root, _, names in os.walk(dirpath):
        for name in names:
            if Path(name).suffix.lower() in VIDEO_EXTENSIONS:
                yield os.path.join(root, name)


def collect_video_paths(paths: List[str], stream=None) -> List[str]:
    """Return sorted, deduplicated video paths from files and recursive dirs.
    If stream is provided (e.g. stderr), print 'Scanning <dir> ...' then ' Scanned <dir>. N files.\\n' for each directory.
    """
    seen = set()
    for arg in paths:
        p = Path(arg).resolve()
        if p.is_file():
            if p.suffix.lower() in VIDEO_EXTENSIONS:
                seen.add(str(p))
        elif p.is_dir():
            label = p.name if p.name else str(p)
            if stream is not None:
                stream.write("Scanning {} ...".format(label))
                stream.flush()
            files_in_dir = []
            for fp in find_videos(p):
                files_in_dir.append(fp)
                seen.add(fp)
            if stream is not None:
                stream.write(" Scanned {}. {} files.\n".format(label, "{:,}".format(len(files_in_dir))))
                stream.flush()
    return sorted(seen)


def _progress_bar(current: int, total: int, width: int = 24) -> str:
    """Return a single line progress bar string (e.g. '[=========>     ] 66% (2/3)')."""
    if total <= 0:
        filled = width
        pct = 100
    else:
        filled = int(width * current / total)
        pct = int(100 * current / total)
    bar = "=" * filled + ">" * (1 if filled < width and current < total else 0)
    bar = bar.ljust(width)
    return "[{}] {}% ({}/{})".format(bar, pct, current, total)


def _format_eta(eta_seconds: float) -> str:
    """Format seconds as 'ETA 0:00' or 'ETA 1:23:45'."""
    if eta_seconds < 0 or not (eta_seconds < 86400):  # cap at 24h for display
        return ""
    s = int(round(eta_seconds))
    if s < 60:
        return "ETA 0:{:02d}".format(s)
    m, s = divmod(s, 60)
    if m < 60:
        return "ETA {}:{:02d}".format(m, s)
    h, m = divmod(m, 60)
    return "ETA {}:{:02d}:{:02d}".format(h, m, s)


def _update_progress(stderr, current: int, total: int, filename: str, eta_str: str = "") -> None:
    """Overwrite the single-line progress display on stderr (no cursor-up to avoid scroll)."""
    line = _progress_bar(current, total)
    if eta_str:
        line += "  " + eta_str
    line += "  " + filename
    stderr.write("\r" + line + "\033[K")
    stderr.flush()


def main():
    parser = argparse.ArgumentParser(description="Video file report (JSON)")
    parser.add_argument("-p", "--pretty", action="store_true", help="pretty-print JSON")
    parser.add_argument("paths", nargs="*", default=["."], help="files or directories")
    args = parser.parse_args()

    for cmd in REQUIRED_COMMANDS:
        if not shutil.which(cmd):
            sys.stderr.write("error: required command '{}' not found in PATH\n".format(cmd))
            sys.stderr.flush()
            if cmd == "ffprobe":
                sys.stderr.write("  (install ffmpeg to get ffprobe)\n")
                sys.stderr.flush()
            sys.exit(1)

    indent = 2 if args.pretty else None
    filepaths = collect_video_paths(args.paths, stream=sys.stderr)
    total = len(filepaths)
    # Fancy single-line bar only when stdout is redirected (e.g. to file) and stderr is a TTY
    show_fancy_progress = sys.stderr.isatty() and not sys.stdout.isatty()
    # Simple "PROGRESS: N%" when stdout is a TTY (interactive, no redirect)
    show_simple_progress = sys.stdout.isatty()

    if show_fancy_progress:
        sys.stderr.write("\r" + _progress_bar(0, total) + "  " + "\033[K")
        sys.stderr.flush()

    last_pct = -1
    start_time = time.time()
    if args.pretty:
        print("[")
    else:
        print("[", end="")
    for i, filepath in enumerate(filepaths):
        size = get_size(filepath)
        duration = get_duration(filepath)
        resolution = get_resolution(filepath)
        vcodec = get_vcodec(filepath)
        audio_langs_str = get_stream_langs(filepath, "a")
        sub_langs_str = get_stream_langs(filepath, "s")

        record = {
            "file": filepath,
            "size_kb": round(size / 1024),
            "time_min": round(duration / 60),
            "resolution": resolution,
            "v_codec": vcodec,
            "audio_langs": audio_langs_str.split(",") if audio_langs_str else [],
            "sub_langs": sub_langs_str.split(",") if sub_langs_str else [],
        }
        chunk = json.dumps(record, indent=indent)
        if args.pretty:
            chunk = "  " + "\n  ".join(chunk.split("\n"))
            if i > 0:
                print(",")
            print(chunk, end="")
        else:
            if i > 0:
                print(",", end="")
            print(chunk, end="")
        sys.stdout.flush()

        current = i + 1
        elapsed = time.time() - start_time
        eta_sec = (total - current) * (elapsed / current) if current > 0 else 0
        eta_str = _format_eta(eta_sec)

        if show_fancy_progress:
            _update_progress(sys.stderr, current, total, os.path.basename(filepath), eta_str)
        elif show_simple_progress:
            pct = 100 if total == 0 else int(100 * current / total)
            if total < 100 or pct > last_pct:
                msg = "\nPROGRESS: {}% ({}/{}) ...".format(pct, current, total)
                if eta_str:
                    msg += " " + eta_str
                sys.stderr.write(msg + "\n")
                sys.stderr.flush()
                last_pct = pct

    if show_fancy_progress:
        sys.stderr.write("\n")
        sys.stderr.flush()
    if args.pretty:
        print("\n]")
    else:
        print("]")


if __name__ == "__main__":
    main()
