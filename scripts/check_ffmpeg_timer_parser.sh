#!/usr/bin/env bash
# Exercise the strict timer parser against one board capture and synthetic cases.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/results/logs/ffmpeg-timer-parser-selfcheck.log}"
PRIVATE_ROOT="/opt/usr/ffmpeg-demo"

# shellcheck source=scripts/ffmpeg_timer_parser.sh
source "$SCRIPT_DIR/ffmpeg_timer_parser.sh"

mkdir -p "$(dirname -- "$LOG_FILE")"
: > "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

sdb connect "$TARGET" 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
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
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]]
log "target=$TARGET"
log "sdb_serial=$sdb_serial"

real_output="$(
    sdb -s "$sdb_serial" shell \
        "'$PRIVATE_ROOT/bin/timer' '$PRIVATE_ROOT/bin/ffmpeg.F1' -version; rc=\$?; printf 'timer_remote_rc=%s\\n' \"\$rc\"; if [ \"\$rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi" \
        </dev/null 2>&1 | tr -d '\r'
)"
printf 'real_output_begin\n%s\nreal_output_end\n' "$real_output" | tee -a "$LOG_FILE"
real_value="$(ffmpeg_timer_value <<< "$real_output")" || {
    log "real_capture=FAIL"
    exit 1
}
[[ "$real_value" =~ ^[0-9]+$ ]]
[[ "$(grep -Ec '^[0-9]+$' <<< "$real_output")" -eq 1 ]]
log "real_capture=PASS extracted=$real_value"

no_number=$'ffmpeg version 8.0.1\nsample_end=OK'
if ffmpeg_timer_value <<< "$no_number" >/dev/null; then
    log "negative.no_decimal_line=FAIL"
    exit 1
fi
log "negative.no_decimal_line=PASS result=INVALID"

two_numbers=$'123456\n789012\nsample_end=OK'
if ffmpeg_timer_value <<< "$two_numbers" >/dev/null; then
    log "negative.two_decimal_lines=FAIL"
    exit 1
fi
log "negative.two_decimal_lines=PASS result=INVALID"

micro_value="$(ffmpeg_timer_value <<< '42424242')"
[[ "$micro_value" == 42424242 ]]
log "compat.micro_single_decimal=PASS extracted=$micro_value"
log "TIMER_PARSER_SELFCHECK_PASS"
