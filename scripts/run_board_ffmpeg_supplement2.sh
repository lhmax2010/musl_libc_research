#!/usr/bin/env bash
# Collect only the authorized FFmpeg board size and function-surface supplement.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
: "${SDB_TARGET:?must be set}"
TARGET="$SDB_TARGET"
PRIVATE_ROOT="/opt/usr/ffmpeg-demo"
BIN_DIR="$PRIVATE_ROOT/bin"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/results/results-ffmpeg-supplement2.txt}"
PRIMARY_RESULT="$ROOT_DIR/results/results-ffmpeg.txt"
SUPPLEMENT_RESULT="$ROOT_DIR/results/results-ffmpeg-supplement.txt"
PRIMARY_EXPECTED_SHA256="69784e43a288bdce04c6e9b5d2492f411cf9f2a5d0457fad63734923f85893ce"
SUPPLEMENT_EXPECTED_SHA256="c08c5896b7a85623bae89320f081128ebebfbe383b9110dd086f9d50ab665194"
SIZE_MATRIX="$ROOT_DIR/results/logs/ffmpeg-build-evidence/sizes-matrix.txt"
FUNCTION_SURFACE="$ROOT_DIR/results/logs/ffmpeg-build-evidence/function-surface.txt"

[[ ! -e "$RESULT_FILE" ]] || {
    echo "ERROR raw result already exists and is read-only: $RESULT_FILE" >&2
    exit 2
}
for path in "$PRIMARY_RESULT" "$SUPPLEMENT_RESULT" "$SIZE_MATRIX" "$FUNCTION_SURFACE"; do
    [[ -f "$path" ]] || { echo "ERROR required evidence missing: $path" >&2; exit 2; }
done
for tool in awk diff grep sdb sha256sum stat tee; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR required host tool missing: $tool" >&2; exit 2; }
done

primary_sha256="$(sha256sum "$PRIMARY_RESULT" | awk '{print $1}')"
supplement_sha256="$(sha256sum "$SUPPLEMENT_RESULT" | awk '{print $1}')"
[[ "$primary_sha256" == "$PRIMARY_EXPECTED_SHA256" ]] || {
    echo "ERROR primary result hash changed: $primary_sha256" >&2
    exit 2
}
[[ "$supplement_sha256" == "$SUPPLEMENT_EXPECTED_SHA256" ]] || {
    echo "ERROR first supplement hash changed: $supplement_sha256" >&2
    exit 2
}

mkdir -p "$(dirname -- "$RESULT_FILE")"
touch "$RESULT_FILE"

say() {
    printf '%s\n' "$*" | tee -a "$RESULT_FILE"
}

run_logged() {
    "$@" 2>&1 | tr -d '\r' | tee -a "$RESULT_FILE"
}

run_logged sdb connect "$TARGET"
if [[ -n "${SDB_SERIAL:-}" ]]; then
    sdb_serial="$SDB_SERIAL"
else
    sdb_serial="$(
        sdb devices | awk -v target="$TARGET" '
            $2 == "device" && ($1 == target || index($1, target ":") == 1) {
                print $1
            }
        '
    )"
fi
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]] || {
    say "SUPPLEMENT2_FAIL expected exactly one SDB serial for target=$TARGET"
    exit 2
}

remote_capture() {
    sdb -s "$sdb_serial" shell "$1" </dev/null 2>&1 | tr -d '\r'
}

run_remote() {
    remote_capture "$1" | tee -a "$RESULT_FILE"
}

run_logged sdb -s "$sdb_serial" root on
say "### environment"
say "measurement.mode=supplement2"
say "measurement.scope=size,function"
say "measurement.target=$TARGET"
say "measurement.sdb_serial=$sdb_serial"
say "measurement.start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "primary_result.path=results/results-ffmpeg.txt"
say "primary_result.sha256=$primary_sha256"
say "supplement_result.path=results/results-ffmpeg-supplement.txt"
say "supplement_result.sha256=$supplement_sha256"
say "decode=NOT_RUN reason=authorized_supplement2_scope"
say "startup=NOT_RUN reason=authorized_supplement2_scope"
say "memory=NOT_RUN reason=authorized_supplement2_scope"
run_remote "printf 'loadavg.before='; cat /proc/loadavg; ps -ef | grep -E '[f]fmpeg|[t]imer' || true"
run_remote "set -e; residual=0; for exe in /proc/[0-9]*/exe; do target=\$(readlink \"\$exe\" 2>/dev/null || true); case \"\$target\" in '$BIN_DIR'/ffmpeg.*|'$BIN_DIR'/timer) printf 'residual.before=%s\\n' \"\$target\"; residual=1 ;; esac; done; [ \"\$residual\" -eq 0 ]; echo residual.before=NONE"
run_remote 'set -e; found=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do found=1; echo performance > "$f"; done; [ "$found" -eq 1 ]; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do cpu=${f#/sys/devices/system/cpu/}; cpu=${cpu%%/*}; value=$(cat "$f"); printf "governor.%s=%s\n" "$cpu" "$value"; [ "$value" = performance ]; done'
run_remote 'set -e; for f in /sys/class/thermal/thermal_zone[0-9]*/temp; do zone=${f#/sys/class/thermal/}; zone=${zone%%/*}; value=$(cat "$f"); printf "temperature.before.%s=%s\n" "$zone" "$value"; [ "$value" -le 65000 ]; done'

say "### board size matrix verification"
while IFS=',' read -r variant mode state expected; do
    say "size_host,$variant,$mode,$state,$expected"
    [[ "$state" == stripped ]] || continue
    suffix=""
    [[ "$mode" == gc ]] && suffix=".gc"
    actual="$(remote_capture "stat -c %s '$BIN_DIR/ffmpeg.$variant$suffix'")"
    independent="$(remote_capture "command stat -c %s '$BIN_DIR/ffmpeg.$variant$suffix'")"
    say "size_board,$variant,$mode,$state,$actual"
    say "size_board_independent,$variant,$mode,$state,$independent"
    [[ "$actual" == "$expected" && "$independent" == "$expected" ]] || {
        say "SUPPLEMENT2_FAIL size mismatch variant=$variant mode=$mode expected=$expected actual=$actual independent=$independent"
        exit 8
    }
done < "$SIZE_MATRIX"
say "size_board_verification=PASS"

say "### F2 function surface"
function_output="$(remote_capture "cat '$PRIVATE_ROOT/share/function-surface.txt'")"
printf 'function_surface_begin\n%s\nfunction_surface_end\n' "$function_output" | tee -a "$RESULT_FILE"
if ! diff -u "$FUNCTION_SURFACE" <(printf '%s\n' "$function_output") | tee -a "$RESULT_FILE"; then
    say "SUPPLEMENT2_FAIL function surface differs from build evidence"
    exit 9
fi
for key in strcoll iconv setlocale getaddrinfo; do
    grep -Eq "^$key=(PRESENT|ABSENT)$" <<< "$function_output" || {
        say "SUPPLEMENT2_FAIL function surface missing key=$key"
        exit 9
    }
done
say "function_surface_verification=PASS"

run_remote "set -e; residual=0; for exe in /proc/[0-9]*/exe; do target=\$(readlink \"\$exe\" 2>/dev/null || true); case \"\$target\" in '$BIN_DIR'/ffmpeg.*|'$BIN_DIR'/timer) printf 'residual.after=%s\\n' \"\$target\"; residual=1 ;; esac; done; [ \"\$residual\" -eq 0 ]; echo residual.after=NONE"
run_remote "printf 'loadavg.after='; cat /proc/loadavg"
say "measurement.finish_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "MEASUREMENT_FFMPEG_SUPPLEMENT2_PASS"
