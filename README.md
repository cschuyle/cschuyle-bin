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

Move video files (`.mkv`, `.avi`, `.mov`, `.webm`, `.ogm`) from source trees into a destination, preserving directory structure. `.mp4` / `.m4v` are left in place.

### dus

Disk usage for paths: postorder tree with siblings sorted by size. Caches scan results in SQLite (`~/.dus/dus.db`).

### exfat-probs.sh

Scan a tree for paths that may break on exFAT or Windows: reserved names, invalid characters, trailing dots/spaces, long paths, and case collisions.

### gar

Audit machine configuration against manifests in `gar.d/`. Desired state is the platform/shared base plus an additive union of role overlays enabled in `~/.config/gar/roles` (one role id per line; missing file means no roles). Role `my-data-client` adds the dragnon/moocho/My-Data stack: machine-env repos (`dragnon-config`, `datagator`, `moocho`, `moocho-overseer`, `My-Data`), secrets (`DRAGNON_SYNOLOGY_*`), env (`DRAGNON_*`), and login item Proton VPN. Role `personal-machine` adds personal apps (Opera, Waterfox, WhatsApp, ProtonVPN, qBittorrent, Spotify, VLC, HandBrake, Kindle, Karakeep, Ground News, Amphetamine, Mondly Languages, Telegram) and the `HandBrakeCLI` command. Omit a role to exclude its items. Mac: Homebrew, secrets, env, Java, apps, browser extensions, commands, machine environment repos, settings. Synology: commands, machine environment repos, git config. WSL: env, `/mnt/z` mount, commands, machine environment repos, git config. `gar apps` lists tracked GUI apps; `gar info` (no name) shows the platform info page from `gar.d/<platform>.info` (empty by default); `gar info NAME` shows install hints and plain-text general info from `gar.d/*.info.d/`. In an interactive terminal, offers to pull `main` for machine env repos with no uncommitted changes that are behind `origin/main`, and offers to fix settings warnings it can apply automatically (`defaults` values, Cursor/VS Code `settings.json` keys, and the menu-bar volume toggle).

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

Move each path listed in a file (one per line) into a target directory. Paths may be files or directories. Lines may be quoted (`'…'`, `"…"`), backslash-escaped, or surrounded by whitespace.

### copy-file-list

Copy each path listed in a file (one per line) into a target directory. Paths may be files or directories. Lines may be quoted (`'…'`, `"…"`), backslash-escaped, or surrounded by whitespace. Shows a progress meter on stderr (`[####------] 2/5 (40%) path`). `-v` / `--verbose` echoes each `cp` command.

### qb-is-done

For finished qBittorrent folders, print `mkdir`/`mv` commands to sort into `_MP4` or `_DONE` by video type.

### qb-is-mixed

For finished folders containing both MP4/M4V and MKV/AVI/OGM, print shell commands to move them into `_MIXED`.

### qb-is-not-done

List torrent download directories that still have in-progress `.!qB` partial files.

### qb-is-not-mp4

List finished torrent directories that contain only non-MP4 video (MKV/AVI/OGM), with no active partials or MP4/M4V files.

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

`status` checks whether a torrent video folder is downloaded and ready (no partials; MP4 present; no unsplit MKV/AVI/OGM); `split` moves the folder and parks non-MP4 originals under `_Originals`.

### vids-lint

Scan video directories for "dirty" states: `.srt` subtitles not named `<video-stem>.<suffix>.srt` (with a language segment) alongside their video, and directories that directly contain more than one video file. Two subtitle violations are recognized: `orphan-subtitle` (name matches no video in the folder) and `non-identifiable-language-subtitle-file` (tied to a video but carrying no language segment, e.g. `Movie.srt` or `Movie.forced.srt` next to `Movie.mp4`). Only the part of the name past the video stem is inspected for a language, so a title word like `The.English.Patient.srt` is not mistaken for a language. `non-identifiable-language-subtitle-file` is a quiet violation, reported only with `-a` / `--all`. It also flags macOS AppleDouble sidecar files (`._<name>`) as `appledouble-junk-file` — these are never counted as videos or subtitles, and their presence is another quiet violation reported only with `-a` / `--all` (and `-i` offers to delete them). Each finding carries its violation code, shown in brackets in plain output and as a `code` field with `--json`. With no path argument, lints the first eligible item in the current directory (first non-hidden entry, sorted by name, whose tree contains a video or subtitle file). `--json` emits one object per dirty directory. `-i` / `--interactive` offers to fix each fixable subtitle by moving it into its main video's folder and prepending the video's basename to the original subtitle name (`Subs/2_English.srt` → `Movie.2_English.srt`); subtitles are skipped when there is no single main video, the target already exists, or the name is just the video stem with no suffix. `-i` also offers to delete AppleDouble junk files, with one prompt per directory covering all its changes. With no path argument, `-i` processes every non-hidden entry in the current directory (as if the argument were `*`), offering fixes and advancing to the next item even after you fix the current one. Exits 1 if anything is flagged (after fixes, in `-i` mode).

### vids-mkdir.pl

Read video filenames from stdin; print `mkdir`/`mv` commands to group files by year.

### vids-rename.pl

Read video filenames from stdin; print `mv` commands to normalize names (strip resolution, tidy years).
