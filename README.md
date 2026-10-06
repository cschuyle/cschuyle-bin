# cschuyle-bin

Personal scripts and utilities on `$PATH` (via `Yew/cschuyle-bin` in shell config). Each script documents itself: run `NAME --help` (or `NAME -h`) for the full usage text printed by that script.

## Scripts

### autosource.sh

Watch files or directories and enqueue changed paths for the interactive shell to `source`. Run with `source autosource.sh --shell-hook` and add `_autosource_drain` to `PROMPT_COMMAND`.

### brief-whois

Look up domains via RDAP (`rdap.org`). Default output is one tab-separated line per domain; `-v` prints a multi-line report. With no arguments, reads domains from stdin.

### case-insensitive-dups.sh

Report top-level files in a directory whose names collide when compared case-insensitively. Exits 1 if any duplicates are found.

### config-get

Resolve a single string config value for a command-line script (usable from bash, Python, or Perl by shelling out). Pass the caller's path with `-s`/`--script` (e.g. `"${BASH_SOURCE[0]}"`, `$0`, or `__file__`); `<script base>` is that filename with its extension stripped. Sources are tried in order, first match wins: (1) env var `<SCRIPT_BASE>_<KEY>` (uppercased, non-alphanumerics become `_`); (2) `<script base>.{yaml,yml,json}` in the script's dir; (3) the same in `~/.config/` (honors `XDG_CONFIG_HOME`); (4) `config.{yaml,yml,json}` in the script's dir, under the top-level `<script base>` object; (5) the same in `~/.config/`. Within one file source, `yaml` then `yml` then `json` is tried. YAML uses PyYAML when installed, else a built-in parser covering nested mappings of scalar values (no dependency required). Hyphens and underscores are interchangeable in the script base and the key (e.g. `data-dirs` and `data_dirs` resolve the same, in env vars and file lookups alike). Prints the value to stdout; exits 1 if the key is unresolved and no `--default` is given. `--name`/`--dir` override the derived base/dir; `--source` prints the matched source to stderr.

Example: `preset="$(config-get -s "${BASH_SOURCE[0]}" --default "Fast 1080p30" preset)"`

### cut-first

Read lines from stdin; print each line with the first whitespace-separated field removed.

### ddf

Show disk availability for each configured data directory. The space-separated directory list resolves via `config-get` (key `data_dirs`): env `DDF_DATA_DIRS`, then `ddf.{yaml,json}` / `config.{yaml,json}` in the script dir or `~/.config`. Without `config-get` on `PATH`, `DDF_DATA_DIRS` is used directly.

With no data dirs configured, `ddf` reports the machine's physical local volume(s) instead of erroring: on macOS, `/` and any `/Volumes/*` disks; on Linux/WSL/Synology, local filesystems excluding tmpfs/overlay/etc.

### dus

Disk usage for paths: postorder tree with siblings sorted by size. Caches scan results in SQLite (`~/.dus/dus.db`).

### exfat-probs.sh

Scan a tree for paths that may break on exFAT or Windows: reserved names, invalid characters, trailing dots/spaces, long paths, and case collisions.

### gar

Audit machine configuration against manifests in `gar.d/`. Desired state is the platform/shared base plus an additive union of role overlays enabled in `~/.config/gar/roles` (one role id per line; missing file means no roles). Role `dev-tools` adds developer tooling: apps Docker and Claude, the `aws`/`gh`/`claude`/`lintree`/`pdftotext`/`ffmpeg` commands, and Homebrew `awscli`, `claude-code`, `poppler`, and `ffmpeg-full`; it also forbids plain Homebrew `ffmpeg`, which would leave the keg-only `ffmpeg-full` unlinked. Role `my-data-client` adds the dragnon/moocho/My-Data stack: machine-env repos (`dragnon-config`, `datagator`, `moocho`, `moocho-overseer`, `My-Data`, `trovester-bin`), secrets (`DRAGNON_SYNOLOGY_*`), env (`DRAGNON_*`), login item Proton VPN, app SynologyAssistant, and Homebrew `ffmpeg-full`. Role `personal-machine` adds personal apps (Opera, Waterfox, WhatsApp, ProtonVPN, qBittorrent, Spotify, VLC, HandBrake, Kindle, Karakeep, Ground News, Amphetamine, Mondly Languages, Telegram), the `HandBrakeCLI` command, and Homebrew `handbrake`. Omit a role to exclude its items. Mac: Homebrew, secrets, env, Java, apps, browser extensions, commands, machine environment repos, settings. Synology: commands, machine environment repos, git config. WSL: env, `/mnt/z` mount, commands, machine environment repos, git config. `gar apps` lists tracked GUI apps; `gar info` (no name) shows the platform info page from `gar.d/<platform>.info` (empty by default); `gar info NAME` shows install hints and plain-text general info from `gar.d/*.info.d/`. In an interactive terminal, offers to pull `main` for machine env repos with no uncommitted changes that are behind `origin/main`, and offers to fix settings warnings it can apply automatically (`defaults` values, Cursor/VS Code `settings.json` keys, and the menu-bar volume toggle).

### git-better-skip-worktree

Low-level CLI for git's `skip-worktree` bit (files git is told to ignore local edits to). Invokable as `git better-skip-worktree`. `list` shows skip-worktree'd files as SAME/DIFF vs HEAD; `diff <file>` shows a skip-worktree'd file's real diff; `skip <path>...` / `undo [<path>...]` set/clear the bit; `sync` round-trips locally-modified skip-worktree'd files through a stash across a fast-forward so upstream changes come in without losing your edits.

### git-better-worktree

Better views of git worktrees. Aliased `gbw`; invokable as `git better-worktree`. `gbw list` is like `git worktree list` but adds a MAIN / linked column so you can tell the main working tree from the linked ones. (Skip-worktree management, formerly `gbw skip`, now lives in `git-better-skip-worktree` / `git-shutup-this-is-mine`.)

### git-pull-repos.sh

In the current directory, run `git pull -r` in every immediate subdirectory that is a git repo.

### git-shutup-this-is-mine

Manage files you edit freely but never want committed or pushed — while still being able to see what changed to them upstream. Invokable as `git shutup-this-is-mine`. `add` marks a file as yours (via skip-worktree, so git ignores your edits); `list` shows every "mine" file and its mechanism (skip-worktree / local-exclude / other); `diff` shows your local edit; `convert <path>... <dest>` moves file(s) between mechanisms (`skip-worktree` / `assume-unchanged` / `local-gitignore`), auto-detecting the source — converting into local-gitignore untracks the file (`git rm --cached`, contents kept) and adds it to `.git/info/exclude`; `upstream` fetches and shows what changed on the remote for the file, ignoring your local edit; `pull` updates the branch without the usual abort when the remote changed a "mine" file; `undo` stops treating a file as yours. A friendly front-end over `git-better-skip-worktree`.

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

### move-file-list

Move each path listed in a file (one per line) into a target directory. Paths may be files or directories. Lines may be quoted (`'…'`, `"…"`), backslash-escaped, or surrounded by whitespace.

### copy-file-list

Copy each path listed in a file (one per line) into a target directory. Paths may be files or directories. Lines may be quoted (`'…'`, `"…"`), backslash-escaped, or surrounded by whitespace. Shows a progress meter on stderr (`[####------] 2/5 (40%) path`). `-v` / `--verbose` echoes each `cp` command.

### rename-fat-filename-by-urlencoding

Rename a file by percent-encoding characters unsafe on FAT/exFAT (quotes, colons, etc.).

### repo-overlay

A "permanent stash" for a repo's dev-only file overrides (log4j2 noise suppression, local `application.yml`, Tiltfile tweaks, …), kept as commits on a local-only branch (default `local-dev-overlay`) that is never pushed or merged — so the overrides survive the way a forgotten `git stash pop` would not. `apply` writes them into the working tree; `hide`/`unhide` quiet them from `git status` (skip-worktree, or `.git/info/exclude` for added files); `update` saves working-tree edits back onto the overlay branch; `remove`/`clean` revert; `install-hooks` adds pre-commit/pre-push/pre-rebase/post-checkout guards so the overrides never get committed or pushed. The overlay's base is marked by a rebase-proof empty sentinel commit (`init-sentinel`). Which repos it manages — each one's overlay branch and description — comes from `~/.config/repo-overlay/repos.toml`, keyed by repo path. A heavier relative of `git-shutup-this-is-mine` / `git-better-skip-worktree`: a whole committed branch of overrides rather than a per-file bit.

### space

Show disk usage for files or directories, sorted by size. `-h` uses human-readable units; `-a` includes dot files.

### split-lines

Split input into two files: a small fraction (~1/N of lines) and the rest. Default N is 2.

### stressian

Add Russian stress marks to Cyrillic text using the ruaccent model. Reads TEXT from arguments, or from stdin. The first run downloads the ruaccent model (~473 MB) into `~/.stressian` (override with `STRESSIAN_WORKDIR`); later runs use that cache offline.

### tarsync

Synchronize files with `tar` over a pipe; supports local or remote destinations, dry-run, compression, and optional overwrite-newer.

### toggle-switch-key

Toggle the macOS "Move focus to next window" shortcut between Command-` (standard) and Command-<. Pass `show` to print the current binding without changing it.

### top-5.sh

List the four largest files under a directory with human-readable sizes.

### unshuffle-lines

Split lines into odd/even buckets, or into N parts (`-nth` / `-n`). Companion to recombine shuffled splits.

---

The video toolchain (`vids-handle`, `better-handbrake.sh`, `dir-fission`, `dg-whatis`, `vids-rename.pl`, `vids-mkdir.pl`, `vids-lint`, `video-data.py`, `smartylass.py`, and the deprecated `vids`, `datani-stats`, `qb-is-*`) has moved to the sibling `trovester` repository.
