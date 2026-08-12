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
still shows `WARN uncommitted changes`. `gar` does not manage the skip-worktree
flag itself; the standalone `git-list-skip-worktree` script lists and clears it.
