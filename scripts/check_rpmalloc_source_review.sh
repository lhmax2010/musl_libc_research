#!/usr/bin/env bash
# Fail-closed physical gate for the rpmalloc source review.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
REVIEW_FILE="$ROOT_DIR/results/logs/rpmalloc-source-review.md"
APPROVED_LINE='- [x] FatTank verified the frozen rpmalloc digest and archived corroborating records.'

if [[ ! -f "$REVIEW_FILE" ]]; then
    printf 'RPMALLOC_BUILD_BLOCKED: review file missing: %s\n' "$REVIEW_FILE" >&2
    exit 7
fi

approved_count="$(grep -Fxc -- "$APPROVED_LINE" "$REVIEW_FILE" || true)"
if [[ "$approved_count" != 1 ]]; then
    printf '%s\n' \
        'RPMALLOC_BUILD_BLOCKED: FatTank source review checkbox is not checked.' \
        "Expected exactly once: $APPROVED_LINE" >&2
    exit 7
fi

printf 'RPMALLOC_SOURCE_REVIEW_GATE_PASS: %s\n' "$REVIEW_FILE"
