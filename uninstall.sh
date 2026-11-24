#!/usr/bin/env bash
# Convenience entry point: bash uninstall.sh [--purge] [options]
exec "$(dirname -- "$(readlink -f -- "$0")")/bin/input-leap-network-filter" uninstall "$@"
