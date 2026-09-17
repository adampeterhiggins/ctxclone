# ctxclone

A zsh plugin that clones GitHub org repos into a `.context/` directory — for pulling
related source code into a project as context for AI agents without polluting the
working tree. Repos clone in parallel with a live progress display, and tab
completion ranks repos by your recent usage.

## Requirements

- `zsh`
- `git`
- [`gh`](https://cli.github.com/) — authenticated, used for the repo-name cache
  that powers tab completion

## Install

### oh-my-zsh

```zsh
git clone https://github.com/adampeterhiggins/ctxclone \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ctxclone
```

Then add `ctxclone` to the `plugins=(...)` list in `~/.zshrc`.

### Manual

```zsh
source /path/to/ctxclone/ctxclone.plugin.zsh
```

### Claude Code plugin

This repo also ships a Claude Code skill that teaches Claude how to use `ctxclone`:

```
claude plugin marketplace add adampeterhiggins/ctxclone
claude plugin install ctxclone@ctxclone
```

## Usage

```zsh
ctxclone [flags] <repo-name> [repo-name ...]
```

| Flag | Description |
| --- | --- |
| `-rm`, `--delete` | Delete local ctxcloned repo(s) |
| `-r`, `--reclone` | Delete then reclone repo(s) |
| `-o`, `--organisation <org>` | GitHub org to clone from |
| `-d`, `--directory <dir>` | Parent dir for clones (default `.context`, relative to cwd) |
| `-n`, `--name <folder>` | Local folder name — applies to the next repo, or the previous one if given after it |
| `-h`, `--help` | Show usage |

```zsh
ctxclone api web                    # clone two repos from your default org
ctxclone -o anthropics claude-code  # clone from a different org
ctxclone -d vendor api              # clone into ./vendor/api
ctxclone platform-api -n api-ctx    # clone platform-api into .context/api-ctx
ctxclone -rm api                    # delete .context/api
```

`ctxclone-refresh [org]` forces a refresh of the cached repo list (otherwise
refreshed automatically every 24h).

Add `.context/` to your project's `.gitignore` — the clones are scratch context,
not project files.

## Configuration

Set these in `~/.zshrc` **before** the plugin loads (i.e. before
`source $ZSH/oh-my-zsh.sh`):

| Variable | Default | Description |
| --- | --- | --- |
| `CTXCLONE_DEFAULT_ORG` | *(unset)* | Default GitHub org. When unset, `-o <org>` is required. |
| `CTXCLONE_DEFAULT_CONTEXT_DIR` | `.context` | Directory repos are cloned into |
| `CTXCLONE_VSCODE_SOURCE_ROOT` | *(unset)* | When set, `<root>/<repo>/.vscode` is copied into each new clone (workspace files are renamed `<repo>-<cwd>.code-workspace`) |
| `CTXCLONE_CACHE_DIR` | `~/.cache/ctxclone` | Cache location for repo lists and usage ranking |
| `CTXCLONE_CACHE_TTL` | `86400` | Seconds before the repo list is refetched |
| `CTXCLONE_LIMIT` | `20` | Max completion suggestions |
| `CTXCLONE_CACHE_LIMIT` | `500` | Max repos fetched from `gh repo list` |

## License

[MIT](LICENSE)
