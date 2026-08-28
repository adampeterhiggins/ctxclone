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
  local r s prog label folder
  for r in $repos; do
    folder="${name_map[$r]:-$r}"
    if [[ "$folder" == "$r" ]]; then
      label="$r"
    else
      label="$r → $folder"
    fi
    s=${done_map[$r]}
    case $s in
      0)
        prog=${progress_map[$r]}
        [[ -n "$prog" ]] \
          && printf '  \033[33m…\033[0m  %-40s \033[2m%s\033[0m\033[K\n' "$label" "$prog" \
          || printf '  \033[33m…\033[0m  %s\033[K\n' "$label"
        ;;
      1) printf '  \033[32m✓\033[0m  %s\033[K\n' "$label" ;;
      2) printf '  \033[31m✗\033[0m  %s\033[K\n' "$label" ;;
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
  local -A name_map=()
  local -a argv=("$@")
  local i=1 arg val pending_name="" last_repo=""

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
      -n|--name)
        (( i++ ))
        val="${argv[$i]}"
        [[ -z "$val" ]] && { echo "ctxclone: $arg requires a value" >&2; return 2; }
        if [[ -n "$last_repo" ]]; then
          name_map[$last_repo]="$val"
          last_repo=""
        else
          pending_name="$val"
        fi
        ;;
      --name=*) val="${arg#*=}"; [[ -z "$val" ]] && { echo "ctxclone: --name requires a value" >&2; return 2; }
        if [[ -n "$last_repo" ]]; then
          name_map[$last_repo]="$val"
          last_repo=""
        else
          pending_name="$val"
        fi
        ;;
      -n=*) val="${arg#*=}"; [[ -z "$val" ]] && { echo "ctxclone: -n requires a value" >&2; return 2; }
        if [[ -n "$last_repo" ]]; then
          name_map[$last_repo]="$val"
          last_repo=""
        else
          pending_name="$val"
        fi
        ;;
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
  -n, --name <folder>          Local folder name (default: repo name); applies to the next repo, or the previous one if given after it
  -h, --help                    Show this help

Notes:
  - Flags may appear anywhere in the argument list.
  - Repos clone into <directory>/<folder>. .vscode dir copied from
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
  ctxclone -n api-context platform-api
  ctxclone platform-api -n api-context
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
      *)
        repos+=("$arg")
        if [[ -n "$pending_name" ]]; then
          name_map[$arg]="$pending_name"
          pending_name=""
        else
          name_map[$arg]="${name_map[$arg]:-$arg}"
        fi
        last_repo="$arg"
        ;;
    esac
    (( i++ ))
  done

  if [[ -n "$pending_name" ]]; then
    echo "ctxclone: -n/--name requires a repo name" >&2
    return 2
  fi

  local base="https://github.com/$org"

  if (( ${#repos} == 0 )); then
    echo "Usage: ctxclone [-rm|--delete] [-r|--reclone] [-o <org>] [-d <dir>] [-n <folder>] <repo-name> [repo-name ...]"
    return 1
  fi

  if [[ "$action" == "delete" ]]; then
    local repo folder rc=0
    for repo in $repos; do
      folder="${name_map[$repo]:-$repo}"
      if [[ -d "$ctx_dir/$folder" ]]; then
        if rm -rf "$ctx_dir/$folder"; then
          printf '  \033[32m✓\033[0m  %s (deleted)\n' "$folder"
        else
          printf '  \033[31m✗\033[0m  %s (delete failed)\n' "$folder"
          rc=1
        fi
      else
        printf '  \033[33m–\033[0m  %s (not found)\n' "$folder"
      fi
    done
    [[ -d "$ctx_dir" ]] && rmdir "$ctx_dir" 2>/dev/null
    return $rc
  fi

  local repo

  if [[ "$action" == "reclone" ]]; then
    local folder
    for repo in $repos; do
      folder="${name_map[$repo]:-$repo}"
      rm -rf "$ctx_dir/$folder"
    done
  fi

  mkdir -p "$CTXCLONE_CACHE_DIR"
  setopt LOCAL_OPTIONS NO_MONITOR
  local tmpdir workspace_tag
  tmpdir="$(mktemp -d)"
  workspace_tag="$(basename "$PWD")"

  local -A done_map progress_map

  local folder
  for repo in $repos; do
    folder="${name_map[$repo]:-$repo}"
    done_map[$repo]=0
    progress_map[$repo]=""
    (
      git clone --progress "$base/$repo.git" "$ctx_dir/$folder" \
        >"$tmpdir/$repo.log" 2>&1
      rc=$?
      if (( rc == 0 )); then
        _ctxclone_copy_vscode "$repo" "$ctx_dir/$folder" "$workspace_tag" \
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
      -n|--name) (( i++ )) ;;
      --name=*) ;;
      -n=*) ;;
      -*) ;;
      *)
        (( i == CURRENT )) && continue
        seen+=("$w")
        ;;
    esac
  done

  local cur_repo
  cur_repo="$(git config --get remote.origin.url 2>/dev/null)"
  if [[ -n "$cur_repo" ]]; then
    cur_repo="${cur_repo##*/}"
    cur_repo="${cur_repo%.git}"
    seen+=("$cur_repo")
  fi

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
    '(-n --name)'{-n,--name}'[local folder name for next/previous repo]:folder:_files -/' \
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

# A later `compinit` in ~/.zshrc (appended by tool installers) sources a stale
# zcompdump, which reassigns $_comps wholesale and drops this binding. Re-assert
# it at the first prompt, once .zshrc has finished running.
_ctxclone_ensure_compdef() {
  (( $+functions[compdef] )) || return 0
  [[ -n "${_comps[ctxclone]}" ]] && return 0
  compdef _ctxclone ctxclone
}
autoload -Uz add-zsh-hook && add-zsh-hook precmd _ctxclone_ensure_compdef

ctxclone-refresh() {
  local org="${1:-$CTXCLONE_DEFAULT_ORG}"
  _ctxclone_refresh_cache "$org" && echo "ctxclone cache refreshed ($org)"
}