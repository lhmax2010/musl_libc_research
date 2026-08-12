#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/results/logs/malloc-share-scan-reports"
RAW_DIR="$ROOT_DIR/results/perf-raw"

stems=(
    p_dbus_system_idle
    p_dbus_system_stimulus
    p_dlog_logger_idle
    p_dlog_logger_stimulus
    p_enlightenment_idle
    p_homescreen_idle
    p_pulseaudio_idle
    p_resourced_idle
    p_systemui_idle
)

printf '%s\n' 'malloc-share mechanical extraction'
printf '%s\n' 'malloc_symbol_regex=^(malloc|_int_malloc|_int_free.*|free|calloc|realloc|tcache.*|malloc_consolidate|arena_get)$'
printf '%s\n' 'percent_column=Self'
printf '%s\n' 'low_samples_threshold=500'
printf '%s\n' 'expected_samples_per_round=2970 (99_Hz * 30_seconds)'
printf '%s\n' 'est_CPU_percent=(samples / 2970) * 100'
printf '%s\n' 'OUT_IDLE=LOW_SAMPLES and est_CPU_percent < 5.0'

round_count=0
out_idle_or_excluded_count=0

for stem in "${stems[@]}"; do
    symbol_file="$REPORT_DIR/$stem.symbol.txt"
    dso_file="$REPORT_DIR/$stem.dso.txt"
    stats_file="$REPORT_DIR/$stem.stats.txt"
    test -f "$symbol_file"
    test -f "$dso_file"
    test -f "$stats_file"

    samples="$(awk '/^[[:space:]]*SAMPLE events:/ { print $3; exit }' "$stats_file")"
    samples="${samples:-0}"
    malloc_self="$(awk '
        /^[[:space:]]*[0-9.]+%[[:space:]]+[0-9.]+%/ {
            self=$2
            gsub(/%/, "", self)
            symbol=$4
            if (symbol ~ /^(malloc|_int_malloc|_int_free.*|free|calloc|realloc|tcache.*|malloc_consolidate|arena_get)$/) {
                sum += self
            }
        }
        END { printf "%.2f", sum + 0 }
    ' "$symbol_file")"
    libc_self="$(awk '
        /^[[:space:]]*[0-9.]+%[[:space:]]+[0-9.]+%/ {
            self=$2
            gsub(/%/, "", self)
            dso=$3
            if (dso ~ /^libc([.-]|\.so)/ || dso == "libc.so.6") {
                sum += self
            }
        }
        END { printf "%.2f", sum + 0 }
    ' "$dso_file")"

    quality=VALID_SAMPLE_COUNT
    if (( samples < 500 )); then
        quality=LOW_SAMPLES
    fi

    est_cpu_percent="$(awk -v samples="$samples" 'BEGIN { printf "%.3f", (samples / 2970) * 100 }')"
    routing=UNCLASSIFIED
    if [[ "$quality" == LOW_SAMPLES ]] && awk -v value="$est_cpu_percent" 'BEGIN { exit !(value < 5.0) }'; then
        routing=OUT_IDLE
    fi
    if [[ "$stem" == p_dbus_system_* ]]; then
        routing="${routing}+SINGLE_THREADED_EXCLUDED"
    fi
    round_count=$((round_count + 1))
    if [[ "$routing" == OUT_IDLE* || "$routing" == *SINGLE_THREADED_EXCLUDED* ]]; then
        out_idle_or_excluded_count=$((out_idle_or_excluded_count + 1))
    fi

    printf 'round=%s samples=%s est_CPU=%s%% malloc_self=%s%% libc_self=%s%% quality=%s routing=%s\n' \
        "$stem" "$samples" "$est_cpu_percent" "$malloc_self" "$libc_self" "$quality" "$routing"

    awk '
        /^[[:space:]]*[0-9.]+%[[:space:]]+[0-9.]+%/ {
            symbol=$4
            if (symbol ~ /^(malloc|_int_malloc|_int_free.*|free|calloc|realloc|tcache.*|malloc_consolidate|arena_get)$/) {
                line=$0
                sub(/[[:space:]]+$/, "", line)
                print "malloc_source_row=" line
            }
        }
    ' "$symbol_file"
    awk '
        /^[[:space:]]*[0-9.]+%[[:space:]]+[0-9.]+%/ {
            dso=$3
            if (dso ~ /^libc([.-]|\.so)/ || dso == "libc.so.6") {
                line=$0
                sub(/[[:space:]]+$/, "", line)
                print "libc_source_row=" line
            }
        }
    ' "$dso_file"
done

printf 'rounds_total=%s\n' "$round_count"
printf 'rounds_OUT_IDLE_or_EXCLUDED=%s\n' "$out_idle_or_excluded_count"
test "$round_count" -eq 9
test "$out_idle_or_excluded_count" -eq 9
printf '%s\n' 'routing_gate=PASS (9/9 OUT_IDLE/EXCLUDED)'

printf '%s\n' 'raw_sha256_begin'
sha256sum "$RAW_DIR"/*.data
printf '%s\n' 'raw_sha256_end'
