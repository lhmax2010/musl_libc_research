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

    printf 'round=%s samples=%s malloc_self=%s%% libc_self=%s%% quality=%s\n' \
        "$stem" "$samples" "$malloc_self" "$libc_self" "$quality"

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

printf '%s\n' 'raw_sha256_begin'
sha256sum "$RAW_DIR"/*.data
printf '%s\n' 'raw_sha256_end'
