#!/usr/bin/env bash
# Host-side GBS build wrapper. Captures logs and extracts evidence from the RPM.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG="${GBS_CONFIG:-$ROOT_DIR/config/gbs_llvm.conf}"
GBS_ROOT="${GBS_ROOT:-$ROOT_DIR/tmp/GBS-ROOT-TIZEN-UNIFIED-LLVM-CODES}"
LOG_DIR="$ROOT_DIR/results/logs"
RPM_DIR="$ROOT_DIR/results/rpms"
LOG_FILE="$LOG_DIR/gbs-build-mimalloc.log"
REVIEW_FILE="$LOG_DIR/mimalloc-source-review.md"

for tool in cpio gbs rpm2cpio; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    fi
done
[[ -f "$CONFIG" ]] || { echo "ERROR GBS config not found: $CONFIG" >&2; exit 2; }
[[ -f "$REVIEW_FILE" ]] || {
    echo "MIMALLOC_BUILD_BLOCKED source review file missing: $REVIEW_FILE" >&2
    exit 7
}
if ! grep -Fqx -- '- [x] FatTank verified the frozen mimalloc digest and archived corroborating records.' "$REVIEW_FILE"; then
    echo "MIMALLOC_BUILD_BLOCKED FatTank source digest review is not checked in $REVIEW_FILE" >&2
    echo "rerun=scripts/build_gbs.sh" >&2
    exit 7
fi

mkdir -p "$LOG_DIR" "$RPM_DIR" "$GBS_ROOT"
cd "$ROOT_DIR"

echo "command=gbs -c $CONFIG build -A armv7l --include-all -B $GBS_ROOT" | tee "$LOG_FILE"
gbs -c "$CONFIG" build -A armv7l --include-all -B "$GBS_ROOT" 2>&1 | tee -a "$LOG_FILE"

rpm_path="$(
    find "$GBS_ROOT/local/repos" -type f \
        -name 'musl-libc-demo-*.armv7l.rpm' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
)"
[[ -n "$rpm_path" && -f "$rpm_path" ]] || {
    echo "ERROR build completed but musl-libc-demo armv7l RPM was not found" | tee -a "$LOG_FILE" >&2
    exit 3
}

rpm_copy="$RPM_DIR/$(basename "$rpm_path")"
cp -p -- "$rpm_path" "$rpm_copy"

extract_member() {
    local member="$1"
    local destination="$2"
    rpm2cpio "$rpm_copy" | cpio --quiet -i --to-stdout ".$member" > "$destination"
    [[ -s "$destination" ]] || {
        echo "ERROR failed to extract $member from $rpm_copy" >&2
        exit 4
    }
}

extract_member "/opt/usr/musl-demo/share/compiler-decision.txt" \
    "$LOG_DIR/compiler-decision-mimalloc.txt"
extract_member "/opt/usr/musl-demo/share/artifacts.sha256" \
    "$ROOT_DIR/results/artifacts-mimalloc.sha256"
extract_member "/opt/usr/musl-demo/share/micro.musl-mi.map" \
    "$LOG_DIR/micro.musl-mi.map"

echo "rpm=$rpm_copy" | tee -a "$LOG_FILE"
echo "compiler_decision=$LOG_DIR/compiler-decision-mimalloc.txt" | tee -a "$LOG_FILE"
echo "BUILD_GBS_PASS" | tee -a "$LOG_FILE"
