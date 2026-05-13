# Notes for agents and automation

This file is for anyone (human or tool) changing this repository.

## Git commits

Do **not** run `git commit` unless the user explicitly asks you to commit (e.g. they say “commit”, “git commit”, or clearly instruct you to create a commit).

Making edits, running tests, and using read-only git commands (`git status`, `git diff`, `git log`, etc.) is fine. Do not assume a commit is desired when a task is done.

The same policy is mirrored for Cursor in [`.cursor/rules/git-and-commits.mdc`](.cursor/rules/git-and-commits.mdc) (`alwaysApply`).
