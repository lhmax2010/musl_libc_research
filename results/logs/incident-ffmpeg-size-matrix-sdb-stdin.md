# Incident: SDB consumed the size-matrix loop input

Status: **PARKED — stdin detachment and a second supplement require authorization**

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
$ printf '%s\n' '#HOST_STDIN_SENTINEL' | sdb -s 192.168.108.26:26101 shell \
    "stat -c %s /opt/usr/ffmpeg-demo/bin/ffmpeg.F1"
#HOST_STDIN_SENTINEL
2353184
```

With stdin detached, only the expected value remains:

```text
$ sdb -s 192.168.108.26:26101 shell \
    "stat -c %s /opt/usr/ffmpeg-demo/bin/ffmpeg.F1" </dev/null
2353184
```

The RPM build evidence expects `2353184`, so no board artifact mismatch has
been observed; the failure is confined to host capture contamination.

## Immutable evidence and boundary

```text
e1c8378ed3639eb274fb2eefe25a791142ee2bf427b17565aa367a03e93451f6  results/results-ffmpeg.txt
2fa4971036581f1b69412138949604755536ba161e371694737ccda46b4c006d  results/results-ffmpeg-supplement.txt
board_size_verification=NOT_COMPLETED
function_surface_verification=NOT_RUN
report-ffmpeg.md=NOT_CREATED
```

Neither raw file may be modified or overwritten. A safe fix would detach SDB
stdin inside `remote_capture`, then collect only the still-missing board-size
and function-surface phases into a new second supplement. That fix and merge
policy are not pre-authorized, so execution remains parked.
