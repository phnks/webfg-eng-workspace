###############################################################################
#  Cline-style helper functions — v2 (multi-line safe, full logging)
###############################################################################

# Emit to stderr so stdout stays clean for the agent’s data
_log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

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
# list_files [root_dir]
###############################################################################
list_files() {
  local root=${1:-.}
  _log "list_files: scanning '${root}'"
  find "$root" -type f -not -path '*/.git/*' -print
}

###############################################################################
# search_files <pattern> [root_dir] [--regex]
# By default does a **literal** fixed-string search. Add --regex for full grep.
###############################################################################
search_files() {
  local pattern=$1 root=${2:-.} flag=${3:-}
  _log "search_files: pattern='${pattern}' root='${root}' $flag"
  local grep_flags=(-RIn --exclude-dir=.git)
  [[ $flag == --regex ]] || grep_flags+=(-F)
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