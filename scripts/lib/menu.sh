# shellcheck shell=bash
# Text menu shown when the CLI runs without arguments on a terminal.
# SPDX-License-Identifier: MIT

run_menu() {
  local choice
  while true; do
    echo
    printf '%s%s%s %s\n\n' "$C_BLD" "Input Leap Network Filter" "$C_RST" "$(ilnf_version)"
    t menu_items
    echo
    read -r -p "> " choice || return 0
    echo
    # Each action runs in a subshell so an error returns to the menu.
    case $choice in
      1) (do_install install) || true ;;
      2) (confirm "$(t ask_uninstall)" && do_uninstall) || true ;;
      3) (do_update) || true ;;
      4) (do_enable) || true ;;
      5) (do_disable) || true ;;
      6) (do_status) || true ;;
      7) (do_interfaces) || true ;;
      8) (do_preview) || true ;;
      9) (do_doctor) || true ;;
      10) (do_repair) || true ;;
      11) (do_configure) || true ;;
      12) (do_rollback) || true ;;
      0 | q | "") return 0 ;;
      *) warn "$(t err_invalid_choice)" ;;
    esac
  done
}
