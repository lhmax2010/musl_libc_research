#!/usr/bin/env bash
# Formal ffmpeg GBS build entry with source and extracted-artifact gates.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
REVIEW_FILE="${FFMPEG_REVIEW_FILE:-$ROOT_DIR/results/logs/ffmpeg-source-review.md}"
SPEC_FILE="$ROOT_DIR/packaging/ffmpeg-musl-demo.spec"
CONFIG="${GBS_CONFIG:-$ROOT_DIR/config/gbs_llvm.conf}"
GBS_ROOT="${GBS_ROOT:-$ROOT_DIR/tmp/GBS-ROOT-TIZEN-UNIFIED-LLVM-CODES}"
LOG_DIR="$ROOT_DIR/results/logs"
RPM_DIR="$ROOT_DIR/results/rpms"
LOG_FILE="$LOG_DIR/gbs-build-ffmpeg.log"
EVIDENCE_DIR="$LOG_DIR/ffmpeg-build-evidence"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-demo-rpm.XXXXXXXX")"
trap 'rm -rf -- "$EXTRACT_DIR"' EXIT HUP INT TERM

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
    echo "ERROR package spec missing: $SPEC_FILE" >&2
    exit 2
}
[[ -f "$CONFIG" ]] || { echo "ERROR GBS config missing: $CONFIG" >&2; exit 2; }

for tool in awk cpio find gbs git grep gzip rpm2cpio sha256sum sort tee; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    }
done

mkdir -p "$LOG_DIR" "$RPM_DIR" "$EVIDENCE_DIR" "$GBS_ROOT"
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
    awk '$1 ~ /^Source[0-9]+:$/ { key=$1; sub(/:$/, "", key); print key "|" $2 }' "$SPEC_FILE"
)
[[ "$source_count" -gt 0 ]] || {
    echo "SOURCE_PREFLIGHT_FAIL no Source declarations" | tee -a "$LOG_FILE" >&2
    exit 8
}
if (( ${#missing_sources[@]} > 0 )); then
    echo "SOURCE_PREFLIGHT_FAIL missing_count=${#missing_sources[@]}" | tee -a "$LOG_FILE" >&2
    printf 'source_preflight.missing=%s\n' "${missing_sources[@]}" | tee -a "$LOG_FILE" >&2
    exit 8
fi
echo "SOURCE_PREFLIGHT_PASS count=$source_count" | tee -a "$LOG_FILE"

ffmpeg_archive="$ROOT_DIR/packaging/ffmpeg-tizen-src.tar.gz.frozen"
ffmpeg_hash_file="$ROOT_DIR/packaging/ffmpeg-tizen-src.sha256"
ffmpeg_commit_file="$ROOT_DIR/packaging/ffmpeg-tizen.commit"
expected_hash="$(awk 'NF {print tolower($1); exit}' "$ffmpeg_hash_file")"
actual_hash="$(sha256sum "$ffmpeg_archive" | awk '{print tolower($1)}')"
expected_commit="$(awk 'NF {print tolower($1); exit}' "$ffmpeg_commit_file")"
embedded_commit="$(git get-tar-commit-id < <(gzip -cd "$ffmpeg_archive"))"
[[ "$actual_hash" == "$expected_hash" ]] || {
    echo "SOURCE0_HOST_GATE_FAIL sha256 expected=$expected_hash actual=$actual_hash" | tee -a "$LOG_FILE" >&2
    exit 9
}
[[ "$embedded_commit" == "$expected_commit" ]] || {
    echo "SOURCE0_HOST_GATE_FAIL commit expected=$expected_commit actual=$embedded_commit" | tee -a "$LOG_FILE" >&2
    exit 9
}
echo "SOURCE0_HOST_GATE_PASS sha256=$actual_hash commit=$embedded_commit" | tee -a "$LOG_FILE"

cd "$ROOT_DIR"
echo "command=gbs -c $CONFIG build -A armv7l --include-all -B $GBS_ROOT --spec ffmpeg-musl-demo.spec" | tee -a "$LOG_FILE"
gbs -c "$CONFIG" build -A armv7l --include-all -B "$GBS_ROOT" \
    --spec ffmpeg-musl-demo.spec 2>&1 | tee -a "$LOG_FILE"

rpm_path="$(
    find "$GBS_ROOT/local/repos" -type f -name 'ffmpeg-musl-demo-*.armv7l.rpm' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr \
        | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
)"
[[ -n "$rpm_path" && -f "$rpm_path" ]] || {
    echo "ERROR build completed but ffmpeg-musl-demo RPM was not found" | tee -a "$LOG_FILE" >&2
    exit 3
}
rpm_copy="$RPM_DIR/$(basename "$rpm_path")"
cp -p -- "$rpm_path" "$rpm_copy"

(
    cd "$EXTRACT_DIR"
    rpm2cpio "$rpm_copy" | cpio --quiet -idm
)
payload="$EXTRACT_DIR/opt/usr/ffmpeg-demo"
[[ -d "$payload/bin" && -d "$payload/share" ]] || {
    echo "ERROR RPM private payload is incomplete" | tee -a "$LOG_FILE" >&2
    exit 4
}
(
    cd "$payload"
    sha256sum -c share/artifacts.sha256
) | tee -a "$LOG_FILE"
rm -rf -- "$EVIDENCE_DIR"
mkdir -p "$EVIDENCE_DIR"
cp -p -- "$payload/share/"* "$EVIDENCE_DIR/"
cp -p -- "$payload/share/artifacts.sha256" "$ROOT_DIR/results/artifacts-ffmpeg.sha256"

rpm_sha256="$(sha256sum "$rpm_copy" | awk '{print $1}')"
echo "rpm=$rpm_copy" | tee -a "$LOG_FILE"
echo "rpm_sha256=$rpm_sha256" | tee -a "$LOG_FILE"
echo "evidence=$EVIDENCE_DIR" | tee -a "$LOG_FILE"
echo "BUILD_GBS_FFMPEG_PASS" | tee -a "$LOG_FILE"
