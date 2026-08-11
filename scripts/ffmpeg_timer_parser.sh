#!/usr/bin/env bash
# Shared strict parser for timer output that may contain child stdout/stderr.

ffmpeg_timer_value() {
    awk '
        /^[0-9]+$/ {
            count++
            value = $0
        }
        END {
            if (count == 1) {
                print value
                exit 0
            }
            exit 1
        }
    '
}
