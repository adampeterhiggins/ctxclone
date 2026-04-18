zmodload zsh/complist

typeset -g CTXCLONE_CACHE_DIR="$HOME/.cache/ctxclone"
typeset -g CTXCLONE_REPO_CACHE="$CTXCLONE_CACHE_DIR/repos.txt"
typeset -g CTXCLONE_USAGE_FILE="$CTXCLONE_CACHE_DIR/recent.txt"
typeset -g CTXCLONE_CACHE_TTL=86400

ctxclone() {
  local repo="$1"
  local base="https://github.com/focaldata"

  if [[ -z "$repo" ]]; then
    echo "Usage: ctxclone <repo-name>"
    return 1
  fi

  mkdir -p "$CTXCLONE_CACHE_DIR"

  git clone "$base/$repo.git" ".context/$repo" || return 1
  _ctxclone_record_usage "$repo"
}

_ctxclone_record_usage() {
  local repo="$1"
  local tmp
  tmp="$(mktemp)"

  {
    print -r -- "$repo"
    [[ -f "$CTXCLONE_USAGE_FILE" ]] && grep -Fxv -- "$repo" "$CTXCLONE_USAGE_FILE"
  } > "$tmp"

  mv "$tmp" "$CTXCLONE_USAGE_FILE"
}

_ctxclone_refresh_cache() {
  mkdir -p "$CTXCLONE_CACHE_DIR"

  gh repo list focaldata \
    --limit 500 \
    --json name,pushedAt \
    -q 'sort_by(.pushedAt) | reverse | .[].name' \
    >| "$CTXCLONE_REPO_CACHE.tmp" 2>/dev/null || return 1

  mv "$CTXCLONE_REPO_CACHE.tmp" "$CTXCLONE_REPO_CACHE"
}

_ctxclone_cache_is_stale() {
  [[ ! -s "$CTXCLONE_REPO_CACHE" ]] && return 0
  local mtime
  mtime="$(stat -f %m "$CTXCLONE_REPO_CACHE" 2>/dev/null)" || return 0
  (( EPOCHSECONDS - mtime > CTXCLONE_CACHE_TTL ))
}

_ctxclone_ranked_repos() {
  local -a usage repos ranked
  local repo

  [[ -f "$CTXCLONE_USAGE_FILE" ]] && usage=("${(@f)$(<"$CTXCLONE_USAGE_FILE")}")
  [[ -f "$CTXCLONE_REPO_CACHE" ]] && repos=("${(@f)$(<"$CTXCLONE_REPO_CACHE")}")

  ranked=()

  for repo in $usage; do
    if (( ${repos[(Ie)$repo]} )); then
      ranked+=("$repo")
    fi
  done

  for repo in $repos; do
    if (( ! ${ranked[(Ie)$repo]} )); then
      ranked+=("$repo")
    fi
  done

  print -l -- $ranked
}

_ctxclone() {
  local -a repos

  mkdir -p "$CTXCLONE_CACHE_DIR"

  if _ctxclone_cache_is_stale; then
    _ctxclone_refresh_cache
  fi

  repos=("${(@f)$(_ctxclone_ranked_repos)}")
  _describe 'repo' repos
}

compdef _ctxclone ctxclone

ctxclone-refresh() {
  _ctxclone_refresh_cache && echo "ctxclone cache refreshed"
}