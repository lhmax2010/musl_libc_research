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
REVIEW_FILE="${MIMALLOC_REVIEW_FILE:-$LOG_DIR/mimalloc-source-review.md}"
SPEC_FILE="$ROOT_DIR/packaging/musl-libc-demo.spec"

for tool in awk cpio gbs rpm2cpio; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    fi
done
[[ -f "$CONFIG" ]] || { echo "ERROR GBS config not found: $CONFIG" >&2; exit 2; }
[[ -f "$SPEC_FILE" ]] || { echo "ERROR package spec not found: $SPEC_FILE" >&2; exit 2; }
[[ -f "$REVIEW_FILE" ]] || {
    echo "MIMALLOC_BUILD_BLOCKED source review file missing: $REVIEW_FILE" >&2
    exit 7
}
if ! grep -Eq -- '^- \[x\] (FatTank verified the frozen mimalloc digest and archived corroborating records\.|Reviewer independently verified the frozen source digests against every cited upstream record\.)$' "$REVIEW_FILE"; then
    echo "MIMALLOC_BUILD_BLOCKED source digest reviewer sign-off is not checked in $REVIEW_FILE" >&2
    echo "rerun=scripts/build_gbs.sh" >&2
    exit 7
fi

mkdir -p "$LOG_DIR" "$RPM_DIR" "$GBS_ROOT"
cd "$ROOT_DIR"

: > "$LOG_FILE"
source_count=0
missing_sources=()
while IFS='|' read -r source_key source_name; do
    [[ -n "$source_key" && -n "$source_name" ]] || continue
    source_count=$((source_count + 1))
    source_path="$ROOT_DIR/packaging/$source_name"
    if [[ -f "$source_path" ]]; then
        echo "source_preflight.$source_key=PASS name=$source_name" | tee -a "$LOG_FILE"
    else
        missing_sources+=("$source_key:$source_name")
        echo "source_preflight.$source_key=MISSING name=$source_name" | tee -a "$LOG_FILE"
    fi
done < <(
    awk '
        $1 ~ /^Source[0-9]+:$/ {
            key=$1
            sub(/:$/, "", key)
            print key "|" $2
        }
    ' "$SPEC_FILE"
)
[[ "$source_count" -gt 0 ]] || {
    echo "SOURCE_PREFLIGHT_FAIL no SourceN declarations found in $SPEC_FILE" | tee -a "$LOG_FILE" >&2
    exit 8
}
if (( ${#missing_sources[@]} > 0 )); then
    echo "SOURCE_PREFLIGHT_FAIL missing_count=${#missing_sources[@]}" | tee -a "$LOG_FILE" >&2
    printf 'source_preflight.missing=%s\n' "${missing_sources[@]}" | tee -a "$LOG_FILE" >&2
    exit 8
fi
echo "SOURCE_PREFLIGHT_PASS count=$source_count" | tee -a "$LOG_FILE"

echo "command=gbs -c $CONFIG build -A armv7l --include-all -B $GBS_ROOT" | tee -a "$LOG_FILE"
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
