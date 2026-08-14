# Incident: SDB consumed the size-matrix loop input

Status: **RESOLVED — stdin detached globally; size/function supplement passed**

## Stopping point

The authorized supplement preserved the primary decode file and completed:

```text
startup_triples=30
startup_valid=30
startup_invalid=0
memory_metrics=9
memory_sentinels=9
decode_metrics_in_supplement=0
```

It then stopped at the first board size cell:

```text
size_host,F1,baseline,unstripped,10874676
size_host,F1,baseline,stripped,2353184
size_board,F1,baseline,stripped,F2,baseline,unstripped,11881532
F2,baseline,stripped,2967556
F3,baseline,unstripped,12493148
F3,baseline,stripped,3071876
F1,gc,unstripped,10969056
F1,gc,stripped,2177984
F2,gc,unstripped,11953964
F2,gc,stripped,2782396
F3,gc,unstripped,12565496
F3,gc,stripped,2886716
2353184
MEASUREMENT_FAIL size mismatch variant=F1 mode=baseline
```

The function-surface phase was not run, and `report-ffmpeg.md` was not
generated.

## Root cause

The size verification is a host loop with its stdin redirected from
`sizes-matrix.txt`. `remote_capture` invokes `sdb shell` without detaching
stdin, so SDB consumes and echoes the loop's remaining matrix records. The
captured `actual` value therefore contains those records followed by the
correct `stat` number, and the exact comparison fails closed.

A read-only mechanical confirmation showed the stdin behavior:

```text
$ printf '%s\n' '#HOST_STDIN_SENTINEL' | sdb -s BOARD_RPI4:26101 shell \
    "stat -c %s /opt/usr/ffmpeg-demo/bin/ffmpeg.F1"
#HOST_STDIN_SENTINEL
2353184
```

With stdin detached, only the expected value remains:

```text
$ sdb -s BOARD_RPI4:26101 shell \
    "stat -c %s /opt/usr/ffmpeg-demo/bin/ffmpeg.F1" </dev/null
2353184
```

The RPM build evidence expects `2353184`, so no board artifact mismatch has
been observed; the failure is confined to host capture contamination.

## Immutable evidence and boundary

```text
69784e43a288bdce04c6e9b5d2492f411cf9f2a5d0457fad63734923f85893ce  results/results-ffmpeg.txt
c08c5896b7a85623bae89320f081128ebebfbe383b9110dd086f9d50ab665194  results/results-ffmpeg-supplement.txt
board_size_verification=NOT_COMPLETED
function_surface_verification=NOT_RUN
report-ffmpeg.md=NOT_CREATED
```

Neither raw file may be modified or overwritten. A safe fix would detach SDB
stdin inside `remote_capture`, then collect only the still-missing board-size
and function-surface phases into a new second supplement. That fix and merge
policy are not pre-authorized, so execution remains parked.

## Resolution

FatTank authorized stdin isolation as a board-script-wide invariant and a
second supplement limited to the invalid/missing phases. Every `sdb shell`
logical call under `scripts/` now has explicit `< /dev/null`; the while/read
scan and per-site conclusions are archived in
`results/logs/sdb-stdin-isolation-selfcheck.log`.

The causal regression first reproduced the unisolated multiline pollution,
then verified all six deployed stripped binaries against both the frozen size
matrix and a second independent `stat`. The F1 baseline anchor was `2353184`.

`results/results-ffmpeg-supplement2.txt` subsequently collected only size and
function evidence:

```text
decode=NOT_RUN
startup=NOT_RUN
memory=NOT_RUN
size_board_cells=6
size_board_verification=PASS
function_surface_verification=PASS
MEASUREMENT_FFMPEG_SUPPLEMENT2_PASS
```

The three immutable data-source hashes and their merge routing are frozen in
`results/logs/ffmpeg-three-source-sha256.log`. The board-script standard now
includes this lesson:

```text
循环体内的远端命令必须显式断开 stdin,与哨兵机制同级列为板端脚本标准约束
```
