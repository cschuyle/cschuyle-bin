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

**Which repos.** Repos come from a `machine-env-repos` manifest (each line
`name|path[|branch]`, branch defaulting to `main`), plus any `~/Yew/*-setup`
repos discovered automatically. A separate name-based skip manifest can exclude
repos from auditing.

**What it checks per repo.** For each repo it reports whether the checkout is
missing / not a git repo, whether the working tree has genuine uncommitted
changes to tracked files (untracked files are ignored), whether the current
branch matches the configured branch, and — after fetching — how many commits it
is ahead (unpushed) or behind the tracked branch. It also advisory-warns when
the configured branch differs from the repo's remote default branch.

**Offer to pull.** When run in an interactive terminal, `gar` offers to rebase-
pull a repo that is behind its tracked branch — but only if the tree has no
genuine uncommitted changes and the checkout is on the tracked branch (it won't
touch a dirty tree or a feature branch).

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
`git-better-skip-worktree` script (usable as `git better-skip-worktree`; the
user aliases it `gbsw`) is the CLI for it: `gbsw list` prints every
skip-worktree'd file prefixed `SAME`/`DIFF`, `gbsw diff <file>` shows the real
diff (temporarily clearing the flag, restoring via a trap), `gbsw skip <path>...`
sets skip-worktree on the given files, and `gbsw undo [<path>...]` clears the flag
(on the named files, or all of them if none are named). Note `gbsw` operates on the *current* repo (`git rev-parse
--show-toplevel`), whereas `gar` inspects arbitrary repos *by path* via
`git -C`, so `gar` keeps its own `gar_repo_skip_worktree_modified_files` (same
`hash-object` vs `HEAD:` technique) rather than shelling out to `gbsw`.
