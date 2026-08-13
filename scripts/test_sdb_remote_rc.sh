#!/usr/bin/env bash
# Integration self-test: a constructed remote rc=37 must be red on the host.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
# shellcheck source=sdb_remote_rc.sh
source "$SCRIPT_DIR/sdb_remote_rc.sh"

sdb connect "$TARGET" </dev/null
sdb_serial="$(
    sdb devices | awk -v target="$TARGET" '
        $2 == "device" && ($1 == target || index($1, target ":") == 1) { print $1 }
    '
)"
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]] || {
    echo "SELFTEST_FAIL expected exactly one SDB serial target=$TARGET" >&2
    exit 2
}

constructed_output=""
constructed_rc=0
constructed_output="$(
    sdb_remote_capture "$sdb_serial" \
        "printf 'constructed_remote_failure=YES\\n'; exit 37"
)" || constructed_rc=$?
printf '%s\n' "$constructed_output"
printf 'constructed_remote_rc=%s\n' "$constructed_rc"
[[ "$constructed_rc" -eq 37 ]] || {
    echo "SELFTEST_FAIL expected remote rc=37" >&2
    exit 3
}
echo "SDB_REMOTE_RC_SELFTEST_PASS"
