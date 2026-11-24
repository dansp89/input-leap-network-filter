# shellcheck shell=bash
# Common helpers: paths, output, i18n, locking, atomic file operations.
# SPDX-License-Identifier: MIT

# ---------------------------------------------------------------- exit codes
readonly EX_OK=0 EX_ERROR=1 EX_USAGE=2 EX_NOT_INSTALLED=3 EX_UNSUPPORTED=4
readonly EX_DEPS=5 EX_CONFLICT=6 EX_BUILD=7 EX_LOCKED=8 EX_UNHEALTHY=10

readonly ILNF_NAME="input-leap-network-filter"
readonly ILNF_REPO="dansp89/input-leap-network-filter"
readonly WRAPPER_MARKER="# input-leap-network-filter: managed wrapper"
readonly DESKTOP_MARKER="X-ILNF-Managed=true"
readonly FILTER_SYMBOL="_ZN17QNetworkInterface12allAddressesEv"

# ---------------------------------------------------------------- options
OPT_VERBOSE=0 OPT_QUIET=0 OPT_DEBUG=0 OPT_DRY_RUN=0 OPT_YES=0
OPT_NON_INTERACTIVE=0 OPT_JSON=0 OPT_COLOR=1 OPT_PATH="" OPT_PURGE=0 OPT_LANG=""

# ---------------------------------------------------------------- paths (XDG)
init_paths() {
  : "${HOME:?HOME is not set}"
  local xc="${XDG_CONFIG_HOME:-}" xd="${XDG_DATA_HOME:-}" xs="${XDG_STATE_HOME:-}"
  # XDG requires absolute paths; ignore relative values.
  [[ $xc == /* ]] || xc="$HOME/.config"
  [[ $xd == /* ]] || xd="$HOME/.local/share"
  [[ $xs == /* ]] || xs="$HOME/.local/state"
  CONFIG_DIR="$xc/$ILNF_NAME"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
  DATA_DIR="$xd/$ILNF_NAME"
  APP_DIR="$DATA_DIR/app"
  BACKUP_DIR="$DATA_DIR/backups"
  STATE_DIR="$xs/$ILNF_NAME"
  MANIFEST="$STATE_DIR/manifest"
  DISABLED_FLAG="$STATE_DIR/disabled"
  JOURNAL="$STATE_DIR/journal"
  LIB_DIR="$HOME/.local/lib/$ILNF_NAME"
  LIB_FILE="$LIB_DIR/network-filter.so"
  PROBE="$LIB_DIR/ilnf-probe"
  USER_BIN="$HOME/.local/bin"
  CLI_LINK="$USER_BIN/$ILNF_NAME"
  APPS_DIR="$xd/applications"
  AUTOSTART_DIR="$xc/autostart"
  LEGACY_LIB="$HOME/.local/lib/input-leap/network-filter.so"
}

# ---------------------------------------------------------------- i18n
declare -gA MSG=()

detect_lang() {
  local l="${OPT_LANG:-${ILNF_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}}"
  case "$l" in
    pt_BR* | pt-BR* | pt*) echo pt_BR ;;
    es*) echo es ;;
    *) echo en ;;
  esac
}

# Locale files are plain key=value text; they are parsed, never sourced.
load_locale() {
  local lang file key val
  lang=$(detect_lang)
  for file in "$ILNF_ROOT/locales/en/messages.txt" "$ILNF_ROOT/locales/$lang/messages.txt"; do
    [[ -r $file ]] || continue
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -z $line || $line == \#* || $line != *=* ]] && continue
      key=${line%%=*} val=${line#*=}
      [[ $key =~ ^[a-z0-9_]+$ ]] && MSG[$key]=$val
    done <"$file"
  done
}

# t KEY [printf args...]
t() {
  local key=$1
  shift
  local fmt=${MSG[$key]:-$key}
  # shellcheck disable=SC2059  # format strings come from our own locale files
  printf -- "$fmt" "$@"
}

# ---------------------------------------------------------------- output
setup_colors() {
  if [[ $OPT_COLOR == 1 && -z ${NO_COLOR:-} && -t 2 && $OPT_JSON == 0 ]]; then
    C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YEL=$'\e[33m' C_BLU=$'\e[34m' C_BLD=$'\e[1m' C_RST=$'\e[0m'
  else
    C_RED="" C_GRN="" C_YEL="" C_BLU="" C_BLD="" C_RST=""
  fi
}

# Human-readable output goes to stderr in --json mode so stdout stays valid JSON.
_out() { if [[ $OPT_JSON == 1 ]]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
info() { [[ $OPT_QUIET == 1 || $OPT_JSON == 1 ]] || _out "$*"; }
verbose() { [[ $OPT_VERBOSE == 1 || $OPT_DEBUG == 1 ]] && [[ $OPT_JSON == 0 ]] && _out "  $*"; return 0; }
debug() { [[ $OPT_DEBUG == 1 ]] && printf '[debug] %s\n' "$*" >&2; return 0; }
warn() { printf '%s%s%s %s\n' "$C_YEL" "$(t lbl_warn)" "$C_RST" "$*" >&2; }
error() { printf '%s%s%s %s\n' "$C_RED" "$(t lbl_error)" "$C_RST" "$*" >&2; }
ok_line() { [[ $OPT_JSON == 1 || $OPT_QUIET == 1 ]] || printf '%s[OK]%s   %s\n' "$C_GRN" "$C_RST" "$*"; }
warn_line() { [[ $OPT_JSON == 1 || $OPT_QUIET == 1 ]] || printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$*"; }
fail_line() { [[ $OPT_JSON == 1 || $OPT_QUIET == 1 ]] || printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$*"; }
die() {
  local code=$1
  shift
  error "$*"
  exit "$code"
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\} s=${s//\"/\\\"} s=${s//$'\n'/\\n} s=${s//$'\t'/\\t} s=${s//$'\r'/\\r}
  printf '%s' "$s"
}
# json_kv key value -> "key":"value"
json_kv() { printf '"%s":"%s"' "$1" "$(json_escape "$2")"; }
json_bool() { if [[ $2 == 1 || $2 == true ]]; then printf '"%s":true' "$1"; else printf '"%s":false' "$1"; fi; }

# ---------------------------------------------------------------- prompts
is_interactive() { [[ $OPT_NON_INTERACTIVE == 0 && -t 0 && -t 1 ]]; }

# confirm "question" -> 0 if accepted. --yes accepts; non-interactive refuses.
confirm() {
  [[ $OPT_YES == 1 ]] && return 0
  is_interactive || return 1
  local ans
  printf '%s [%s] ' "$1" "$(t yes_no)" >&2
  read -r ans || return 1
  [[ $ans =~ ^([yYsS]|yes|sim|si)$ ]]
}

# ---------------------------------------------------------------- execution
# run CMD...: executes unless --dry-run.
run() {
  if [[ $OPT_DRY_RUN == 1 ]]; then
    info "$(t dry_run): $(printf '%q ' "$@")"
    return 0
  fi
  debug "exec: $(printf '%q ' "$@")"
  "$@"
}

# ---------------------------------------------------------------- locking
acquire_lock() {
  mkdir -p -- "$STATE_DIR"
  chmod 700 -- "$STATE_DIR"
  exec 9>"$STATE_DIR/lock"
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || die "$EX_LOCKED" "$(t err_locked)"
  fi
}

# ---------------------------------------------------------------- files
sha256() { [[ -f $1 ]] || return 0; sha256sum -- "$1" | cut -d' ' -f1; }

# Refuse to write through symlinks (symlink attacks) unless explicitly allowed.
assert_not_symlink() {
  [[ -L $1 ]] && die "$EX_CONFLICT" "$(t err_symlink "$1")"
  return 0
}

# atomic_write DEST MODE  (content on stdin)
atomic_write() {
  local dest=$1 mode=$2 dir tmp
  dir=$(dirname -- "$dest")
  if [[ $OPT_DRY_RUN == 1 ]]; then
    cat >/dev/null
    info "$(t dry_run): write $dest"
    return 0
  fi
  mkdir -p -- "$dir"
  assert_not_symlink "$dest"
  tmp=$(mktemp -- "$dir/.ilnf.XXXXXX")
  if ! cat >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod "$mode" -- "$tmp"
  mv -fT -- "$tmp" "$dest"
}

# atomic_copy SRC DEST MODE
atomic_copy() { atomic_write "$2" "$3" <"$1"; }

# Write only when content differs (idempotency). Returns 0 if changed, 1 if unchanged.
write_if_changed() {
  local dest=$1 mode=$2 tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $dest ]] && cmp -s -- "$tmp" "$dest"; then
    rm -f -- "$tmp"
    return 1
  fi
  atomic_write "$dest" "$mode" <"$tmp"
  rm -f -- "$tmp"
  return 0
}

# Owned by the current user and not writable by group/others.
is_trusted_file() {
  local f=$1 uid mode
  [[ -f $f && ! -L $f ]] || return 1
  read -r uid mode < <(stat -c '%u %a' -- "$f") || return 1
  [[ $uid == "$(id -u)" ]] || return 1
  ((8#$mode & 8#022)) && return 1
  return 0
}

is_elf() { [[ -f $1 ]] && [[ $(head -c4 -- "$1" 2>/dev/null | od -An -c | tr -d ' ') == '177ELF' ]]; }

# ---------------------------------------------------------------- manifest
# Plain key=value file; values are read, never evaluated.
declare -gA MF=()

manifest_load() {
  MF=()
  [[ -f $MANIFEST ]] || return 1
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == *=* && $line != \#* ]] || continue
    MF[${line%%=*}]=${line#*=}
  done <"$MANIFEST"
  return 0
}

manifest_save() {
  local k
  {
    printf '# %s installation manifest - do not edit\n' "$ILNF_NAME"
    for k in $(printf '%s\n' "${!MF[@]}" | sort); do
      printf '%s=%s\n' "$k" "${MF[$k]}"
    done
  } | atomic_write "$MANIFEST" 600
}

# Manifest content without volatile fields, for change detection.
manifest_snapshot() {
  local k
  for k in $(printf '%s\n' "${!MF[@]}" | sort); do
    [[ $k == updated_at ]] || printf '%s=%s\n' "$k" "${MF[$k]}"
  done
}

is_installed() { [[ -f $MANIFEST ]]; }

# ---------------------------------------------------------------- journal
# A journal records an in-progress transaction so an interrupted install can
# be detected and recovered by `repair`.
journal_begin() { [[ $OPT_DRY_RUN == 1 ]] || printf '%s %s\n' "$1" "$(date -u +%FT%TZ)" >"$JOURNAL"; }
journal_end() { rm -f -- "$JOURNAL"; }

ilnf_version() { tr -d '[:space:]' <"$ILNF_ROOT/VERSION"; }
