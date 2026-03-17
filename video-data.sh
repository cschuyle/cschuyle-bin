#!/usr/bin/env bash

# Usage: ./video_report.sh /path/to/dir

DIR="${1:-.}"

printf "%-50s | %-10s | %-10s | %-12s | %-10s | %-20s | %-20s\n" \
"FILE" "SIZE" "DURATION" "RESOLUTION" "V_CODEC" "AUDIO_LANGS" "SUB_LANGS"

printf -- "---------------------------------------------------------------------------------------------------------------------------------------\n"

find "$DIR" -type f \( \
    -iname "*.mp4" -o \
    -iname "*.mkv" -o \
    -iname "*.avi" -o \
    -iname "*.mov" -o \
    -iname "*.m4v" -o \
    -iname "*.webm" \
\) | while read -r file; do

    size=$(du -h "$file" | cut -f1)

    duration=$(ffprobe -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file")

    duration=$(printf "%.0f" "$duration" 2>/dev/null)

    if [[ -n "$duration" ]]; then
        duration=$(printf '%02d:%02d:%02d' \
            $((duration/3600)) \
            $((duration%3600/60)) \
            $((duration%60)))
    fi

    resolution=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=s=x:p=0 "$file")

    vcodec=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name \
        -of default=noprint_wrappers=1:nokey=1 "$file")

    audio_langs=$(ffprobe -v error -select_streams a \
        -show_entries stream_tags=language \
        -of csv=p=0 "$file" | sort -u | tr '\n' ',' | sed 's/,$//')

    sub_langs=$(ffprobe -v error -select_streams s \
        -show_entries stream_tags=language \
        -of csv=p=0 "$file" | sort -u | tr '\n' ',' | sed 's/,$//')

    printf "%-50s | %-10s | %-10s | %-12s | %-10s | %-20s | %-20s\n" \
        "$file" "$size" "$duration" "$resolution" "$vcodec" "$audio_langs" "$sub_langs"

done
