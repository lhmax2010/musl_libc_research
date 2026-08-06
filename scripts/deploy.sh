#!/usr/bin/env bash
# Install the GBS-built RPM and verify the board payload byte-for-byte.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.25}"
RESULTS_DIR="$ROOT_DIR/results"
LOG_DIR="$RESULTS_DIR/logs"
LOG_FILE="$LOG_DIR/deploy.log"
PRIVATE_ROOT="/opt/usr/musl-demo"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musl-demo-rpm.XXXXXXXX")"
trap 'rm -rf -- "$EXTRACT_DIR"' EXIT HUP INT TERM

for tool in cpio diff rpm2cpio sdb sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    fi
done

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

if [[ -n "${RPM_PATH:-}" ]]; then
    rpm_path="$RPM_PATH"
else
    rpm_path="$(
        find "$RESULTS_DIR/rpms" -maxdepth 1 -type f \
            -name 'musl-libc-demo-*.armv7l.rpm' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
fi
[[ -n "$rpm_path" && -f "$rpm_path" ]] || {
    echo "ERROR armv7l RPM not found; set RPM_PATH or run scripts/build_gbs.sh" | tee -a "$LOG_FILE" >&2
    exit 3
}

rpm_base="$(basename "$rpm_path")"
[[ "$rpm_base" =~ ^[A-Za-z0-9._+-]+$ ]] || {
    echo "ERROR unsafe RPM basename: $rpm_base" | tee -a "$LOG_FILE" >&2
    exit 3
}
remote_rpm="/tmp/$rpm_base"

(
    cd "$EXTRACT_DIR"
    rpm2cpio "$rpm_path" | cpio --quiet -idm
)
HOST_PAYLOAD="$EXTRACT_DIR$PRIVATE_ROOT"
[[ -d "$HOST_PAYLOAD/bin" && -f "$HOST_PAYLOAD/share/artifacts.sha256" ]] || {
    echo "ERROR RPM is missing the expected private payload" | tee -a "$LOG_FILE" >&2
    exit 4
}
(
    cd "$HOST_PAYLOAD"
    sha256sum -c share/artifacts.sha256
) | tee -a "$LOG_FILE"
(
    cd "$HOST_PAYLOAD"
    sha256sum bin/* | sort -k2
) > "$EXTRACT_DIR/host-bin.sha256"

run_logged() {
    "$@" 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
}

echo "target=$TARGET" | tee -a "$LOG_FILE"
echo "rpm=$rpm_path" | tee -a "$LOG_FILE"
run_logged sdb connect "$TARGET"
run_logged sdb root on
run_logged sdb push "$rpm_path" "$remote_rpm"

set +e
sdb shell "rpm -Uvh --force '$remote_rpm'" 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
install_rc=${PIPESTATUS[0]}
set -e
if [[ "$install_rc" -ne 0 ]]; then
    echo "DEPLOY_FAIL rpm_install_rc=$install_rc" | tee -a "$LOG_FILE" >&2
    exit "$install_rc"
fi

sdb shell "cd '$PRIVATE_ROOT' && sha256sum -c share/artifacts.sha256" \
    2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
sdb shell "cd '$PRIVATE_ROOT' && sha256sum bin/*" \
    | tr -d '\r' | sort -k2 > "$EXTRACT_DIR/board-bin.sha256"
if ! diff -u "$EXTRACT_DIR/host-bin.sha256" "$EXTRACT_DIR/board-bin.sha256" \
    | tee -a "$LOG_FILE"; then
    echo "DEPLOY_FAIL board binary hashes differ from RPM payload" | tee -a "$LOG_FILE" >&2
    exit 5
fi
echo "binary_hash_comparison=PASS" | tee -a "$LOG_FILE"

for variant in micro.glibc-dyn micro.musl-static micro.musl-dyn; do
    echo "smoke.variant=$variant" | tee -a "$LOG_FILE"
    sdb shell "$PRIVATE_ROOT/bin/$variant" 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
done

echo "DEPLOY_PASS musl-dyn used package interpreter $PRIVATE_ROOT/lib/ld-musl-armhf.so.1" \
    | tee -a "$LOG_FILE"
