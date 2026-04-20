zmodload zsh/complist

typeset -g CTXCLONE_CACHE_DIR="$HOME/.cache/ctxclone"
typeset -g CTXCLONE_REPO_CACHE="$CTXCLONE_CACHE_DIR/repos.txt"
typeset -g CTXCLONE_USAGE_FILE="$CTXCLONE_CACHE_DIR/recent.txt"
typeset -g CTXCLONE_CACHE_TTL=86400
typeset -g CTXCLONE_LIMIT=20
typeset -g CTXCLONE_CACHE_LIMIT=500

_ctxclone_render_status() {
  local r s
  for r in $repos; do
    s=${done_map[$r]}
    case $s in
      0) printf '  \033[33m…\033[0m  %s\n' "$r" ;;
      1) printf '  \033[32m✓\033[0m  %s\n' "$r" ;;
      2) printf '  \033[31m✗\033[0m  %s\n' "$r" ;;
    esac
  done
}

ctxclone() {
  local base="https://github.com/focaldata"

  if [[ $# -eq 0 ]]; then
    echo "Usage: ctxclone <repo-name> [repo-name ...]"
    return 1
  fi

  mkdir -p "$CTXCLONE_CACHE_DIR"
  setopt LOCAL_OPTIONS NO_MONITOR

  local -a repos=("$@")
  local tmpdir
  tmpdir="$(mktemp -d)"

  local -A done_map
  local repo

  for repo in $repos; do
    done_map[$repo]=0
    (
      git clone "$base/$repo.git" ".context/$repo" \
        >"$tmpdir/$repo.log" 2>&1
      echo $? >"$tmpdir/$repo.exit"
    ) &
  done

  local n=${#repos} remaining=${#repos} rc
  _ctxclone_render_status

  while (( remaining > 0 )); do
    sleep 0.2
    for repo in $repos; do
      [[ ${done_map[$repo]} != 0 ]] && continue
      [[ ! -f "$tmpdir/$repo.exit" ]] && continue
      rc=$(<"$tmpdir/$repo.exit")
      if (( rc == 0 )); then
        done_map[$repo]=1
        _ctxclone_record_usage "$repo"
      else
        done_map[$repo]=2
      fi
      (( remaining-- ))
    done
    printf '\033[%dA' $n
    _ctxclone_render_status
  done

  rm -rf "$tmpdir"

  for repo in $repos; do
    [[ ${done_map[$repo]} == 2 ]] && return 1
  done
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
    --limit $CTXCLONE_CACHE_LIMIT \
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
  local -a repos filtered
  local limit=$CTXCLONE_LIMIT

  mkdir -p "$CTXCLONE_CACHE_DIR"

  if _ctxclone_cache_is_stale; then
    _ctxclone_refresh_cache
  fi

  repos=("${(@f)$(_ctxclone_ranked_repos)}")
  filtered=(${(M)repos:#${PREFIX}*})
  filtered=(${filtered[1,$limit]})
  _describe 'repo' filtered
}

compdef _ctxclone ctxclone

ctxclone-refresh() {
  _ctxclone_refresh_cache && echo "ctxclone cache refreshed"
}