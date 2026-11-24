#!/usr/bin/env bash
# Convenience entry point: bash install.sh [options]
exec "$(dirname -- "$(readlink -f -- "$0")")/bin/input-leap-network-filter" install "$@"
