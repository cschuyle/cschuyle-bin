A script to tell me which repos I don *NOT* have cloned

# Usage

Create a personal access token in Gitlab. Minimum capabilities:
'api' and 'write_repository'.

The following command will require the token:

```
glab auth login --hostname gitlab.natera.com
```

Once authenticated, you can do this:

```
./_SCRIPTS/gitlab-repo-overseer
./_SCRIPTS/reponalysis
```

Optional extras (repos you can clone but are not a GitLab member of) live in:

```
~/.config/gitlab-repo-overseer/extra-repos
```

One `path_with_namespace` per line (`#` comments allowed).
