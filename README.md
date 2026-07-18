# cschuyle-bin

Personal scripts and utilities on `$PATH` (via `Yew/cschuyle-bin` in shell config). Each script documents itself: run `NAME --help` (or `NAME -h`) for the full usage text printed by that script.

## Scripts

### autosource.sh

Watch files or directories and enqueue changed paths for the interactive shell to `source`. Run with `source autosource.sh --shell-hook` and add `_autosource_drain` to `PROMPT_COMMAND`.

### brief-whois

Look up domains via RDAP (`rdap.org`). Default output is one tab-separated line per domain; `-v` prints a multi-line report. With no arguments, reads domains from stdin.

### case-insensitive-dups.sh

Report top-level files in a directory whose names collide when compared case-insensitively. Exits 1 if any duplicates are found.

### cut-first

Read lines from stdin; print each line with the first whitespace-separated field removed.

### ddf

Show disk availability for each directory in `CS_DF_DATA_DIRS` (from `config.sh`).

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

### rename-fat-filename-by-urlencoding

Rename a file by percent-encoding characters unsafe on FAT/exFAT (quotes, colons, etc.).

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

---

The video toolchain (`vids-handle`, `better-handbrake.sh`, `dir-fission`, `dg-whatis`, `vids-rename.pl`, `vids-mkdir.pl`, `vids-lint`, `video-data.py`, `smartylass.py`, and the deprecated `vids`, `datani-stats`, `qb-is-*`) has moved to the sibling `trovester` repository.
