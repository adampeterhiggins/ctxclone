zmodload zsh/complist

typeset -g CTXCLONE_CACHE_DIR="$HOME/.cache/ctxclone"
typeset -g CTXCLONE_REPO_CACHE="$CTXCLONE_CACHE_DIR/repos.txt"
typeset -g CTXCLONE_USAGE_FILE="$CTXCLONE_CACHE_DIR/recent.txt"
typeset -g CTXCLONE_CACHE_TTL=86400
typeset -g CTXCLONE_LIMIT=20
typeset -g CTXCLONE_CACHE_LIMIT=500
typeset -g CTXCLONE_VSCODE_SOURCE_ROOT="$HOME/Documents/Focaldata/Git"
typeset -g CTXCLONE_DEFAULT_ORG="focaldata"
typeset -g CTXCLONE_DEFAULT_CONTEXT_DIR=".context"

_ctxclone_read_progress() {
  local logfile="$1"
  [[ ! -f "$logfile" ]] && return

  local line pct phase
  line=$(tr '\r' '\n' < "$logfile" 2>/dev/null \
    | grep -oE '(Receiving objects|Resolving deltas|Compressing objects|Counting objects|Enumerating objects):[ ]+[0-9]+%' \
    | tail -1)
  [[ -z "$line" ]] && return

  pct=$(echo "$line" | grep -oE '[0-9]+%')
  case "${line%% *}" in
    Receiving)   phase="receiving" ;;
    Resolving)   phase="resolving" ;;
    Compressing) phase="compressing" ;;
    Counting)    phase="counting" ;;
    Enumerating) phase="enumerating" ;;
    *) return ;;
  esac

  echo "$phase $pct"
}

_ctxclone_render_status() {
  local r s prog
  for r in $repos; do
    s=${done_map[$r]}
    case $s in
      0)
        prog=${progress_map[$r]}
        [[ -n "$prog" ]] \
          && printf '  \033[33m…\033[0m  %-40s \033[2m%s\033[0m\033[K\n' "$r" "$prog" \
          || printf '  \033[33m…\033[0m  %s\033[K\n' "$r"
        ;;
      1) printf '  \033[32m✓\033[0m  %s\033[K\n' "$r" ;;
      2) printf '  \033[31m✗\033[0m  %s\033[K\n' "$r" ;;
    esac
  done
}

_ctxclone_copy_vscode() {
  local repo="$1" dest="$2" workspace_tag="$3"
  local src="$CTXCLONE_VSCODE_SOURCE_ROOT/$repo/.vscode"

  [[ ! -d "$src" ]] && return 0

  cp -R "$src" "$dest/.vscode" || return 1

  local f
  for f in "$dest/.vscode"/*.code-workspace(N); do
    mv "$f" "$dest/.vscode/$repo-$workspace_tag.code-workspace"
    break
  done
}

ctxclone() {
  local action="clone"
  local org="$CTXCLONE_DEFAULT_ORG"
  local ctx_dir="$CTXCLONE_DEFAULT_CONTEXT_DIR"
  local -a repos=()
  local -a argv=("$@")
  local i=1 arg val

  while (( i <= ${#argv} )); do
    arg="${argv[$i]}"
    case "$arg" in
      -rm|--delete) action="delete" ;;
      -r|--reclone) action="reclone" ;;
      -o|--organisation|--organization)
        (( i++ ))
        val="${argv[$i]}"
        [[ -z "$val" ]] && { echo "ctxclone: $arg requires a value" >&2; return 2; }
        org="$val"
        ;;
      --organisation=*|--organization=*)
        org="${arg#*=}"
        [[ -z "$org" ]] && { echo "ctxclone: --organisation requires a value" >&2; return 2; }
        ;;
      -o=*) org="${arg#*=}" ;;
      -d|--directory)
        (( i++ ))
        val="${argv[$i]}"
        [[ -z "$val" ]] && { echo "ctxclone: $arg requires a value" >&2; return 2; }
        ctx_dir="$val"
        ;;
      --directory=*) ctx_dir="${arg#*=}" ;;
      -d=*) ctx_dir="${arg#*=}" ;;
      -h|--help)
        cat <<EOF
ctxclone — clone org repos into a local context directory

Usage:
  ctxclone [flags] <repo-name> [repo-name ...]

Flags:
  -rm, --delete                 Delete local ctxcloned repo(s)
  -r, --reclone                 Delete then reclone repo(s)
  -o, --organisation <org>      GitHub org to clone from (default: $CTXCLONE_DEFAULT_ORG)
  -d, --directory <dir>        Parent dir for clones; relative paths use cwd (default: $CTXCLONE_DEFAULT_CONTEXT_DIR)
  -h, --help                    Show this help

Notes:
  - Flags may appear anywhere in the argument list.
  - Repos clone into <directory>/<repo>. .vscode dir copied from
    \$CTXCLONE_VSCODE_SOURCE_ROOT/<repo>/.vscode if present.
  - Tab completion ranks by recent usage, cached from \`gh repo list <org>\`.

Related:
  ctxclone-refresh [org]       Force refresh of the repo name cache.

Examples:
  ctxclone api web
  ctxclone -rm api
  ctxclone api -r web
  ctxclone -o anthropics claude-code
  ctxclone -d vendor api
EOF
        return 0
        ;;
      --)
        (( i++ ))
        while (( i <= ${#argv} )); do
          repos+=("${argv[$i]}")
          (( i++ ))
        done
        break
        ;;
      -*)
        echo "ctxclone: unknown flag: $arg" >&2
        return 2
        ;;
      *) repos+=("$arg") ;;
    esac
    (( i++ ))
  done

  local base="https://github.com/$org"

  if (( ${#repos} == 0 )); then
    echo "Usage: ctxclone [-rm|--delete] [-r|--reclone] [-o <org>] [-d <dir>] <repo-name> [repo-name ...]"
    return 1
  fi

  if [[ "$action" == "delete" ]]; then
    local repo rc=0
    for repo in $repos; do
      if [[ -d "$ctx_dir/$repo" ]]; then
        if rm -rf "$ctx_dir/$repo"; then
          printf '  \033[32m✓\033[0m  %s (deleted)\n' "$repo"
        else
          printf '  \033[31m✗\033[0m  %s (delete failed)\n' "$repo"
          rc=1
        fi
      else
        printf '  \033[33m–\033[0m  %s (not found)\n' "$repo"
      fi
    done
    [[ -d "$ctx_dir" ]] && rmdir "$ctx_dir" 2>/dev/null
    return $rc
  fi

  local repo

  if [[ "$action" == "reclone" ]]; then
    for repo in $repos; do
      rm -rf "$ctx_dir/$repo"
    done
  fi

  mkdir -p "$CTXCLONE_CACHE_DIR"
  setopt LOCAL_OPTIONS NO_MONITOR
  local tmpdir workspace_tag
  tmpdir="$(mktemp -d)"
  workspace_tag="$(basename "$PWD")"

  local -A done_map progress_map

  for repo in $repos; do
    done_map[$repo]=0
    progress_map[$repo]=""
    (
      git clone --progress "$base/$repo.git" "$ctx_dir/$repo" \
        >"$tmpdir/$repo.log" 2>&1
      rc=$?
      if (( rc == 0 )); then
        _ctxclone_copy_vscode "$repo" "$ctx_dir/$repo" "$workspace_tag" \
          >>"$tmpdir/$repo.log" 2>&1
      fi
      echo $rc >"$tmpdir/$repo.exit"
    ) &
  done

  local n=${#repos} remaining=${#repos} rc
  _ctxclone_render_status

  while (( remaining > 0 )); do
    sleep 0.2
    for repo in $repos; do
      if [[ ${done_map[$repo]} == 0 ]]; then
        progress_map[$repo]="$(_ctxclone_read_progress "$tmpdir/$repo.log")"
        [[ ! -f "$tmpdir/$repo.exit" ]] && continue
        rc=$(<"$tmpdir/$repo.exit")
        if (( rc == 0 )); then
          done_map[$repo]=1
          _ctxclone_record_usage "$repo"
        else
          done_map[$repo]=2
        fi
        (( remaining-- ))
      fi
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

_ctxclone_cache_path() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  print -r -- "$CTXCLONE_CACHE_DIR/repos-$org.txt"
}

_ctxclone_refresh_cache() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  local cache
  cache="$(_ctxclone_cache_path "$org")"
  mkdir -p "$CTXCLONE_CACHE_DIR"

  gh repo list "$org" \
    --limit $CTXCLONE_CACHE_LIMIT \
    --json name,pushedAt \
    -q 'sort_by(.pushedAt) | reverse | .[].name' \
    >| "$cache.tmp" 2>/dev/null || return 1

  mv "$cache.tmp" "$cache"
}

_ctxclone_cache_is_stale() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  local cache
  cache="$(_ctxclone_cache_path "$org")"
  [[ ! -s "$cache" ]] && return 0
  local mtime
  mtime="$(stat -f %m "$cache" 2>/dev/null)" || return 0
  (( EPOCHSECONDS - mtime > CTXCLONE_CACHE_TTL ))
}

_ctxclone_ranked_repos() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  local cache
  cache="$(_ctxclone_cache_path "$org")"
  local -a usage repos ranked
  local repo

  [[ -f "$CTXCLONE_USAGE_FILE" ]] && usage=("${(@f)$(<"$CTXCLONE_USAGE_FILE")}")
  [[ -f "$cache" ]] && repos=("${(@f)$(<"$cache")}")

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
  local -a repos filtered seen
  local limit=$CTXCLONE_LIMIT
  local org="$CTXCLONE_DEFAULT_ORG"
  local i w next s

  for (( i=2; i<=${#words}; i++ )); do
    w="${words[$i]}"
    case "$w" in
      -o|--organisation|--organization)
        next="${words[$((i+1))]}"
        [[ -n "$next" ]] && org="$next"
        (( i++ ))
        ;;
      --organisation=*|--organization=*) org="${w#*=}" ;;
      -o=*) org="${w#*=}" ;;
      -d|--directory) (( i++ )) ;;
      -*) ;;
      *)
        (( i == CURRENT )) && continue
        seen+=("$w")
        ;;
    esac
  done

  mkdir -p "$CTXCLONE_CACHE_DIR"

  if _ctxclone_cache_is_stale "$org"; then
    _ctxclone_refresh_cache "$org"
  fi

  repos=("${(@f)$(_ctxclone_ranked_repos "$org")}")

  _arguments -s -S \
    '(-rm --delete -r --reclone)'{-rm,--delete}'[delete local ctxcloned repo(s)]' \
    '(-rm --delete -r --reclone)'{-r,--reclone}'[delete then reclone repo(s)]' \
    '(-o --organisation --organization)'{-o,--organisation,--organization}'[GitHub org]:org:' \
    '(-d --directory)'{-d,--directory}'[parent dir for clones]:dir:_files -/' \
    '(-h --help)'{-h,--help}'[show usage]' \
    '*:repo:->repos'

  case $state in
    repos)
      filtered=(${(M)repos:#${PREFIX}*})
      for s in $seen; do
        filtered=(${filtered:#$s})
      done
      filtered=(${filtered[1,$limit]})
      _describe 'repo' filtered
      ;;
  esac
}

compdef _ctxclone ctxclone

ctxclone-refresh() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  _ctxclone_refresh_cache "$org" && echo "ctxclone cache refreshed ($org)"
}