#!/usr/bin/env bash
# Build the allocator shootout add-on RPM after the FatTank source gate.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG="${GBS_CONFIG:-$ROOT_DIR/config/gbs_llvm.conf}"
GBS_ROOT="${GBS_ROOT:-$ROOT_DIR/tmp/GBS-ROOT-TIZEN-UNIFIED-LLVM-CODES}"
LOG_DIR="$ROOT_DIR/results/logs"
RPM_DIR="$ROOT_DIR/results/rpms"
LOG_FILE="$LOG_DIR/gbs-build-shootout.log"
SPEC_FILE="$ROOT_DIR/packaging/allocator-shootout.spec"

for tool in awk cpio gbs rpm2cpio; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    }
done
[[ -f "$CONFIG" ]] || { echo "ERROR GBS config missing: $CONFIG" >&2; exit 2; }
[[ -f "$SPEC_FILE" ]] || { echo "ERROR spec missing: $SPEC_FILE" >&2; exit 2; }

# This must be the first state-changing build action.
"$SCRIPT_DIR/check_rpmalloc_source_review.sh"

mkdir -p "$LOG_DIR" "$RPM_DIR" "$GBS_ROOT"
: > "$LOG_FILE"
echo "rpmalloc_review_commit=23a76a0f95f2ad58a7793de70afed12fdd6210a8" | tee -a "$LOG_FILE"
"$SCRIPT_DIR/check_rpmalloc_source_review.sh" 2>&1 | tee -a "$LOG_FILE"

source_count=0
missing_sources=()
while IFS='|' read -r source_key source_name; do
    [[ -n "$source_key" && -n "$source_name" ]] || continue
    source_count=$((source_count + 1))
    if [[ -f "$ROOT_DIR/packaging/$source_name" ]]; then
        echo "source_preflight.$source_key=PASS name=$source_name" | tee -a "$LOG_FILE"
    else
        missing_sources+=("$source_key:$source_name")
        echo "source_preflight.$source_key=MISSING name=$source_name" | tee -a "$LOG_FILE"
    fi
done < <(
    awk '$1 ~ /^Source[0-9]+:$/ { key=$1; sub(/:$/, "", key); print key "|" $2 }' "$SPEC_FILE"
)
[[ "$source_count" -gt 0 ]] || {
    echo "SOURCE_PREFLIGHT_FAIL no SourceN declarations" | tee -a "$LOG_FILE" >&2
    exit 8
}
if (( ${#missing_sources[@]} > 0 )); then
    printf 'SOURCE_PREFLIGHT_FAIL missing=%s\n' "${missing_sources[*]}" | tee -a "$LOG_FILE" >&2
    exit 8
fi
echo "SOURCE_PREFLIGHT_PASS count=$source_count" | tee -a "$LOG_FILE"

command=(gbs -c "$CONFIG" build -A armv7l --include-all -B "$GBS_ROOT" --spec allocator-shootout.spec)
printf 'command=' | tee -a "$LOG_FILE"
printf '%q ' "${command[@]}" | tee -a "$LOG_FILE"
printf '\n' | tee -a "$LOG_FILE"
cd "$ROOT_DIR"
"${command[@]}" 2>&1 | tee -a "$LOG_FILE"

rpm_path="$(
    find "$GBS_ROOT/local/repos" -type f \
        -name 'allocator-shootout-demo-*.armv7l.rpm' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
)"
[[ -n "$rpm_path" && -f "$rpm_path" ]] || {
    echo "ERROR allocator shootout RPM not found" | tee -a "$LOG_FILE" >&2
    exit 3
}
rpm_copy="$RPM_DIR/$(basename "$rpm_path")"
cp -p -- "$rpm_path" "$rpm_copy"

extract_member() {
    local member="$1"
    local destination="$2"
    rpm2cpio "$rpm_copy" | cpio --quiet -i --to-stdout ".$member" > "$destination"
    [[ -s "$destination" ]] || {
        echo "ERROR failed to extract $member" >&2
        exit 4
    }
}

extract_member /opt/usr/musl-demo/share/shootout-compiler-decision.txt \
    "$LOG_DIR/compiler-decision-shootout.txt"
extract_member /opt/usr/musl-demo/share/shootout-s6-status.txt \
    "$LOG_DIR/shootout-s6-status.txt"
extract_member /opt/usr/musl-demo/share/shootout-artifacts.sha256 \
    "$ROOT_DIR/results/artifacts-shootout.sha256"
extract_member /opt/usr/musl-demo/share/micro.musl-rp.map \
    "$LOG_DIR/micro.musl-rp.map"
if rpm2cpio "$rpm_copy" | cpio --quiet -it 2>/dev/null \
    | grep -Fxq './opt/usr/musl-demo/share/micro.musl-scudo.map'; then
    extract_member /opt/usr/musl-demo/share/micro.musl-scudo.map \
        "$LOG_DIR/micro.musl-scudo.map"
fi
sha256sum "$rpm_copy" > "$rpm_copy.sha256"
echo "rpm=$rpm_copy" | tee -a "$LOG_FILE"
cat "$LOG_DIR/shootout-s6-status.txt" | tee -a "$LOG_FILE"
echo "BUILD_GBS_SHOOTOUT_PASS" | tee -a "$LOG_FILE"
