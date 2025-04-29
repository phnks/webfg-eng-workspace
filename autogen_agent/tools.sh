###############################################################################
#  Cline-style helper functions — v2 (multi-line safe, full logging)
###############################################################################

# Emit to stderr so stdout stays clean for the agent’s data
_log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# Directory *names* (no slashes) that should always be skipped
PRUNE_DIRS=(.git .hg .svn .idea .vscode .cache .config .local
            node_modules dist build out coverage __pycache__
            .venv venv env .env target .gradle .terraform .yarn
            .next .turbo .parcel .svelte-kit .expo .angular)

# Glob patterns (can include slashes) that should be skipped everywhere
PRUNE_GLOBS=('*/.*' '*/tmp_code_*' '*tmp_code_*')

###############################################################################
# build _PRUNE_ARGS once per call (array of: -name/-path … -o …)
###############################################################################
_build_prune_args() {
  local -a args=()

  # 1.  directory-name prunes (match ONLY when current entry is a directory)
  for d in "${PRUNE_DIRS[@]}"; do
    args+=( -name "$d" -o )
  done

  # 2.  glob prunes – treat as path tests so they work anywhere
  for g in "${PRUNE_GLOBS[@]}"; do
    args+=( -path "$g" -o )
  done

  unset 'args[-1]'          # drop trailing -o
  printf '%s\n' "${args[@]}"
}

###############################################################################
# read_file <file_path>
###############################################################################
read_file() {
  local path=$1
  _log "read_file: '${path}'"
  [[ -f $path ]] || { _log "ERROR – file not found"; return 1; }
  cat -- "$path"
  _log "read_file: SUCCESS – $(wc -l <"$path") lines"
}

###############################################################################
# write_to_file <file_path>  [<content>]
# If <content> is omitted, the function reads *everything* from STDIN.
###############################################################################
write_to_file() {
  local path=$1; shift
  mkdir -p "$(dirname "$path")" || { _log "ERROR – mkdir failed"; return 1; }
  _log "write_to_file: '${path}'"
  if [[ $# -gt 0 ]]; then
    printf '%s' "$*" > "$path"
  else
    cat - > "$path"
  fi
  _log "write_to_file: SUCCESS – wrote $(wc -c <"$path") bytes"
}

###############################################################################
# replace_in_file <file_path> <search_block> <replace_block>
#
# Both search & replace args may contain ANY bytes except NUL.
# They can be multi-line; no quoting rules needed.
###############################################################################
replace_in_file() {
  local file=$1 search=$2 replace=$3
  _log "replace_in_file: '${file}'"

  [[ -f $file ]] || { _log "ERROR – file not found"; return 1; }
  local tmp; tmp=$(mktemp "${file}.XXXX") || { _log "ERROR – mktemp failed"; return 1; }

  # Use python so we don’t fight with shell quoting
  python - "$file" "$tmp" <<'PY' "$search" "$replace"
import sys, pathlib, base64, textwrap
fp, tmp, search, replace = sys.argv[1:5]
p = pathlib.Path(fp)
txt = p.read_text()
if search not in txt:
    sys.stderr.write("no match\n"); sys.exit(1)
p_tmp = pathlib.Path(tmp)
p_tmp.write_text(txt.replace(search, replace, 1))
PY
  local rc=$?
  if [[ $rc -ne 0 ]]; then _log "replace_in_file: ERROR – no match found"; rm -f "$tmp"; return 1; fi

  mv -- "$tmp" "$file"
  _log "replace_in_file: SUCCESS – first occurrence replaced"
}

###############################################################################
# list_files [root_dir]  – respects PRUNE_DIRS + PRUNE_GLOBS
###############################################################################
list_files() {
  local root=${1:-.}
  _log "list_files: root='${root}' (pruning ${PRUNE_DIRS[*]} + ${PRUNE_GLOBS[*]})"

  # Build prune args once
  local -a PRUNE; mapfile -t PRUNE < <(_build_prune_args)

  # shellcheck disable=SC2145
  find "$root" \( -type d \( "${PRUNE[@]}" \) -prune \) \
       -o \( -type f \( "${PRUNE[@]}" \) -prune \) \
       -o -type f -print
}

###############################################################################
# search_files <pattern> [root_dir] [--regex]  – same pruning logic
###############################################################################
search_files() {
  local pattern=$1 root=${2:-.} flag=${3:-}
  _log "search_files: pattern='${pattern}' root='${root}' $flag (pruning ${PRUNE_DIRS[*]} + ${PRUNE_GLOBS[*]})"

  local -a grep_flags=(-RIn --exclude-dir=.git)
  [[ $flag == --regex ]] || grep_flags+=(-F)

  for d in "${PRUNE_DIRS[@]}";  do
    grep_flags+=( --exclude-dir="$d" )
  done
  for g in "${PRUNE_GLOBS[@]}"; do
    grep_flags+=( --exclude="$g" --exclude-dir="$g" )
  done
  grep_flags+=( --exclude='.*' )   # ← added line

  grep "${grep_flags[@]}" -- "$pattern" "$root"
  local rc=$?
  [[ $rc -eq 0 ]] && _log "search_files: SUCCESS" || _log "search_files: no matches"
  return $rc
}

###############################################################################
# list_code_definition_names [root_dir]
# Requires: universal-ctags, jq
###############################################################################
list_code_definition_names() {
  local root=${1:-.}
  command -v ctags >/dev/null || { _log "ERROR – universal-ctags not installed"; return 1; }
  command -v jq >/dev/null    || { _log "ERROR – jq not installed"; return 1; }
  _log "list_code_definition_names: indexing '${root}'"
  ctags -R --fields=+n --output-format=json "$root" \
    | jq -r '.[].name' | sort -u
}
###############################################################################