#!/usr/bin/env python3
"""
Video file report: list size, duration, resolution, codec, audio/subtitle languages.
Usage: python3 video-data.py [path ...]
  Each path may be a file or directory. Directories are recursed. Default: current dir.
Output: JSON array of video entries.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

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


def collect_video_paths(paths: list[str]) -> list[str]:
    """Return sorted, deduplicated video paths from files and recursive dirs."""
    seen = set()
    for arg in paths:
        p = Path(arg).resolve()
        if p.is_file():
            if p.suffix.lower() in VIDEO_EXTENSIONS:
                seen.add(str(p))
        elif p.is_dir():
            for fp in find_videos(p):
                seen.add(fp)
    return sorted(seen)


def main():
    paths = sys.argv[1:] if len(sys.argv) > 1 else ["."]

    results = []
    for filepath in collect_video_paths(paths):
        size = get_size(filepath)
        duration = get_duration(filepath)
        resolution = get_resolution(filepath)
        vcodec = get_vcodec(filepath)
        audio_langs_str = get_stream_langs(filepath, "a")
        sub_langs_str = get_stream_langs(filepath, "s")

        results.append({
            "file": filepath,
            "size_kb": round(size / 1024),
            "time_min": round(duration / 60),
            "resolution": resolution,
            "v_codec": vcodec,
            "audio_langs": audio_langs_str.split(",") if audio_langs_str else [],
            "sub_langs": sub_langs_str.split(",") if sub_langs_str else [],
        })

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
