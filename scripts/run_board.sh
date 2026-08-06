#!/usr/bin/env bash
# Run the complete three-variant measurement matrix on an already deployed board.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.25}"
REPS="${REPS:-30}"
PRIVATE_ROOT="/opt/usr/musl-demo"
BIN_DIR="$PRIVATE_ROOT/bin"
RESULTS_DIR="$ROOT_DIR/results"
LOG_DIR="$RESULTS_DIR/logs"
RESULT_FILE="$RESULTS_DIR/results.txt"
RESOLV_FILE="$LOG_DIR/resolv.conf.board"

[[ "$REPS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR REPS must be a positive integer" >&2; exit 2; }
for tool in python3 sdb tee; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR required host tool missing: $tool" >&2; exit 2; }
done

mkdir -p "$LOG_DIR"
: > "$RESULT_FILE"

say() {
    printf '%s\n' "$*" | tee -a "$RESULT_FILE"
}

remote_capture() {
    sdb shell "$1" | tr -d '\r'
}

run_remote() {
    remote_capture "$1" | tee -a "$RESULT_FILE"
}

sdb connect "$TARGET" 2>&1 | tr -d '\r' | tee -a "$RESULT_FILE"
sdb root on 2>&1 | tr -d '\r' | tee -a "$RESULT_FILE"
say "### environment"
say "measurement.target=$TARGET"
say "measurement.start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
say "measurement.startup_reps=$REPS"
run_remote "uname -a"

for variant in micro.glibc-dyn micro.musl-static micro.musl-dyn timer; do
    run_remote "test -x '$BIN_DIR/$variant' && echo binary.$variant=present"
done

say "### governor"
run_remote 'set -e; found=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do found=1; echo performance > "$f"; done; [ "$found" -eq 1 ]; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do cpu=${f#/sys/devices/system/cpu/}; cpu=${cpu%%/*}; value=$(cat "$f"); printf "governor.%s=%s\n" "$cpu" "$value"; [ "$value" = performance ]; done'

temperature_snapshot() {
    local phase="$1"
    local output
    output="$(remote_capture 'for f in /sys/class/thermal/thermal_zone[0-9]*/temp; do zone=${f#/sys/class/thermal/}; zone=${zone%%/*}; printf "%s=%s\n" "$zone" "$(cat "$f")"; done')"
    [[ -n "$output" ]] || { say "temperature.$phase=UNAVAILABLE"; return; }
    while IFS='=' read -r zone value; do
        say "temperature.$phase.$zone=$value"
    done <<< "$output"
}

FREQ_INVALID=0
frequency_snapshot() {
    local round="$1"
    local phase="$2"
    local output cpu cur max
    FREQ_INVALID=0
    output="$(remote_capture 'found=0; for d in /sys/devices/system/cpu/cpu[0-9]*; do [ -f "$d/cpufreq/scaling_cur_freq" ] || continue; found=1; cpu=${d##*/}; cur=$(cat "$d/cpufreq/scaling_cur_freq"); max=$(cat "$d/cpufreq/scaling_max_freq"); printf "%s,%s,%s\n" "$cpu" "$cur" "$max"; done; [ "$found" -eq 1 ]')"
    while IFS=',' read -r cpu cur max; do
        [[ "$cur" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]] || {
            say "startup_freq,$round,$phase,$cpu,INVALID,INVALID"
            FREQ_INVALID=1
            continue
        }
        say "startup_freq,$round,$phase,$cpu,$cur,$max"
        if (( cur < max )); then
            FREQ_INVALID=1
        fi
    done <<< "$output"
}

temperature_snapshot before
say "### frequencies before"
frequency_snapshot 0 before
say "frequency.before.invalid=$FREQ_INVALID"

say "### sizes"
run_remote "ls -l '$BIN_DIR/micro.glibc-dyn' '$BIN_DIR/micro.musl-static' '$BIN_DIR/micro.musl-dyn' '$PRIVATE_ROOT/lib/libc.so'"

timer_one() {
    local variant="$1"
    local value
    value="$(remote_capture "$BIN_DIR/timer '$BIN_DIR/$variant' startup")"
    [[ "$value" =~ ^[0-9]+$ ]] || { say "startup.timer_error.$variant=$value"; return 1; }
    printf '%s' "$value"
}

say "### startup triple"
for ((round = 1; round <= REPS; round++)); do
    frequency_snapshot "$round" before
    round_invalid="$FREQ_INVALID"
    case $(( (round - 1) % 3 )) in
        0) order=(micro.glibc-dyn micro.musl-static micro.musl-dyn) ;;
        1) order=(micro.musl-static micro.musl-dyn micro.glibc-dyn) ;;
        2) order=(micro.musl-dyn micro.glibc-dyn micro.musl-static) ;;
    esac
    glibc_ns=""
    static_ns=""
    dyn_ns=""
    for variant in "${order[@]}"; do
        value="$(timer_one "$variant")"
        case "$variant" in
            micro.glibc-dyn) glibc_ns="$value" ;;
            micro.musl-static) static_ns="$value" ;;
            micro.musl-dyn) dyn_ns="$value" ;;
        esac
    done
    frequency_snapshot "$round" after
    if (( FREQ_INVALID != 0 )); then round_invalid=1; fi
    say "startup_triple,$round,$glibc_ns,$static_ns,$dyn_ns"
    if (( round_invalid != 0 )); then
        say "startup_invalid,$round,reason=cur_freq_below_max"
    else
        say "startup_valid,$round"
    fi
done

say "### mem smaps_rollup x3"
for rep in 1 2 3; do
    for variant in glibc-dyn musl-static musl-dyn; do
        say "memcfg=$variant,rep=$rep"
        run_remote "set -e; out=/tmp/musl-demo-mem-$variant-\$\$.out; '$BIN_DIR/micro.$variant' mem > \"\$out\" & pid=\$!; cleanup() { kill \"\$pid\" 2>/dev/null || true; wait \"\$pid\" 2>/dev/null || true; rm -f \"\$out\"; }; trap cleanup EXIT HUP INT TERM; sleep 1; cat \"\$out\"; grep -E '^(Rss|Pss|Private_Clean|Private_Dirty):' \"/proc/\$pid/smaps_rollup\""
    done
done

say "### threads 200"
for variant in glibc-dyn musl-static musl-dyn; do
    say "threadscfg=$variant"
    run_remote "'$BIN_DIR/micro.$variant' threads 200"
done

say "### malloc churn"
for rep in 1 2 3 4 5; do
    for threads in 1 4; do
        shift_by=$(( (rep + threads) % 3 ))
        case "$shift_by" in
            0) order=(glibc-dyn musl-static musl-dyn) ;;
            1) order=(musl-static musl-dyn glibc-dyn) ;;
            2) order=(musl-dyn glibc-dyn musl-static) ;;
        esac
        for variant in "${order[@]}"; do
            say "malloccfg=$variant,rep=$rep,threads=$threads"
            run_remote "'$BIN_DIR/micro.$variant' malloc '$threads' 2000000"
        done
    done
done

say "### dns"
sdb pull /etc/resolv.conf "$RESOLV_FILE" 2>&1 | tr -d '\r' | tee -a "$RESULT_FILE"
say "dns.resolv_conf_archive=$RESOLV_FILE"
while IFS= read -r line || [[ -n "$line" ]]; do say "resolv.conf=$line"; done < "$RESOLV_FILE"
for variant in glibc-dyn musl-static musl-dyn; do
    for name in localhost www.tizen.org; do
        say "dnscfg=$variant,name=$name"
        set +e
        remote_capture "'$BIN_DIR/micro.$variant' dns '$name'" | tee -a "$RESULT_FILE"
        probe_rc=${PIPESTATUS[0]}
        set -e
        say "dns.exit_status.$variant.$name=$probe_rc"
    done
done

say "### locale"
for variant in glibc-dyn musl-static musl-dyn; do
    say "localecfg=$variant,mode=default"
    run_remote "'$BIN_DIR/micro.$variant' locale"
    say "localecfg=$variant,mode=ko_KR.UTF-8"
    run_remote "LC_ALL=ko_KR.UTF-8 '$BIN_DIR/micro.$variant' locale"
done

temperature_snapshot after
say "### frequencies after"
frequency_snapshot 0 after
say "frequency.after.invalid=$FREQ_INVALID"
say "measurement.finish_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

python3 "$SCRIPT_DIR/gen_report.py" "$RESULT_FILE" > "$RESULTS_DIR/report.md"
echo "MEASUREMENT_PASS results=$RESULT_FILE report=$RESULTS_DIR/report.md"
