#!/usr/bin/env bash
# Formal ffmpeg build entry. Phase 1 is intentionally fail-closed on source review.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
REVIEW_FILE="${FFMPEG_REVIEW_FILE:-$ROOT_DIR/results/logs/ffmpeg-source-review.md}"
SPEC_FILE="$ROOT_DIR/packaging/ffmpeg-musl-demo.spec"

[[ -f "$REVIEW_FILE" ]] || {
    echo "FFMPEG_BUILD_BLOCKED source review file missing: $REVIEW_FILE" >&2
    exit 7
}
if ! grep -Fqx -- \
    '- [x] FatTank verified the frozen Tizen ffmpeg commit and archived provenance.' \
    "$REVIEW_FILE"; then
    echo "FFMPEG_BUILD_BLOCKED frozen commit reviewer sign-off is not checked in $REVIEW_FILE" >&2
    echo "rerun=scripts/build_gbs_ffmpeg.sh" >&2
    exit 7
fi

echo "FFMPEG_SOURCE_REVIEW_PASS"
[[ -f "$SPEC_FILE" ]] || {
    echo "FFMPEG_BUILD_PHASE_PENDING packaging/ffmpeg-musl-demo.spec is created only after source review" >&2
    exit 8
}

echo "ERROR ffmpeg GBS implementation must replace the Phase 1 checkpoint before use" >&2
exit 8
