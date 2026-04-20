# ctxclone

## What it does

`ctxclone` is a zsh command that clones one or more repos from the `focaldata` GitHub org into a `.context/` subdirectory of the current working directory. It is used to pull in repository source code as context for AI agents (like Claude) without polluting the working tree.

## When to suggest it

- The user wants to give Claude context from another focaldata repo
- The user says something like "pull in the X repo", "add context from Y", or "clone Z for context"
- The user is working on a task that spans multiple focaldata repos
- The user asks Claude to look at code that lives in a different repo

## Usage

```zsh
ctxclone <repo-name> [repo-name ...]
```

Repos are cloned to `.context/<repo-name>/` in the current directory.

Multiple repos clone in parallel with a live progress display.

Tab completion is available — it fetches the full list of focaldata repos via `gh` and ranks results by recent usage.

## Examples

```zsh
# Clone a single repo
ctxclone platform-api

# Clone several repos at once
ctxclone platform-api data-pipeline auth-service
```

## Refreshing the repo cache

```zsh
ctxclone-refresh
```

This re-fetches the focaldata repo list from GitHub. The cache expires automatically after 24 hours.

## Notes

- Cloned repos land in `.context/` — this directory is typically gitignored and is purely for agent context
- The `focaldata` org base URL is hardcoded in the plugin (`https://github.com/focaldata`)
- Requires `gh` CLI to be authenticated for cache/completion to work
