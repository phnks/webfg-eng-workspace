###############################################################################
#   Cline-style helper functions — with debug logging
###############################################################################

# Simple logger: everything goes to stderr so stdout stays “clean” for data.
_log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

###############################################################################
# read_file  <file_path>
#            → prints file contents or fails if file missing / unreadable
###############################################################################
read_file() {
  local path="$1"
  _log "read_file: attempting to read '${path}'"
  if [[ ! -f "$path" ]]; then
    _log "read_file: ERROR – file not found"; return 1
  fi
  cat "$path"
  _log "read_file: SUCCESS – $(wc -l <"$path") lines output"
}

###############################################################################
# write_to_file  <file_path>  <content …>
#                → creates parent dirs, overwrites file atomically
###############################################################################
write_to_file() {
  local path="$1"; shift
  _log "write_to_file: ensuring directory '$(dirname "$path")' exists"
  mkdir -p "$(dirname "$path")" || { _log "write_to_file: ERROR – mkdir failed"; return 1; }
  _log "write_to_file: writing to '${path}' (bytes: ${#*})"
  printf '%s' "$*" > "$path"
  _log "write_to_file: SUCCESS – file saved"
}

###############################################################################
# replace_in_file  <file_path>  <search_block>  <replace_block>
#                  → replaces FIRST exact occurrence (multiline-safe)
###############################################################################
replace_in_file() {
  local file="$1" search="$2" replace="$3"
  _log "replace_in_file: searching in '${file}'"

  # 1️⃣  sanity checks
  if [[ ! -f "$file" ]]; then
    _log "replace_in_file: ERROR – file not found"; return 1
  fi
  [[ -z "$search" ]] && { _log "replace_in_file: ERROR – empty search_block"; return 1; }

  # 2️⃣  temp output
  local tmp
  tmp=$(mktemp "${file}.XXXXXX") || { _log "ERROR – mktemp failed"; return 1; }

  # 3️⃣  run substitution
  if ! perl -0777 -pe 's/\Q'"${search}"'\E/'"${replace}"'/s' "$file" > "$tmp"; then
    _log "replace_in_file: ERROR – Perl substitution failed"
    rm -f "$tmp"; return 1
  fi

  # 4️⃣  did anything change?
  if cmp -s "$file" "$tmp"; then
    _log "replace_in_file: ERROR – no match found"
    rm -f "$tmp"; return 1
  fi

  # 5️⃣  commit change
  mv "$tmp" "$file"
  _log "replace_in_file: SUCCESS – first occurrence replaced"
}

###############################################################################
# list_files  [root_dir]
#             → lists every regular file (one per line), skips .git/*
###############################################################################
list_files() {
  local root="${1:-.}"
  _log "list_files: scanning '${root}' for regular files"
  local count=0
  while IFS= read -r path; do
    echo "$path"; ((count++))
  done < <(find "$root" -type f -not -path '*/.git/*')
  _log "list_files: SUCCESS – ${count} files listed"
}

###############################################################################
# search_files  <pattern>  [root_dir]
#               → grep-style file:line:text hits, smart-case
###############################################################################
search_files() {
  local pattern="$1" root="${2:-.}"
  _log "search_files: looking for '${pattern}' under '${root}'"
  local results
  results=$(grep -RIn --exclude-dir=.git -- "$pattern" "$root")
  if [[ -z "$results" ]]; then
    _log "search_files: no matches found"; return 1
  fi
  printf '%s\n' "$results"
  _log "search_files: SUCCESS – $(printf '%s\n' "$results" | wc -l) matches"
}

###############################################################################
#   End of helper functions
###############################################################################