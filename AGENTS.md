# Notes for agents and automation

This file is for anyone (human or tool) changing this repository.

## Git commits

Do **not** run `git commit` unless the user explicitly asks you to commit (e.g. they say “commit”, “git commit”, or clearly instruct you to create a commit).

Making edits, running tests, and using read-only git commands (`git status`, `git diff`, `git log`, etc.) is fine. Do not assume a commit is desired when a task is done.

The same policy is mirrored for Cursor in [`.cursor/rules/git-and-commits.mdc`](.cursor/rules/git-and-commits.mdc) (`alwaysApply`).

## gar: machine-env repo checking

`gar` is a machine-config auditor: it compares desired-state manifests in
`gar.d/` against the live machine and reports `OK` / `MISS` / `WARN` /
`EXPECTED MODS` (a `MISS` counts as a problem and makes `gar` exit non-zero;
`WARN` and `EXPECTED MODS` are advisory only). One of its checks audits a set of
git repos ("machine environment repos") — the part most likely to need changes.

**Post-fix recheck.** Each interactive fix that succeeds is counted
(`gar_note_fixed issue|warning`: brew fixes clear a MISS, so they count as
issues; repo pulls/rebases and settings fixes clear a WARN). If any fix was
applied, the end-of-run summary is replaced by `Gar: Fixed N issues.` (or
`N warnings` when no issue was fixed), `After fixes:`, and a re-run of `gar`
with `GAR_RECHECK=1` — no prompts, no platform banner — whose report, summary
and exit status stand as the result. The summary line appends the WARN count:
`All checks passed. 1 warning.` / `4 issue(s). 1 warning.`

**Startup config preflight.** Before the main audit run, `gar` validates its
config paths — the repo's `gar.d/`, and the local `~/.config/gar` dir, its `d/`
overlay dir, and its `roles` file — and hard-fails to stderr with `exit 2` if
any is a broken (dangling) symlink, the wrong file type (e.g. `roles` is a
directory), or unreadable. Plain *absence* of a local path is not an error: it
remains the supported "no local config" state. This is distinct from `exit 1`
(audit found problems). The `gar.d/` dir is also validated at script load (a
missing/unreadable `gar.d/` next to the script exits 2 immediately). The
subcommands `info` / `apps` / `roles` do not run this preflight.

**Timing log.** Every run writes a timing log to
`~/.gar/timings/timings-<timestamp>.txt` (tab-separated: timestamp, `START`/
`END`, operation label, duration on `END` lines) so a slow or hung run can be
diagnosed after the fact instead of reproduced live. It covers each top-level
section (`Homebrew`, `Applications`, `Machine environment repos`, etc.) plus,
within that last section, each repo's parallel prefetch and any pull/rebase or
retry-fetch a repo triggers — fine enough that a hang shows up as the last
`START` line with no matching `END`, naming exactly the stuck repo/operation.
Writing the log is best-effort (a failed `mkdir`/file-create silently disables
it) and never affects `gar`'s own exit status.

**Which repos.** Repos come from a `machine-env-repos` manifest (each line
`name|path[|branch]`, branch defaulting to `main`), plus any `~/Yew/*-setup`
repos discovered automatically. A separate name-based skip manifest can exclude
repos from auditing. A second manifest, `machine-env-catchup` (lines
`name|mainline`), marks repos for *catch-up* mode (see below).

**What it checks per repo.** For each repo it reports whether the checkout is
missing / not a git repo, whether the working tree has genuine uncommitted
changes to tracked files (untracked files are ignored), whether the current
branch matches the configured branch, and — after fetching — how many commits it
is ahead (unpushed) or behind the tracked branch. It also advisory-warns when
the configured branch differs from the repo's remote default branch.

These findings print as an aligned table — status, repo name, `(path)`, and a
short message in four columns, with the status prefix padded to a common width
and the name / `(path)` columns sized to fit the repos in that run (one row per
finding, so a repo with several issues repeats across rows). The buffered rows
are all emitted before any pull offer.

**Offer to pull.** When run in an interactive terminal, `gar` offers to rebase-
pull a repo that is behind its tracked branch — but only if the tree has no
genuine uncommitted changes and the checkout is on the tracked branch (it won't
touch a dirty tree or a feature branch). Pull offers run after the table above
is printed. The pull itself is `git pull -r origin <config_branch>`.

**Catch-up repos.** A repo named in a `machine-env-catchup` manifest is audited
and updated differently: instead of comparing/pulling `config_branch` against
`origin`, `gar` rebases the *current* branch onto a configured **mainline** ref.
Manifest lines are `name|mainline` (pipe-delimited, same matching as the skip
manifest), where `mainline` is a remote-tracking ref like `origin/main`; a bare
`name` defaults the mainline to `origin/<the repo's remote default branch>`.
`gar` measures how far the current branch is behind the mainline
(`HEAD..<mainline>`) and — interactively — offers `git fetch <remote>` +
`git rebase <mainline>` on **whatever branch is checked out** (the tracked-branch
guard is relaxed; a clean tree is still required). This suits repos where you sit
on a feature branch and periodically rebase it onto mainline. Crucially the
rebase does **not** touch the branch's own upstream (`@{u}`), so `git push` still
goes to the feature branch — `gar` never pushes. A catch-up repo whose mainline
can't be resolved (no explicit value and no remote default) is flagged with a
WARN rather than silently skipped. Catch-up findings are advisory (WARN), so they
don't affect the exit code, and the configured-vs-remote-default advisory is
suppressed for them (a catch-up repo doesn't track `config_branch`). The catch-up
helpers take the resolved mainline ref as an argument and make no `@{u}`
assumption, unlike the pull path. `gar info <name>` shows a `Catch-up:` line with
the mainline and reports behind-vs-mainline for these repos. The manifest is
resolved per platform (`<platform>.machine-env-catchup`, else
`shared.machine-env-catchup`) and wired into all three platform runners (mac,
wsl, synology); mac now also honors its `machine-env-skip` manifest, which it
previously ignored.

**Homebrew audit (mac).** `check_mac_homebrew` combines the platform base
`Brewfile` with each active role's `role.<role>.Brewfile` overlay and runs
`brew bundle check` against the union — a formula/cask/tap in the desired state
but not installed is a MISS. A companion check, `check_mac_brew_forbidden`,
audits the inverse: a `brew-forbidden` manifest (`<platform|shared>.brew-forbidden`
plus each active role's `role.<role>.brew-forbidden`, one formula name per line,
`#` comments allowed) lists formulae that must **not** be installed. A forbidden
formula that *is* installed is a MISS with an `uninstall: brew uninstall <name>`
hint. This is how the dev-tools role forbids plain `ffmpeg` (it would keep the
role's keg-only `ffmpeg-full` unlinked). Only the mac runner wires
`brew-forbidden`; both checks run under the `Homebrew` timing section.

Interactively, `gar` offers to fix each missing item with the action that
satisfies it (`gar_brew_item_action`): `brew link --force` for "needs to be
linked", `brew upgrade` for an installed-but-outdated item, else `brew install`
(duplicate `bundle check` lines are collapsed first). If Spotlight is disabled
on `/` and Xcode isn't at `/Applications/Xcode.app` (`gar_brew_blocked_by_spotlight`),
it skips the offers and instead WARNs and prints the brew commands to run:
Homebrew then looks for Xcode via `/usr/bin/mdfind`, which never returns with
Spotlight off, so any install/upgrade hangs (after downloading) until Ctrl-C.

A keg-only formula the role *wants* linked onto PATH (e.g. `ffmpeg-full`, so
`ffmpeg` resolves to it) must be declared `brew "name", link: true` in the
Brewfile — `brew bundle check` treats a bare `brew "name"` for a keg-only
formula as unsatisfied unless it is *unlinked*, which is the opposite of what's
wanted here.

**Shadowed commands.** For each command in a `commands` manifest that is on
PATH, `check_commands` WARNs if more than one distinct copy is on PATH
(`gar_warn_command_shadowed`), naming the one in use and the shadowed ones.
Copies resolving to the same file are collapsed, and macOS system copies
(`/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`) are ignored, since Homebrew routinely
shadows those on purpose. Example: the kubernetes role's Homebrew `kubectl` vs
the one Docker Desktop links into `/usr/local/bin`.

**`gar info <name>`.** `cmd_info` dispatches, in order: `brew`/`homebrew`
(literal) → full Homebrew audit section (forces `gar_show_all`, runs
`check_mac_homebrew`); a machine-env repo → its git status; an app; a
browser extension; an install-hint; a brew hint; general info.

- *Repo status.* If not OK it lists why: a *count* of files with genuine
  uncommitted local changes (never the filenames), non-tracked branch,
  ahead/behind counts, and remote-default mismatch. Any expected (skip-worktree'd)
  mods are then listed one file per line, indented and shell-quoted.
- *Homebrew status.* For a formula/cask (whether matched via the brew hint or an
  install-hint whose value is a `brew install …` command), a `Status:` line led
  by gar's OK/WARN/MISS vocabulary reports `OK - installed (up to date)` /
  `WARN - installed (update available)` / `MISS - not installed`
  (`gar_brew_installed` = `brew list --formula|--cask`; `gar_brew_outdated` =
  non-empty `brew outdated --formula|--cask`). Helper `gar_brew_bin` resolves the
  brew binary (shared with `check_mac_homebrew`).

**skip-worktree & `EXPECTED MODS`.** git's `skip-worktree` flag hides local edits
from `git status` (used for intentional local config tweaks, e.g. lims'
`log4j2.properties` files). git honors the skip bit at every level
(`status` / `diff` / `diff-files` / `diff-index` all ignore those files), so to
detect real skip-worktree'd edits `gar` compares each skip-worktree'd file's
working-tree content (`git hash-object`) against its committed blob
(`git rev-parse HEAD:<file>`). A repo whose *only* tracked modifications are
skip-worktree'd files is reported as `EXPECTED MODS` (advisory, not a problem)
rather than `WARN`, and is still offered a pull (a rebase pull leaves
skip-worktree'd files untouched). A genuine tracked edit takes precedence and
still shows `WARN uncommitted changes`.

`gar` does not manage the skip-worktree flag itself. The standalone
`git-better-skip-worktree` script (usable as `git better-skip-worktree`) is the low-level CLI
for it: `git better-skip-worktree list` prints every skip-worktree'd file prefixed
`SAME`/`DIFF`, `git better-skip-worktree diff <file>` shows the real diff (temporarily
clearing the flag, restoring via a trap), `git better-skip-worktree skip <path>...`
sets skip-worktree on the given files, `git better-skip-worktree undo [<path>...]`
clears the flag (on the named files, or all of them if none are named), and
`git better-skip-worktree sync [--dry-run]` round-trips locally-modified
skip-worktree'd files through a stash across a fast-forward. (This machinery
used to live in `git-better-worktree` as its `gbw skip` subcommand; `gbw` now
only has its `list` subcommand, which annotates `git worktree list` with a
MAIN/linked column — unrelated to skip-worktree.)

`git-shutup-this-is-mine` (usable as `git shutup-this-is-mine`) is a friendlier
front-end over `git-better-skip-worktree` for the "files I edit but never commit/push,
yet still want to see upstream changes to" workflow. Its `add`/`undo`/`diff`/
`pull` delegate to `git-better-skip-worktree`; its `list` is stateless and unions all
"leave-this-file-alone" mechanisms it finds (skip-worktree, `.git/info/exclude`
local-excludes, and assume-unchanged labeled `other`); its `convert <path>...
<dest>` moves file(s) between those three mechanisms (`<dest>` is
`skip-worktree` / `assume-unchanged` / `local-gitignore`, aliases `sw`/`au`/`lx`),
auto-detecting each file's current source mechanism. `convert` refuses a file
whose working tree differs from HEAD (all directions, so no local edit is
silently exposed or dropped) and refuses converting a local-gitignore'd file
(it's untracked) into a tracked-index mechanism. Converting *into*
local-gitignore untracks the file (`git rm --cached`, working copy kept) and
appends a root-anchored `/path` line to `.git/info/exclude` (removal on the way
out matches only exact `path`/`/path` lines, never globs) — but this is refused
for a file that exists in HEAD: git never ignores a tracked file, and
untracking a committed one stages a deletion a push would propagate, so
committed files must stay skip-worktree. (In practice this makes `→
local-gitignore` apply only to files not in HEAD, e.g. added-but-never-committed
entries.) Its `upstream
[<path>]` fetches then runs `git diff HEAD:<path> @{u}:<path>` to show what
changed on the remote while ignoring your local working-tree edit — the piece
plain skip-worktree can't give you.

Note these tools operate on the *current* repo (`git rev-parse
--show-toplevel`), whereas `gar` inspects arbitrary repos *by path* via
`git -C`, so `gar` keeps its own `gar_repo_skip_worktree_modified_files` (same
`hash-object` vs `HEAD:` technique) rather than shelling out to them.
