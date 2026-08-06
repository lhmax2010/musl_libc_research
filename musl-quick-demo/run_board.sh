#!/usr/bin/env bash
# Compatibility entry point for the canonical board runner.
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$SCRIPT_DIR/../scripts/run_board.sh" "$@"
