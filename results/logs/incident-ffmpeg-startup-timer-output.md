# Incident: FFmpeg startup timer output parser assumes a silent child

Status: **RESOLVED — strict parser shipped; supplement startup data is complete**

## Stopping point

The replacement H.264 clip passed deployment and all three hardened smoke
gates. The formal board session then completed all ten valid decode rounds
before stopping at startup round 1, variant F1:

```text
### startup triples
temperature.startup.1.before.raw=37972
frequency.startup.1.before.cpu0.cur=1500000,max=1500000
frequency.startup.1.before.cpu1.cur=1500000,max=1500000
frequency.startup.1.before.cpu2.cur=1500000,max=1500000
frequency.startup.1.before.cpu3.cur=1500000,max=1500000
MEASUREMENT_FAIL startup incomplete round=1 variant=F1
```

No memory, board-size, or function-surface measurement was started, and no
`report-ffmpeg.md` was generated.

## Root cause

`packaging/timer.c` lets the measured child inherit stdout and stderr. That
was harmless for the earlier silent `micro ... startup` probe, but
`ffmpeg -version` prints its version/configuration before `timer` prints the
elapsed-nanosecond integer. `timer_one` incorrectly assumes that output line 1
is the integer, so its completeness check rejects a successful timer run.

An independent, read-only confirmation used:

```text
sdb -s BOARD_RPI4:26101 shell "/opt/usr/ffmpeg-demo/bin/timer /opt/usr/ffmpeg-demo/bin/ffmpeg.F1 -version; rc=\$?; printf 'timer_remote_rc=%s\\n' \"\$rc\""
```

The relevant output was:

```text
ffmpeg version 8.0.1 Copyright (c) 2000-2025 the FFmpeg developers
...
Exiting with exit code 0
3816667
timer_remote_rc=0
```

The instrument and child succeeded; only the host-side parser attribution is
wrong. A correct parser would select exactly one standalone decimal timing
line while retaining the remote return-code and sentinel checks. That change
has not been made because it is a newly encountered, unpreauthorized failure.

## Preserved partial data

The raw partial session is immutable at `results/results-ffmpeg.txt`:

```text
sha256=69784e43a288bdce04c6e9b5d2492f411cf9f2a5d0457fad63734923f85893ce
decode_valid_rounds=10
decode_metrics=30
native_decoder_mappings=30
bench_utime_lines=30
bench_maxrss_lines=30
sample_sentinels=30
decode_invalid_rounds=0
L3_failures=0
frequency_invalid_rounds=0
maximum_temperature_raw=37972
startup_triples=0
memory_metrics=0
board_size_verification=NOT_RUN
function_surface_verification=NOT_RUN
report_ffmpeg=NOT_CREATED
```

Every decode command used the frozen, three-way-identical 30-second form:

```text
ffmpeg.Fx -nostdin -hide_banner -v info -c:v h264 \
  -i /opt/usr/ffmpeg-demo/data/testclip.mp4 -map 0:v:0 \
  -an -t 30 -f null - -benchmark
```

## Authorization needed to resume

The raw file must not be edited or overwritten. Resumption requires a ruling
that authorizes both:

1. changing `timer_one` to require and select exactly one standalone decimal
   timer line instead of assuming line 1; and
2. either collecting only the unrun startup/memory/size/function phases into
   a new supplement file and combining it with the valid decode session, or
   running a wholly new complete session into a new raw file.

Until that ruling:

```text
board_measurement=PARKED
report-ffmpeg.md=NOT_CREATED
```

## Resolution

FatTank selected the supplement approach, following the malloc truncation
precedent: preserve the valid primary raw data, collect only missing phases in
a new file, and combine VALID samples without rewriting either source.

Commit `967d6d8e97da3a781a4f817bbdfacef70875abf7` changed the parser to accept
exactly one line matching `^[0-9]+$`. Zero or multiple decimal-only lines are
INVALID; remote rc=0 and exactly one `sample_end=OK` remain mandatory. The
board-captured verbose FFmpeg case, both negative cases, and the historical
micro single-line format passed the archived regression at
`results/logs/ffmpeg-timer-parser-selfcheck.log`.

The supplement produced 30/30 valid startup triples under the same thermal
and frequency gates. Root cause and lesson are therefore closed as:

```text
root_cause=micro_zero_output_assumption_broken_by_ffmpeg_version_banner
fix=exactly_one_standalone_decimal_line_plus_rc_and_sentinel
precedent=incident-board-measurement-malloc-truncation
lesson=解析器对被测程序输出形态的假设,须随被测对象更换而重审
```
