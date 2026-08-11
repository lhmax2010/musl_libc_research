#!/usr/bin/env bash
# Measure the three-way FFmpeg H.264 software-decode island on one Tizen board.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
RUN_MODE="${RUN_MODE:-full}"
DECODE_REPS="${DECODE_REPS:-10}"
STARTUP_REPS="${STARTUP_REPS:-30}"
MEM_REPS="${MEM_REPS:-3}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
PRIVATE_ROOT="/opt/usr/ffmpeg-demo"
BIN_DIR="$PRIVATE_ROOT/bin"
CLIP="$PRIVATE_ROOT/data/testclip.mp4"
PRIMARY_RESULT="$ROOT_DIR/results/results-ffmpeg.txt"
PRIMARY_EXPECTED_SHA256="e1c8378ed3639eb274fb2eefe25a791142ee2bf427b17565aa367a03e93451f6"
if [[ -z "${RESULT_FILE:-}" ]]; then
    if [[ "$RUN_MODE" == supplement ]]; then
        RESULT_FILE="$ROOT_DIR/results/results-ffmpeg-supplement.txt"
    else
        RESULT_FILE="$PRIMARY_RESULT"
    fi
fi
CLIP_HASH_FILE="$ROOT_DIR/packaging/ffmpeg-testclip.sha256"
SIZE_MATRIX="$ROOT_DIR/results/logs/ffmpeg-build-evidence/sizes-matrix.txt"
CONFIGURE_COMMANDS="$ROOT_DIR/results/logs/ffmpeg-build-evidence/ffmpeg-configure-commands.txt"
CONFIGURE_EQUIVALENCE="$ROOT_DIR/results/logs/ffmpeg-build-evidence/configure-equivalence.txt"

# shellcheck source=scripts/ffmpeg_timer_parser.sh
source "$SCRIPT_DIR/ffmpeg_timer_parser.sh"

[[ "$RUN_MODE" == full || "$RUN_MODE" == supplement ]] || {
    echo "ERROR RUN_MODE must be full or supplement" >&2
    exit 2
}

for value in "$DECODE_REPS" "$STARTUP_REPS" "$MEM_REPS" "$COOLDOWN_SECONDS"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "ERROR repetition/delay values must be integers" >&2; exit 2; }
done
(( DECODE_REPS >= 10 && STARTUP_REPS == 30 && MEM_REPS == 3 )) || {
    echo "ERROR frozen sample counts require decode>=10 startup=30 mem=3" >&2
    exit 2
}
[[ ! -e "$RESULT_FILE" ]] || {
    echo "ERROR raw result already exists and is read-only: $RESULT_FILE" >&2
    exit 2
}
for path in "$CLIP_HASH_FILE" "$SIZE_MATRIX" "$CONFIGURE_COMMANDS" "$CONFIGURE_EQUIVALENCE"; do
    [[ -f "$path" ]] || { echo "ERROR required evidence missing: $path" >&2; exit 2; }
done
if [[ "$RUN_MODE" == supplement ]]; then
    [[ -f "$PRIMARY_RESULT" ]] || { echo "ERROR primary result missing: $PRIMARY_RESULT" >&2; exit 2; }
    primary_actual_sha256="$(sha256sum "$PRIMARY_RESULT" | awk '{print $1}')"
    [[ "$primary_actual_sha256" == "$PRIMARY_EXPECTED_SHA256" ]] || {
        echo "ERROR primary result hash changed: $primary_actual_sha256" >&2
        exit 2
    }
fi
for tool in awk grep sdb sed sha256sum sort stat tee; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR required host tool missing: $tool" >&2; exit 2; }
done

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
    say "MEASUREMENT_FAIL expected exactly one SDB serial for target=$TARGET"
    exit 2
}

remote_capture() {
    sdb -s "$sdb_serial" shell "$1" 2>&1 | tr -d '\r'
}

run_remote() {
    remote_capture "$1" | tee -a "$RESULT_FILE"
}

run_logged sdb -s "$sdb_serial" root on

expected_clip_hash="$(awk 'NF && $1 !~ /^#/ {print tolower($1); exit}' "$CLIP_HASH_FILE")"
expected_clip_name="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$CLIP_HASH_FILE")"
[[ "$expected_clip_hash" =~ ^[0-9a-f]{64}$ ]] || { say "MEASUREMENT_FAIL invalid clip freeze"; exit 3; }

say "### environment"
say "measurement.target=$TARGET"
say "measurement.sdb_serial=$sdb_serial"
say "measurement.mode=$RUN_MODE"
say "measurement.start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "measurement.decode_reps=$DECODE_REPS"
say "measurement.startup_reps=$STARTUP_REPS"
say "measurement.mem_reps=$MEM_REPS"
say "measurement.cooldown_seconds=$COOLDOWN_SECONDS"
say "measurement.temperature_limit_c=65"
say "measurement.sample_sentinel=required"
say "clip.frozen_name=$expected_clip_name"
say "clip.frozen_sha256=$expected_clip_hash"
say "decode.command.template=ffmpeg.Fx -nostdin -hide_banner -v info -c:v h264 -i $CLIP -map 0:v:0 -an -t 30 -f null - -benchmark"
say "memory.command.template=ffmpeg.Fx -nostdin -hide_banner -v info -re -c:v h264 -i $CLIP -map 0:v:0 -an -t 30 -f null - -benchmark"
say "configure.commands.sha256=$(sha256sum "$CONFIGURE_COMMANDS" | awk '{print $1}')"
say "configure.equivalence.sha256=$(sha256sum "$CONFIGURE_EQUIVALENCE" | awk '{print $1}')"
if [[ "$RUN_MODE" == supplement ]]; then
    say "primary_result.path=results/results-ffmpeg.txt"
    say "primary_result.sha256=$primary_actual_sha256"
    say "decode=NOT_RUN reason=authorized_supplement_preserves_primary_decode"
fi
run_remote "uname -a"
run_remote "printf 'loadavg.before='; cat /proc/loadavg; ps -ef | grep -E '[f]fmpeg|[t]imer' || true"

run_remote "set -e; test -f '$CLIP'; actual=\$(sha256sum '$CLIP' | awk '{print \$1}'); printf 'clip.board_sha256=%s\\n' \"\$actual\"; [ \"\$actual\" = '$expected_clip_hash' ]"
for variant in F1 F2 F3; do
    run_remote "test -x '$BIN_DIR/ffmpeg.$variant' && echo binary.ffmpeg.$variant=present"
done
run_remote "test -x '$BIN_DIR/timer' && echo binary.timer=present"

assert_no_residual() {
    local phase="$1"
    run_remote "set -e; residual=0; for exe in /proc/[0-9]*/exe; do target=\$(readlink \"\$exe\" 2>/dev/null || true); case \"\$target\" in '$BIN_DIR'/ffmpeg.*|'$BIN_DIR'/timer) printf 'residual.$phase=%s\\n' \"\$target\"; residual=1 ;; esac; done; [ \"\$residual\" -eq 0 ]; echo residual.$phase=NONE"
}

assert_no_residual before
say "### governor"
run_remote 'set -e; found=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do found=1; echo performance > "$f"; done; [ "$found" -eq 1 ]; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do cpu=${f#/sys/devices/system/cpu/}; cpu=${cpu%%/*}; value=$(cat "$f"); printf "governor.%s=%s\n" "$cpu" "$value"; [ "$value" = performance ]; done'

read_temperature_raw() {
    remote_capture 'set -e; found=0; max=0; for f in /sys/class/thermal/thermal_zone[0-9]*/temp; do found=1; value=$(cat "$f"); case "$value" in *[!0-9]*|"") exit 3 ;; esac; [ "$value" -gt "$max" ] && max=$value; done; [ "$found" -eq 1 ]; echo "$max"'
}

wait_until_cool() {
    local phase="$1"
    local raw
    while :; do
        raw="$(read_temperature_raw)"
        [[ "$raw" =~ ^[0-9]+$ ]] || { say "MEASUREMENT_FAIL temperature unavailable phase=$phase"; exit 4; }
        say "temperature.$phase.raw=$raw"
        if (( raw <= 65000 )); then
            break
        fi
        say "temperature.$phase.wait=ABOVE_65C"
        sleep 10
    done
}

FREQ_INVALID=0
frequency_snapshot() {
    local scope="$1"
    local output cpu cur max
    FREQ_INVALID=0
    output="$(remote_capture 'set -e; found=0; for d in /sys/devices/system/cpu/cpu[0-9]*; do [ -f "$d/cpufreq/scaling_cur_freq" ] || continue; found=1; cpu=${d##*/}; cur=$(cat "$d/cpufreq/scaling_cur_freq"); max=$(cat "$d/cpufreq/scaling_max_freq"); printf "%s,%s,%s\n" "$cpu" "$cur" "$max"; done; [ "$found" -eq 1 ]')"
    while IFS=',' read -r cpu cur max; do
        if [[ ! "$cur" =~ ^[0-9]+$ || ! "$max" =~ ^[0-9]+$ ]]; then
            say "frequency.$scope.$cpu=INVALID"
            FREQ_INVALID=1
        else
            say "frequency.$scope.$cpu.cur=$cur,max=$max"
            (( cur >= max )) || FREQ_INVALID=1
        fi
    done <<< "$output"
}

decode_one() {
    local variant="$1"
    local round="$2"
    local output rc sentinel_count timings utime stime rtime maxrss
    output="$(remote_capture "'$BIN_DIR/ffmpeg.$variant' -nostdin -hide_banner -v info -c:v h264 -i '$CLIP' -map 0:v:0 -an -t 30 -f null - -benchmark; rc=\$?; printf 'decode_remote_rc=%s\\n' \"\$rc\"; if [ \"\$rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi")"
    printf 'decode_output_begin,round=%s,variant=%s\n%s\ndecode_output_end,round=%s,variant=%s\n' \
        "$round" "$variant" "$output" "$round" "$variant" | tee -a "$RESULT_FILE"
    rc="$(sed -n 's/^decode_remote_rc=//p' <<< "$output" | tail -n 1)"
    sentinel_count="$(grep -c '^sample_end=OK$' <<< "$output" || true)"
    timings="$(sed -n 's/.*bench: utime=\([0-9.][0-9.]*\)s stime=\([0-9.][0-9.]*\)s rtime=\([0-9.][0-9.]*\)s.*/\1,\2,\3/p' <<< "$output" | tail -n 1)"
    maxrss="$(sed -n 's/.*bench: maxrss=\([0-9][0-9]*\)KiB.*/\1/p' <<< "$output" | tail -n 1)"
    IFS=',' read -r utime stime rtime <<< "$timings"
    [[ "$rc" == 0 && "$sentinel_count" -eq 1 && -n "$utime" && -n "$stime" && -n "$rtime" && -n "$maxrss" ]] || {
        say "MEASUREMENT_FAIL decode incomplete round=$round variant=$variant rc=${rc:-MISSING} sentinel=$sentinel_count timings=${timings:-MISSING} maxrss=${maxrss:-MISSING}"
        return 1
    }
    grep -q 'h264 (native) -> wrapped_avframe (native)' <<< "$output" || {
        say "MEASUREMENT_FAIL decoder identity missing round=$round variant=$variant"
        return 1
    }
    say "decode_metric,$round,$variant,$utime,$stime,$rtime,$maxrss"
    DECODE_UTIME="$utime"
}

if [[ "$RUN_MODE" == full ]]; then
    say "### decode benchmark: 30-second H.264 window"
    valid_rounds=0
    attempt=0
    max_attempts=$(( DECODE_REPS + 5 ))
    while (( valid_rounds < DECODE_REPS )); do
        attempt=$(( attempt + 1 ))
        (( attempt <= max_attempts )) || { say "MEASUREMENT_FAIL insufficient valid decode rounds"; exit 5; }
        wait_until_cool "decode.$attempt.before"
        frequency_snapshot "decode.$attempt.before"
        round_freq_invalid="$FREQ_INVALID"
        case $(( (attempt - 1) % 3 )) in
            0) order=(F1 F2 F3) ;;
            1) order=(F2 F3 F1) ;;
            2) order=(F3 F1 F2) ;;
        esac
        say "decode_round,$attempt,order=${order[*]}"
        declare -A round_utime=()
        for variant in "${order[@]}"; do
            decode_one "$variant" "$attempt" || exit 5
            round_utime[$variant]="$DECODE_UTIME"
        done
        frequency_snapshot "decode.$attempt.after"
        (( FREQ_INVALID == 0 )) || round_freq_invalid=1
        median="$(printf '%s\n' "${round_utime[F1]}" "${round_utime[F2]}" "${round_utime[F3]}" | sort -n | sed -n '2p')"
        say "decode_round_median_utime,$attempt,$median"
        for variant in F1 F2 F3; do
            if ! awk -v sample="${round_utime[$variant]}" -v median="$median" 'BEGIN { exit !(sample >= median * 0.5) }'; then
                say "MEASUREMENT_FAIL L3 utime_below_half_median round=$attempt variant=$variant utime=${round_utime[$variant]} median=$median"
                exit 5
            fi
        done
        if (( round_freq_invalid != 0 )); then
            say "decode_invalid,$attempt,reason=cur_freq_below_max"
        else
            valid_rounds=$(( valid_rounds + 1 ))
            say "decode_valid,$attempt,valid_index=$valid_rounds"
        fi
        if (( valid_rounds < DECODE_REPS )); then
            say "decode_cooldown_after_attempt.$attempt=$COOLDOWN_SECONDS"
            sleep "$COOLDOWN_SECONDS"
        fi
    done
fi

timer_one() {
    local variant="$1"
    local output rc sentinel_count value
    output="$(remote_capture "'$BIN_DIR/timer' '$BIN_DIR/ffmpeg.$variant' -version; rc=\$?; printf 'startup_remote_rc=%s\\n' \"\$rc\"; if [ \"\$rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi")"
    if ! value="$(ffmpeg_timer_value <<< "$output")"; then
        printf 'startup_timer_invalid_begin,variant=%s\n%s\nstartup_timer_invalid_end,variant=%s\n' \
            "$variant" "$output" "$variant" | tee -a "$RESULT_FILE" >&2
        return 1
    fi
    rc="$(sed -n 's/^startup_remote_rc=//p' <<< "$output" | tail -n 1)"
    sentinel_count="$(grep -c '^sample_end=OK$' <<< "$output" || true)"
    [[ "$value" =~ ^[0-9]+$ && "$rc" == 0 && "$sentinel_count" -eq 1 ]] || return 1
    printf '%s' "$value"
}

say "### startup triples"
for ((round = 1; round <= STARTUP_REPS; round++)); do
    wait_until_cool "startup.$round.before"
    frequency_snapshot "startup.$round.before"
    startup_freq_invalid="$FREQ_INVALID"
    case $(( (round - 1) % 3 )) in
        0) order=(F1 F2 F3) ;;
        1) order=(F2 F3 F1) ;;
        2) order=(F3 F1 F2) ;;
    esac
    f1_ns=""; f2_ns=""; f3_ns=""
    for variant in "${order[@]}"; do
        value="$(timer_one "$variant")" || { say "MEASUREMENT_FAIL startup incomplete round=$round variant=$variant"; exit 6; }
        case "$variant" in F1) f1_ns="$value" ;; F2) f2_ns="$value" ;; F3) f3_ns="$value" ;; esac
    done
    frequency_snapshot "startup.$round.after"
    (( FREQ_INVALID == 0 )) || startup_freq_invalid=1
    say "startup_triple,$round,$f1_ns,$f2_ns,$f3_ns"
    if (( startup_freq_invalid != 0 )); then
        say "startup_invalid,$round,reason=cur_freq_below_max"
    else
        say "startup_valid,$round"
    fi
done

memory_one() {
    local variant="$1"
    local rep="$2"
    local output rc sentinel_count timings maxrss rss pss private_clean private_dirty key
    output="$(remote_capture "set -e; out=/tmp/ffmpeg-mem-$variant-\$\$.out; '$BIN_DIR/ffmpeg.$variant' -nostdin -hide_banner -v info -re -c:v h264 -i '$CLIP' -map 0:v:0 -an -t 30 -f null - -benchmark >\"\$out\" 2>&1 & pid=\$!; cleanup() { kill \"\$pid\" 2>/dev/null || true; wait \"\$pid\" 2>/dev/null || true; rm -f \"\$out\"; }; trap cleanup HUP INT TERM; sleep 5; kill -0 \"\$pid\"; printf 'smaps_begin\\n'; grep -E '^(Rss|Pss|Private_Clean|Private_Dirty):' /proc/\$pid/smaps_rollup; printf 'smaps_end\\n'; set +e; wait \"\$pid\"; rc=\$?; set -e; cat \"\$out\"; rm -f \"\$out\"; trap - HUP INT TERM; printf 'memory_remote_rc=%s\\n' \"\$rc\"; if [ \"\$rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi")"
    printf 'memory_output_begin,rep=%s,variant=%s\n%s\nmemory_output_end,rep=%s,variant=%s\n' \
        "$rep" "$variant" "$output" "$rep" "$variant" | tee -a "$RESULT_FILE"
    rc="$(sed -n 's/^memory_remote_rc=//p' <<< "$output" | tail -n 1)"
    sentinel_count="$(grep -c '^sample_end=OK$' <<< "$output" || true)"
    timings="$(sed -n 's/.*bench: utime=\([0-9.][0-9.]*\)s stime=\([0-9.][0-9.]*\)s rtime=\([0-9.][0-9.]*\)s.*/\1,\2,\3/p' <<< "$output" | tail -n 1)"
    maxrss="$(sed -n 's/.*bench: maxrss=\([0-9][0-9]*\)KiB.*/\1/p' <<< "$output" | tail -n 1)"
    [[ "$rc" == 0 && "$sentinel_count" -eq 1 && -n "$timings" && -n "$maxrss" ]] || {
        say "MEASUREMENT_FAIL memory incomplete rep=$rep variant=$variant rc=${rc:-MISSING} timings=${timings:-MISSING} maxrss=${maxrss:-MISSING}"
        return 1
    }
    for key in Rss Pss Private_Clean Private_Dirty; do
        grep -q "^$key:" <<< "$output" || { say "MEASUREMENT_FAIL memory missing=$key rep=$rep variant=$variant"; return 1; }
    done
    rss="$(sed -n 's/^Rss:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*kB$/\1/p' <<< "$output" | tail -n 1)"
    pss="$(sed -n 's/^Pss:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*kB$/\1/p' <<< "$output" | tail -n 1)"
    private_clean="$(sed -n 's/^Private_Clean:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*kB$/\1/p' <<< "$output" | tail -n 1)"
    private_dirty="$(sed -n 's/^Private_Dirty:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*kB$/\1/p' <<< "$output" | tail -n 1)"
    [[ -n "$rss" && -n "$pss" && -n "$private_clean" && -n "$private_dirty" && -n "$maxrss" ]] || return 1
    say "memory_metric,$rep,$variant,$rss,$pss,$private_clean,$private_dirty,$maxrss"
}

say "### memory at decode second 5"
for ((rep = 1; rep <= MEM_REPS; rep++)); do
    wait_until_cool "memory.$rep.before"
    case $(( (rep - 1) % 3 )) in
        0) order=(F1 F2 F3) ;;
        1) order=(F2 F3 F1) ;;
        2) order=(F3 F1 F2) ;;
    esac
    for variant in "${order[@]}"; do
        memory_one "$variant" "$rep" || exit 7
    done
done

say "### board size matrix verification"
while IFS=',' read -r variant mode state expected; do
    say "size_host,$variant,$mode,$state,$expected"
    [[ "$state" == stripped ]] || continue
    suffix=""
    [[ "$mode" == gc ]] && suffix=".gc"
    actual="$(remote_capture "stat -c %s '$BIN_DIR/ffmpeg.$variant$suffix'")"
    say "size_board,$variant,$mode,$state,$actual"
    [[ "$actual" == "$expected" ]] || { say "MEASUREMENT_FAIL size mismatch variant=$variant mode=$mode"; exit 8; }
done < "$SIZE_MATRIX"
say "size_board_verification=PASS"

say "### F2 function surface"
function_output="$(remote_capture "cat '$PRIVATE_ROOT/share/function-surface.txt'")"
printf '%s\n' "$function_output" | tee -a "$RESULT_FILE"
for key in strcoll iconv setlocale getaddrinfo; do
    grep -Eq "^$key=(PRESENT|ABSENT)$" <<< "$function_output" || {
        say "MEASUREMENT_FAIL function surface missing key=$key"
        exit 9
    }
done
say "function_surface_verification=PASS"

assert_no_residual after
run_remote "printf 'loadavg.after='; cat /proc/loadavg; ps -ef | grep -E '[f]fmpeg|[t]imer' || true"
wait_until_cool after
say "measurement.finish_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ "$RUN_MODE" == supplement ]]; then
    say "MEASUREMENT_FFMPEG_SUPPLEMENT_PASS"
else
    say "MEASUREMENT_FFMPEG_PASS"
fi
