# shellcheck shell=bash
# Read-only reporting: status, doctor, interfaces, preview, version, update.
# SPDX-License-Identifier: MIT

# Locate (or build on demand) the Qt-free probe helper.
get_probe() {
  local p
  for p in "$PROBE" "$ILNF_ROOT/build/ilnf-probe"; do
    [[ -x $p ]] && {
      echo "$p"
      return 0
    }
  done
  p="$STATE_DIR/cache/ilnf-probe"
  if [[ ! -x $p || $p -ot $ILNF_ROOT/src/config.cpp ]]; then
    build_probe_only "$p" || return 1
  fi
  echo "$p"
}

# ---------------------------------------------------------------- interfaces
do_interfaces() {
  local probe
  probe=$(get_probe) || die "$EX_DEPS" "$(t err_no_probe)"
  if [[ $OPT_JSON == 1 ]]; then
    "$probe" interfaces --json --config "$CONFIG_FILE"
    return 0
  fi
  printf '%s%-20s %-10s %-9s %-5s %-7s %s%s\n' "$C_BLD" "$(t col_name)" "$(t col_kind)" "$(t col_device)" \
    "$(t col_state)" "$(t col_filter)" "$(t col_addresses)" "$C_RST"
  local n k p s d r a mark
  while IFS=$'\t' read -r n k p s d r a; do
    if [[ $d == filter ]]; then mark="${C_YEL}$(t lbl_hidden)${C_RST}"; else mark="${C_GRN}$(t lbl_shown)${C_RST}"; fi
    printf '%-20s %-10s %-9s %-5s %-7s %s\n' "$n" "$k" "$p" "$s" "$mark" "$a"
  done < <("$probe" interfaces --config "$CONFIG_FILE" || true)
}

# ---------------------------------------------------------------- preview
do_preview() {
  local probe valid=1
  probe=$(get_probe) || die "$EX_DEPS" "$(t err_no_probe)"
  "$probe" check-config --config "$CONFIG_FILE" >/dev/null 2>&1 || valid=0
  if [[ $OPT_JSON == 1 ]]; then
    "$probe" interfaces --json --config "$CONFIG_FILE" || true
    return 0
  fi
  if [[ $valid == 0 ]]; then
    warn "$(t warn_config_invalid_passthrough)"
    "$probe" check-config --config "$CONFIG_FILE" >&2 || true
  fi
  local n k p s d r a hidden=0 shown=0 hidden_addr=0 shown_addr=0 cnt
  local -a hl=() sl=()
  while IFS=$'\t' read -r n k p s d r a; do
    cnt=0
    [[ $a != - ]] && cnt=$(awk -F, '{print NF}' <<<"$a")
    if [[ $d == filter ]]; then
      hidden=$((hidden + 1)) hidden_addr=$((hidden_addr + cnt))
      hl+=("  - $n ($r) ${a/#-/}")
    else
      shown=$((shown + 1)) shown_addr=$((shown_addr + cnt))
      sl+=("  + $n [$k] ${a/#-/}")
    fi
  done < <("$probe" interfaces --config "$CONFIG_FILE" || true)
  info "$C_BLD$(t prev_shown "$shown" "$shown_addr")$C_RST"
  printf '%s\n' "${sl[@]}"
  info "$C_BLD$(t prev_hidden "$hidden" "$hidden_addr")$C_RST"
  [[ ${#hl[@]} -gt 0 ]] && printf '%s\n' "${hl[@]}"
  [[ -f $DISABLED_FLAG ]] && warn "$(t warn_still_disabled)"
  return 0
}

# ---------------------------------------------------------------- status
do_status() {
  manifest_load || true
  local installed=0 enabled=0 lib_ok=0 wrapper_ok=0 original_ok=0
  is_installed && installed=1
  [[ $installed == 1 && ! -e $DISABLED_FLAG ]] && enabled=1
  [[ -f $LIB_FILE && $(sha256 "$LIB_FILE") == "${MF[lib_sha256]:-x}" ]] && lib_ok=1
  [[ -n ${MF[wrapper]:-} && $(sha256 "${MF[wrapper]}") == "${MF[wrapper_sha256]:-x}" ]] && wrapper_ok=1
  [[ -n ${MF[original]:-} ]] && is_elf "${MF[original]}" && original_ok=1
  if [[ $OPT_JSON == 1 ]]; then
    printf '{%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s}\n' \
      "$(json_kv version "$(ilnf_version)")" "$(json_bool installed $installed)" \
      "$(json_bool enabled $enabled)" "$(json_kv mode "${MF[mode]:-}")" \
      "$(json_kv target "${MF[target]:-}")" "$(json_kv original "${MF[original]:-}")" \
      "$(json_kv qt_major "${MF[qt_major]:-}")" "$(json_bool library_ok $lib_ok)" \
      "$(json_bool wrapper_ok $wrapper_ok)" "$(json_bool original_ok $original_ok)" \
      "$(json_kv config "$CONFIG_FILE")" "$(json_kv installed_version "${MF[version]:-}")"
    return 0
  fi
  if [[ $installed == 0 ]]; then
    info "$(t st_not_installed)"
    return "$EX_NOT_INSTALLED"
  fi
  info "$C_BLD$ILNF_NAME ${MF[version]}$C_RST"
  info "  $(t st_state): $([[ $enabled == 1 ]] && t st_enabled || t st_disabled)"
  info "  $(t st_mode): ${MF[mode]}"
  info "  $(t st_launcher): ${MF[target]}"
  info "  $(t st_original): ${MF[original]}"
  info "  Qt: ${MF[qt_major]} (${MF[qt_system_version]:-?})"
  info "  $(t st_library): $LIB_FILE $([[ $lib_ok == 1 ]] && echo OK || echo "$(t lbl_problem)")"
  info "  $(t st_wrapper): ${MF[wrapper]} $([[ $wrapper_ok == 1 ]] && echo OK || echo "$(t lbl_problem)")"
  info "  $(t st_config): $CONFIG_FILE"
  [[ $lib_ok == 1 && $wrapper_ok == 1 && $original_ok == 1 ]] || {
    warn "$(t hint_run_doctor)"
    return "$EX_UNHEALTHY"
  }
}

# ---------------------------------------------------------------- doctor
declare -a DOC_JSON=()
DOC_FAIL=0 DOC_WARN=0
_check() { # level message key
  local lvl=$1 msg=$2 key=${3:-check}
  case $lvl in
    ok) ok_line "$msg" ;;
    warn) warn_line "$msg"; DOC_WARN=$((DOC_WARN + 1)) ;;
    fail) fail_line "$msg"; DOC_FAIL=$((DOC_FAIL + 1)) ;;
  esac
  DOC_JSON+=("{$(json_kv check "$key"),$(json_kv level "$lvl"),$(json_kv message "$msg")}")
}

do_doctor() {
  detect_os
  detect_pkg_manager
  detect_toolchain
  detect_input_leap
  manifest_load || true
  local level
  level=$(support_level)

  _check "$([[ $level == Unsupported ]] && echo warn || echo ok)" "$(t dr_os "$OS_NAME" "$level")" os
  _check ok "$(t dr_arch "$ARCH")" arch
  _check "$([[ $PKG_MGR == none ]] && echo warn || echo ok)" "$(t dr_pkg "$PKG_MGR")" package_manager

  case $IL_STATE in
    ok)
      _check ok "$(t dr_il "$IL_REAL" "${IL_VERSION:-?}" "$IL_METHOD")" input_leap
      _check ok "$(t dr_qt "$IL_QT" "$(qt_version_of_system "$IL_QT")")" qt
      ;;
    missing) _check fail "$(t err_il_missing)" input_leap ;;
    unsupported) _check fail "$(t err_il_unsupported "$IL_METHOD" "$IL_REASON")" input_leap ;;
  esac
  [[ -n $IL_RUNPATH ]] && _check warn "$(t warn_runpath "$IL_RUNPATH")" runpath

  if [[ -n $CXX_BIN ]]; then _check ok "$(t dr_compiler "$CXX_BIN")" compiler; else _check warn "$(t err_no_compiler)" compiler; fi
  if [[ -n $IL_QT ]]; then
    if qt_dev_available "$IL_QT"; then _check ok "$(t dr_qtdev "$IL_QT")" qt_dev; else _check warn "$(t dr_no_qtdev "$IL_QT")" qt_dev; fi
  fi

  if is_installed; then
    _check ok "$(t dr_installed "${MF[version]}" "${MF[mode]}")" installation
    [[ ${MF[version]} == "$(ilnf_version)" ]] || _check warn "$(t dr_version_diff "${MF[version]}" "$(ilnf_version)")" version
    if [[ -f $LIB_FILE ]]; then
      if [[ $(sha256 "$LIB_FILE") == "${MF[lib_sha256]}" ]]; then
        _check ok "$(t dr_lib_ok)" library
      else
        _check fail "$(t dr_lib_modified)" library
      fi
      is_trusted_file "$LIB_FILE" || _check fail "$(t dr_lib_perms)" library_permissions
      if [[ -n $IL_QT && ${MF[qt_major]} != "$IL_QT" ]]; then _check fail "$(t dr_qt_changed "${MF[qt_major]}" "$IL_QT")" abi; fi
    else
      _check fail "$(t dr_lib_missing)" library
    fi
    local w=${MF[wrapper]}
    if [[ ! -e $w ]]; then
      _check fail "$(t dr_wrapper_missing "$w")" wrapper
    elif is_elf "$w"; then
      _check fail "$(t warn_external_update "$w")" wrapper
    elif [[ $(sha256 "$w") != "${MF[wrapper_sha256]}" ]]; then
      _check warn "$(t dr_wrapper_modified "$w")" wrapper
    else
      _check ok "$(t dr_wrapper_ok)" wrapper
    fi
    if is_elf "${MF[original]}"; then
      if [[ $(sha256 "${MF[original]}") == "${MF[original_sha256]}" ]]; then
        _check ok "$(t dr_original_ok)" original
      else
        _check warn "$(t dr_original_updated)" original
      fi
    else
      _check fail "$(t warn_original_missing "${MF[original]}")" original
    fi
    if [[ -e $DISABLED_FLAG ]]; then _check warn "$(t st_disabled)" enabled; else _check ok "$(t st_enabled)" enabled; fi
    local f IFS=';'
    for f in ${MF[desktop_files]:-}; do
      if [[ -f $f ]] && grep -qxF "$DESKTOP_MARKER" "$f"; then _check ok "$(t dr_desktop_ok "$f")" desktop; else _check warn "$(t dr_desktop_missing "$f")" desktop; fi
    done
    unset IFS
    if [[ ${MF[mode]} == external ]]; then
      local first
      first=$(command -v input-leap 2>/dev/null || true)
      [[ -n $first ]] && ! is_our_wrapper "$first" && _check warn "$(t dr_path_shadow "$first")" path
    fi
  else
    _check warn "$(t st_not_installed)" installation
    [[ $IL_LEGACY == 1 ]] && _check warn "$(t dr_legacy)" legacy
  fi
  [[ -f $JOURNAL ]] && _check warn "$(t warn_interrupted "$(cat "$JOURNAL")")" journal
  [[ -n ${LD_PRELOAD:-} ]] && _check warn "$(t dr_global_preload "$LD_PRELOAD")" ld_preload
  grep -qs network-filter /etc/ld.so.preload && _check fail "$(t dr_etc_preload)" ld_so_preload

  # Config + interfaces
  local probe phys=0 virt=0 filt=0 n k p s d r a
  if probe=$(get_probe 2>/dev/null); then
    if "$probe" check-config --config "$CONFIG_FILE" >/dev/null 2>&1; then
      _check ok "$(t dr_config_ok "$CONFIG_FILE")" config
    else
      _check fail "$(t err_config_invalid "$CONFIG_FILE")" config
    fi
    while IFS=$'\t' read -r n k p s d r a; do
      [[ $k == loopback ]] && continue
      if [[ $p == physical ]]; then phys=$((phys + 1)); else virt=$((virt + 1)); fi
      [[ $d == filter ]] && filt=$((filt + 1))
      [[ $p == physical && $d == filter ]] && _check warn "$(t dr_physical_filtered "$n")" physical_filtered
    done < <("$probe" interfaces --config "$CONFIG_FILE" 2>/dev/null || true)
  fi

  local status=Healthy rc=0
  if ((DOC_FAIL > 0)); then
    status=Unhealthy rc=$EX_UNHEALTHY
  elif ((DOC_WARN > 0)); then status=Warnings; fi
  if [[ $OPT_JSON == 1 ]]; then
    local IFS=,
    printf '{"status":"%s","physical_interfaces":%d,"virtual_interfaces":%d,"filtered_interfaces":%d,"checks":[%s]}\n' \
      "$status" "$phys" "$virt" "$filt" "${DOC_JSON[*]}"
  else
    info ""
    info "$(t dr_phys "$phys")"
    info "$(t dr_virt "$virt")"
    info "$(t dr_filt "$filt")"
    info ""
    info "$C_BLD$(t dr_status "$status")$C_RST"
    ((DOC_FAIL > 0)) && info "$(t hint_repair)"
  fi
  return "$rc"
}

# ---------------------------------------------------------------- version
do_version() {
  if [[ $OPT_JSON == 1 ]]; then
    printf '{%s}\n' "$(json_kv version "$(ilnf_version)")"
  else
    printf '%s %s\n' "$ILNF_NAME" "$(ilnf_version)"
  fi
}

# ---------------------------------------------------------------- update
# Optional: checks GitHub Releases. Never runs on its own; works offline
# (the check simply fails with a message).
version_gt() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]; }

do_update() {
  command -v curl >/dev/null 2>&1 || die "$EX_DEPS" "$(t err_no_curl)"
  local api="https://api.github.com/repos/$ILNF_REPO/releases/latest" json tag latest cur
  cur=$(ilnf_version)
  info "$(t upd_checking)"
  json=$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 20 -H 'Accept: application/vnd.github+json' "$api") ||
    die "$EX_ERROR" "$(t err_update_check)"
  tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$json" | head -n1)
  latest=${tag#v}
  [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$EX_ERROR" "$(t err_update_check)"
  if ! version_gt "$latest" "$cur"; then
    if [[ $OPT_JSON == 1 ]]; then printf '{%s,%s,"update_available":false}\n' "$(json_kv current "$cur")" "$(json_kv latest "$latest")"; else ok_line "$(t upd_current "$cur")"; fi
    # Still make sure the local build matches the current Input Leap/Qt.
    is_installed && do_install update
    return 0
  fi
  if [[ $OPT_JSON == 1 ]]; then
    printf '{%s,%s,"update_available":true}\n' "$(json_kv current "$cur")" "$(json_kv latest "$latest")"
    return 0
  fi
  info "$(t upd_available "$cur" "$latest")"
  confirm "$(t ask_update "$latest")" || die "$EX_ERROR" "$(t cancelled)"

  local tmp base="https://github.com/$ILNF_REPO/releases/download/$tag"
  local tarball="$ILNF_NAME-$latest.tar.gz"
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf -- '$tmp'" EXIT
  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/$tarball" "$base/$tarball" ||
    ! curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
    die "$EX_ERROR" "$(t err_download)"
  fi
  (cd "$tmp" && grep -E " [*]?$tarball\$" SHA256SUMS | sha256sum -c --status -) ||
    die "$EX_CONFLICT" "$(t err_checksum)"
  ok_line "$(t upd_verified)"
  # Reject archives with absolute paths or parent traversal before extracting.
  local listing
  listing=$(tar -tzf "$tmp/$tarball") || die "$EX_ERROR" "$(t err_download)"
  if grep -qE '(^/|(^|/)\.\.(/|$))' <<<"$listing"; then die "$EX_CONFLICT" "$(t err_checksum)"; fi
  mkdir "$tmp/src"
  tar -xzf "$tmp/$tarball" -C "$tmp/src" --no-same-owner --no-same-permissions || die "$EX_ERROR" "$(t err_download)"
  local root
  root=$(find "$tmp/src" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [[ -x $root/bin/$ILNF_NAME ]] || die "$EX_ERROR" "$(t err_download)"
  # The new version installs itself; on failure the current installation is untouched
  # because the library is only replaced after it has been built and validated.
  local -a args=(install --non-interactive)
  [[ $OPT_YES == 1 ]] && args+=(--yes)
  [[ $OPT_VERBOSE == 1 ]] && args+=(--verbose)
  "$root/bin/$ILNF_NAME" "${args[@]}" || die "$EX_ERROR" "$(t err_update_install)"
  ok_line "$(t upd_done "$latest")"
}
