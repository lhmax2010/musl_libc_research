#!/usr/bin/env bash
# Deploy the frozen release-2 baseline plus shootout add-on and verify hashes.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
BASE_RPM="$ROOT_DIR/results/rpms/musl-libc-demo-1.0.0-2.armv7l.rpm"
ADDON_RPM="$ROOT_DIR/results/rpms/allocator-shootout-demo-1.0.0-1.armv7l.rpm"
EXPECTED_BASE_RPM_SHA256="f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead"
PRIVATE_ROOT="/opt/usr/musl-demo"
LOG_FILE="$ROOT_DIR/results/logs/deploy-shootout.log"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-shootout.XXXXXXXX")"
trap 'rm -rf -- "$EXTRACT_DIR"' EXIT HUP INT TERM

for tool in awk cpio diff rpm2cpio sdb sha256sum sort tee; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR missing host tool: $tool" >&2; exit 2; }
done
for rpm_path in "$BASE_RPM" "$ADDON_RPM"; do
    [[ -f "$rpm_path" ]] || { echo "ERROR RPM missing: $rpm_path" >&2; exit 2; }
done
base_sha256="$(sha256sum "$BASE_RPM" | awk '{print $1}')"
[[ "$base_sha256" == "$EXPECTED_BASE_RPM_SHA256" ]] || {
    echo "ERROR release-2 baseline RPM changed expected=$EXPECTED_BASE_RPM_SHA256 actual=$base_sha256" >&2
    exit 3
}

mkdir -p "$(dirname -- "$LOG_FILE")"
: > "$LOG_FILE"
log() { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }
run_logged() { "$@" </dev/null 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"; }

run_logged sdb connect "$TARGET"
sdb_serial="$(
    sdb devices | awk -v target="$TARGET" '
        $2 == "device" && ($1 == target || index($1, target ":") == 1) { print $1 }
    '
)"
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]] || {
    log "DEPLOY_FAIL expected exactly one SDB serial for target=$TARGET"
    exit 3
}
remote_capture() { sdb -s "$sdb_serial" shell "$1" </dev/null 2>&1 | tr -d '\r'; }
run_remote() { remote_capture "$1" | tee -a "$LOG_FILE"; }
run_logged sdb -s "$sdb_serial" root on

log "target=$TARGET"
log "sdb_serial=$sdb_serial"
log "base_rpm_sha256=$base_sha256"
log "addon_rpm_sha256=$(sha256sum "$ADDON_RPM" | awk '{print $1}')"
log "### board identity gate"
identity="$(remote_capture "uname -r; cat /etc/os-release | head -4")"
printf '%s\n' "$identity" | tee -a "$LOG_FILE"
grep -qi 'rpi4' <<< "$identity" || { log "DEPLOY_FAIL board kernel does not contain rpi4"; exit 4; }
grep -qi 'Tizen' <<< "$identity" || { log "DEPLOY_FAIL os-release is not Tizen"; exit 4; }
grep -Eqi 'unified|dev' <<< "$identity" || { log "DEPLOY_FAIL os-release is not unified(dev)"; exit 4; }
log "gate.board_identity=PASS"

for rpm_path in "$BASE_RPM" "$ADDON_RPM"; do
    rpm_base="$(basename "$rpm_path")"
    remote_rpm="/tmp/$rpm_base"
    run_logged sdb -s "$sdb_serial" push "$rpm_path" "$remote_rpm"
    run_remote "rpm -Uvh --noplugins --force '$remote_rpm'"
    run_remote "rm -f '$remote_rpm'; test ! -e '$remote_rpm'; echo cleanup.$rpm_base=PASS"
done

mkdir -p "$EXTRACT_DIR/base" "$EXTRACT_DIR/addon"
(
    cd "$EXTRACT_DIR/base"
    rpm2cpio "$BASE_RPM" | cpio --quiet -idm
)
(
    cd "$EXTRACT_DIR/addon"
    rpm2cpio "$ADDON_RPM" | cpio --quiet -idm
)
{
    cd "$EXTRACT_DIR/base$PRIVATE_ROOT"
    sha256sum bin/* lib/libc.so
    cd "$EXTRACT_DIR/addon$PRIVATE_ROOT"
    sha256sum bin/*
} | sed "s#  .*/opt/usr/musl-demo/#  #" | sort -k2 > "$EXTRACT_DIR/host.sha256"
remote_capture "cd '$PRIVATE_ROOT' && sha256sum bin/micro.glibc-dyn bin/micro.musl-static bin/micro.musl-dyn bin/micro.musl-mi bin/micro.musl-rp bin/micro.musl-scudo bin/timer lib/libc.so" \
    | sort -k2 > "$EXTRACT_DIR/board.sha256"
cat "$EXTRACT_DIR/host.sha256" | sed 's/^/host_hash=/' | tee -a "$LOG_FILE"
cat "$EXTRACT_DIR/board.sha256" | sed 's/^/board_hash=/' | tee -a "$LOG_FILE"
diff -u "$EXTRACT_DIR/host.sha256" "$EXTRACT_DIR/board.sha256" | tee -a "$LOG_FILE"
log "gate.host_board_hashes=PASS"

for variant in micro.glibc-dyn micro.musl-static micro.musl-mi micro.musl-rp micro.musl-scudo; do
    run_remote "'$PRIVATE_ROOT/bin/$variant'; rc=\$?; printf 'smoke.variant=$variant,rc=%s\n' \"\$rc\"; [ \"\$rc\" -eq 0 ]"
done
run_remote "'$PRIVATE_ROOT/bin/micro.musl-dyn'; rc=\$?; printf 'smoke.variant=micro.musl-dyn,loader=$PRIVATE_ROOT/lib/ld-musl-arm.so.1,rc=%s\n' \"\$rc\"; [ \"\$rc\" -eq 0 ]"
run_remote "MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0 '$PRIVATE_ROOT/bin/micro.musl-mi'; rc=\$?; printf 'smoke.variant=S4,env=MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0,rc=%s\n' \"\$rc\"; [ \"\$rc\" -eq 0 ]"
for variant in micro.glibc-dyn micro.musl-static micro.musl-mi micro.musl-rp micro.musl-scudo; do
    run_remote "'$PRIVATE_ROOT/bin/$variant' malloc 1 1000; rc=\$?; printf 'allocator_smoke.variant=$variant,rc=%s\n' \"\$rc\"; [ \"\$rc\" -eq 0 ]"
done
run_remote "MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0 '$PRIVATE_ROOT/bin/micro.musl-mi' malloc 1 1000; rc=\$?; printf 'allocator_smoke.variant=S4,env=MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0,rc=%s\n' \"\$rc\"; [ \"\$rc\" -eq 0 ]"
log "gate.s3_s4_same_binary=PASS path=$PRIVATE_ROOT/bin/micro.musl-mi"
log "DEPLOY_SHOOTOUT_PASS"
