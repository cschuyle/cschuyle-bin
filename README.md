# cschuyle-bin

Personal scripts and utilities on `$PATH` (via `Yew/cschuyle-bin` in shell config). Each script documents itself: run `NAME --help` (or `NAME -h`) for the full usage text printed by that script.

## Scripts

### autosource.sh

Watch files or directories and enqueue changed paths for the interactive shell to `source`. Run with `source autosource.sh --shell-hook` and add `_autosource_drain` to `PROMPT_COMMAND`.

### better-handbrake.sh

Batch-encode video with HandBrakeCLI. Accepts a file or directory, optional preset and filename pattern, and can list GUI presets.

### brief-whois

Look up domains via RDAP (`rdap.org`). Default output is one tab-separated line per domain; `-v` prints a multi-line report. With no arguments, reads domains from stdin.

### case-insensitive-dups.sh

Report top-level files in a directory whose names collide when compared case-insensitively. Exits 1 if any duplicates are found.

### cut-first

Read lines from stdin; print each line with the first whitespace-separated field removed.

### datani-stats

List torrent/HandBrake workflow files by category (downloading, downloaded, to-be-transcoded, transcoding), sorted by size. Roots default to Synology Download and HandBrake paths; override with flags or `DATANI_*` env vars.

### ddf

Show disk availability for each directory in `CS_DF_DATA_DIRS` (from `config.sh`).

### dg-whatis

Classify paths as movie, series, album, or ebook using filesystem heuristics. Supports JSON output, ffprobe metadata, and cross-type video equivalence checks.

### dir-fission

Move video files (`.mkv`, `.avi`, `.mov`, `.webm`) from source trees into a destination, preserving directory structure. `.mp4` / `.m4v` are left in place.

### dus

Disk usage for paths: postorder tree with siblings sorted by size. Caches scan results in SQLite (`~/.dus/dus.db`).

### exfat-probs.sh

Scan a tree for paths that may break on exFAT or Windows: reserved names, invalid characters, trailing dots/spaces, long paths, and case collisions.

### gar

Audit Mac machine configuration against manifests in `gar.d/` (Homebrew, secrets, env, Java, apps, browser extensions, commands, machine environment repos, settings). `gar apps` lists tracked GUI apps; `gar info NAME` shows how to install an item.

### git-pull-repos.sh

In the current directory, run `git pull -r` in every immediate subdirectory that is a git repo.

### just-the-meat

Filter directory listings: drop lines containing `@`, named `temp`, or named `_`.

### ls-hash.sh

Walk a directory and emit JSON listing every file with size, mtime, and sha256.

### ls-hash-tree.sh

Walk a directory and emit a JSON tree with per-node `total_size` and sha256 per file.

### ls-hash-tree.py

Walk a directory tree and emit JSON (stats by default; `--hash` adds BLAKE3). Honors a gitwildmatch ignore file (default `.myignore`).

### ls-shared-folders.sh

List Synology share names and their paths (`synoshare`). Optional argument filters to one share name.

### mount-z

Mount the Synology `cschuyle` share at `/mnt/z` on WSL (requires `DRAGNON_SYNOLOGY_IP`).

### move-file-list

Move each path listed in a file (one per line) into a target directory.

### qb-is-done

For finished qBittorrent folders, print `mkdir`/`mv` commands to sort into `_MP4` or `_DONE` by video type.

### qb-is-mixed

For finished folders containing both MP4/M4V and MKV/AVI, print shell commands to move them into `_MIXED`.

### qb-is-not-done

List torrent download directories that still have in-progress `.!qB` partial files.

### qb-is-not-mp4

List finished torrent directories that contain only non-MP4 video (MKV/AVI), with no active partials or MP4/M4V files.

### rename-fat-filename-by-urlencoding

Rename a file by percent-encoding characters unsafe on FAT/exFAT (quotes, colons, etc.).

### smartylass.py

Classify a directory as code, audio, video, TV series, or books and print a short summary.

### space

Show disk usage for files or directories, sorted by size. `-h` uses human-readable units; `-a` includes dot files.

### split-lines

Split input into two files: a small fraction (~1/N of lines) and the rest. Default N is 2.

### ssh-synology

SSH to the Synology NAS (port 4546) using `DRAGNON_SYNOLOGY_IP`. Switches iTerm to the Caution profile for the session.

### tarsync

Synchronize files with `tar` over a pipe; supports local or remote destinations, dry-run, compression, and optional overwrite-newer.

### top-5.sh

List the four largest files under a directory with human-readable sizes.

### unshuffle-lines

Split lines into odd/even buckets, or into N parts (`-nth` / `-n`). Companion to recombine shuffled splits.

### video-data.py

Report video files as JSON: size, duration, resolution, codec, and audio/subtitle languages (via ffprobe).

### vids

`status` checks whether a torrent video folder is downloaded and ready; `split` moves the folder and parks non-MP4 originals under `_Originals`.

### vids-mkdir.pl

Read video filenames from stdin; print `mkdir`/`mv` commands to group files by year.

### vids-rename.pl

Read video filenames from stdin; print `mv` commands to normalize names (strip resolution, tidy years).
