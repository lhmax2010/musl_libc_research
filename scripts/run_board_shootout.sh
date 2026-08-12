#!/usr/bin/env bash
# Run the six-variant allocator shootout in one gated board session.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
PRIVATE_ROOT="/opt/usr/musl-demo"
BIN_DIR="$PRIVATE_ROOT/bin"
RESULT_FILE="${RESULT_FILE:-$ROOT_DIR/results/results-shootout.txt}"
MALLOC_REPS="${MALLOC_REPS:-5}"
MEM_REPS="${MEM_REPS:-3}"
STARTUP_REPS="${STARTUP_REPS:-30}"
S4_ENV="MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0"
VARIANTS=(S1 S2 S3 S4 S5 S6)

[[ "$MALLOC_REPS" -ge 5 && "$MEM_REPS" -eq 3 && "$STARTUP_REPS" -eq 30 ]] || {
    echo "ERROR frozen sample counts require malloc>=5 mem=3 startup=30" >&2
    exit 2
}
[[ ! -e "$RESULT_FILE" ]] || { echo "ERROR raw result already exists: $RESULT_FILE" >&2; exit 2; }
for tool in awk grep sdb sed sort tee; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR missing host tool: $tool" >&2; exit 2; }
done
mkdir -p "$(dirname -- "$RESULT_FILE")"
touch "$RESULT_FILE"

say() { printf '%s\n' "$*" | tee -a "$RESULT_FILE"; }
run_logged() { "$@" </dev/null 2>&1 | tr -d '\r' | tee -a "$RESULT_FILE"; }

variant_binary() {
    case "$1" in
        S1) echo "$BIN_DIR/micro.glibc-dyn" ;;
        S2) echo "$BIN_DIR/micro.musl-static" ;;
        S3|S4) echo "$BIN_DIR/micro.musl-mi" ;;
        S5) echo "$BIN_DIR/micro.musl-rp" ;;
        S6) echo "$BIN_DIR/micro.musl-scudo" ;;
        *) return 2 ;;
    esac
}

variant_env() {
    if [[ "$1" == S4 ]]; then echo "$S4_ENV"; else echo "EMPTY"; fi
}

variant_command() {
    local variant="$1"
    local args="$2"
    local binary
    binary="$(variant_binary "$variant")"
    if [[ "$variant" == S4 ]]; then
        printf '%s %s %s' "$S4_ENV" "$binary" "$args"
    else
        printf '%s %s' "$binary" "$args"
    fi
}

run_logged sdb connect "$TARGET"
sdb_serial="$(
    sdb devices | awk -v target="$TARGET" '
        $2 == "device" && ($1 == target || index($1, target ":") == 1) { print $1 }
    '
)"
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]] || {
    say "MEASUREMENT_FAIL expected exactly one SDB serial target=$TARGET"
    exit 3
}
remote_capture() { sdb -s "$sdb_serial" shell "$1" </dev/null 2>&1 | tr -d '\r'; }
run_remote() { remote_capture "$1" | tee -a "$RESULT_FILE"; }
run_logged sdb -s "$sdb_serial" root on

say "### environment"
say "measurement.target=$TARGET"
say "measurement.sdb_serial=$sdb_serial"
say "measurement.start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "measurement.malloc_reps=$MALLOC_REPS"
say "measurement.mem_reps=$MEM_REPS"
say "measurement.startup_reps=$STARTUP_REPS"
say "measurement.sample_sentinel=required"
say "measurement.s4_env=$S4_ENV"
say "measurement.s3_s4_binary=$BIN_DIR/micro.musl-mi"
say "measurement.malloc_iters_per_thread=2000000"
identity="$(remote_capture "uname -r; cat /etc/os-release | head -4")"
printf '%s\n' "$identity" | tee -a "$RESULT_FILE"
grep -qi rpi4 <<< "$identity" || { say "MEASUREMENT_FAIL kernel identity lacks rpi4"; exit 4; }
grep -qi Tizen <<< "$identity" || { say "MEASUREMENT_FAIL os identity is not Tizen"; exit 4; }
grep -Eqi 'unified|dev' <<< "$identity" || { say "MEASUREMENT_FAIL os identity is not unified(dev)"; exit 4; }
say "gate.board_identity=PASS"
run_remote "printf 'loadavg.before='; cat /proc/loadavg; ps -ef | grep -E '[m]icro\\.|[t]imer' || true"

for variant in "${VARIANTS[@]}"; do
    binary="$(variant_binary "$variant")"
    run_remote "test -x '$binary' && echo binary.$variant=$binary"
done
run_remote "test -x '$BIN_DIR/timer' && echo binary.timer=$BIN_DIR/timer"
[[ "$(variant_binary S3)" == "$(variant_binary S4)" ]] || { say "MEASUREMENT_FAIL S3/S4 path differs"; exit 4; }
say "gate.s3_s4_same_binary=PASS"

assert_no_residual() {
    local phase="$1"
    run_remote "set -e; residual=0; for exe in /proc/[0-9]*/exe; do target=\$(readlink \"\$exe\" 2>/dev/null || true); case \"\$target\" in '$BIN_DIR'/micro.*|'$BIN_DIR'/timer) printf 'residual.$phase=%s\\n' \"\$target\"; residual=1 ;; esac; done; [ \"\$residual\" -eq 0 ]; echo residual.$phase=NONE"
}
assert_no_residual before

say "### governor"
run_remote 'set -e; found=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do found=1; echo performance > "$f"; done; [ "$found" -eq 1 ]; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do cpu=${f#/sys/devices/system/cpu/}; cpu=${cpu%%/*}; value=$(cat "$f"); printf "governor.%s=%s\n" "$cpu" "$value"; [ "$value" = performance ]; done'

read_temperature_raw() {
    remote_capture 'set -e; found=0; max=0; for f in /sys/class/thermal/thermal_zone[0-9]*/temp; do found=1; value=$(cat "$f"); case "$value" in *[!0-9]*|"") exit 3 ;; esac; [ "$value" -gt "$max" ] && max=$value; done; [ "$found" -eq 1 ]; echo "$max"'
}

wait_until_cool() {
    local scope="$1"
    local raw
    while :; do
        raw="$(read_temperature_raw)"
        [[ "$raw" =~ ^[0-9]+$ ]] || { say "MEASUREMENT_FAIL temperature unavailable scope=$scope"; exit 5; }
        say "temperature.$scope.raw=$raw"
        (( raw <= 65000 )) && break
        say "temperature.$scope.wait=ABOVE_65C"
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
        say "frequency.$scope.$cpu.cur=$cur,max=$max"
        [[ "$cur" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]] || { FREQ_INVALID=1; continue; }
        (( cur >= max )) || FREQ_INVALID=1
    done <<< "$output"
}

sample_env_line() {
    local phase="$1" rep="$2" variant="$3"
    say "sample_env,phase=$phase,rep=$rep,variant=$variant,env=$(variant_env "$variant")"
}

run_probe() {
    local command="$1"
    remote_capture "$command; probe_rc=\$?; printf 'probe_rc=%s\\n' \"\$probe_rc\"; if [ \"\$probe_rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi; exit \"\$probe_rc\"" | tee -a "$RESULT_FILE"
}

rotated_order() {
    local shift_by="$1" i index output=()
    for ((i = 0; i < ${#VARIANTS[@]}; i++)); do
        index=$(( (i + shift_by) % ${#VARIANTS[@]} ))
        output+=("${VARIANTS[$index]}")
    done
    printf '%s\n' "${output[@]}"
}

say "### sizes stripped board matrix"
for variant in "${VARIANTS[@]}"; do
    binary="$(variant_binary "$variant")"
    run_remote "stat -c 'size,variant=$variant,bytes=%s,path=%n' '$binary'"
done

say "### startup six-way interleaved"
startup_valid=0
startup_attempt=0
while (( startup_valid < STARTUP_REPS )); do
    startup_attempt=$((startup_attempt + 1))
    (( startup_attempt <= STARTUP_REPS + 10 )) || { say "MEASUREMENT_FAIL startup valid rounds insufficient"; exit 6; }
    wait_until_cool "startup.$startup_attempt.before"
    frequency_snapshot "startup.$startup_attempt.before"
    round_invalid="$FREQ_INVALID"
    order=()
    while IFS= read -r variant; do order+=("$variant"); done < <(rotated_order $(( (startup_attempt - 1) % 6 )))
    say "startup_round,attempt=$startup_attempt,order=${order[*]}"
    for variant in "${order[@]}"; do
        sample_env_line startup "$startup_attempt" "$variant"
        binary="$(variant_binary "$variant")"
        if [[ "$variant" == S4 ]]; then
            timer_command="$S4_ENV $BIN_DIR/timer $binary startup"
        else
            timer_command="$BIN_DIR/timer $binary startup"
        fi
        output="$(remote_capture "$timer_command; rc=\$?; printf 'probe_rc=%s\\n' \"\$rc\"; if [ \"\$rc\" -eq 0 ]; then printf 'sample_end=OK\\n'; fi")"
        printf '%s\n' "$output" | tee -a "$RESULT_FILE"
        value="$(grep -E '^[0-9]+$' <<< "$output" || true)"
        numeric_count="$(grep -Ec '^[0-9]+$' <<< "$output" || true)"
        sentinel_count="$(grep -c '^sample_end=OK$' <<< "$output" || true)"
        rc="$(sed -n 's/^probe_rc=//p' <<< "$output" | tail -n 1)"
        [[ "$numeric_count" -eq 1 && "$sentinel_count" -eq 1 && "$rc" == 0 ]] || {
            say "MEASUREMENT_FAIL startup sample invalid attempt=$startup_attempt variant=$variant"
            exit 6
        }
        say "startup_sample,attempt=$startup_attempt,variant=$variant,ns=$value,env=$(variant_env "$variant")"
    done
    frequency_snapshot "startup.$startup_attempt.after"
    (( FREQ_INVALID == 0 )) || round_invalid=1
    if (( round_invalid == 0 )); then
        startup_valid=$((startup_valid + 1))
        say "startup_round_valid,attempt=$startup_attempt,valid_index=$startup_valid"
    else
        say "startup_round_invalid,attempt=$startup_attempt,reason=cur_freq_below_max"
    fi
done

say "### mem smaps_rollup x3"
for ((rep = 1; rep <= MEM_REPS; rep++)); do
    wait_until_cool "mem.$rep.before"
    for variant in "${VARIANTS[@]}"; do
        sample_env_line mem "$rep" "$variant"
        say "memcfg=variant=$variant,rep=$rep,env=$(variant_env "$variant")"
        command="$(variant_command "$variant" mem)"
        run_probe "set -e; out=/tmp/shootout-mem-$variant-\$\$.out; $command >\"\$out\" & pid=\$!; cleanup() { kill \"\$pid\" 2>/dev/null || true; wait \"\$pid\" 2>/dev/null || true; rm -f \"\$out\"; }; trap cleanup EXIT HUP INT TERM; sleep 1; kill -0 \"\$pid\"; cat \"\$out\"; grep -E '^(Rss|Pss|Private_Clean|Private_Dirty):' /proc/\$pid/smaps_rollup"
    done
done

say "### threads 200"
for variant in "${VARIANTS[@]}"; do
    sample_env_line threads 1 "$variant"
    say "threadscfg=variant=$variant,rep=1,env=$(variant_env "$variant")"
    run_probe "$(variant_command "$variant" 'threads 200')"
done

say "### malloc churn"
for threads in 1 4; do
    valid_rounds=0
    attempt=0
    while (( valid_rounds < MALLOC_REPS )); do
        attempt=$((attempt + 1))
        (( attempt <= MALLOC_REPS + 5 )) || { say "MEASUREMENT_FAIL malloc valid rounds insufficient threads=$threads"; exit 7; }
        wait_until_cool "malloc.t$threads.$attempt.before"
        frequency_snapshot "malloc.t$threads.$attempt.before"
        round_invalid="$FREQ_INVALID"
        order=()
        while IFS= read -r variant; do order+=("$variant"); done < <(rotated_order $(( (attempt + threads - 1) % 6 )))
        say "malloc_round,threads=$threads,attempt=$attempt,order=${order[*]}"
        for variant in "${order[@]}"; do
            sample_env_line "malloc-t$threads" "$attempt" "$variant"
            say "malloccfg=variant=$variant,threads=$threads,attempt=$attempt,env=$(variant_env "$variant")"
            run_probe "$(variant_command "$variant" "malloc $threads 2000000")"
        done
        frequency_snapshot "malloc.t$threads.$attempt.after"
        (( FREQ_INVALID == 0 )) || round_invalid=1
        if (( round_invalid == 0 )); then
            valid_rounds=$((valid_rounds + 1))
            say "malloc_round_valid,threads=$threads,attempt=$attempt,valid_index=$valid_rounds"
        else
            say "malloc_round_invalid,threads=$threads,attempt=$attempt,reason=cur_freq_below_max"
        fi
    done
done

assert_no_residual after
run_remote "printf 'loadavg.after='; cat /proc/loadavg"
say "measurement.finish_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "MEASUREMENT_PASS"
chmod 0444 "$RESULT_FILE"
printf 'RAW_RESULTS_READ_ONLY=%s\n' "$RESULT_FILE"
