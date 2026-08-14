# Continue execution status — 2026-08-06

## Scheme A installation: PASS

The board RPM was pushed again and its SHA-256 matched the host artifact:

```text
ed42d8978ffd838fc59e4b02a6ab7b36c2825475cd3be434ed952c5341f2fcfa
```

The first authorized remediation level succeeded:

```text
rpm -Uvh --noplugins /tmp/musl-libc-demo-1.0.0-1.armv7l.rpm
REMOTE_RC=0
```

The equivalent Scheme A macro and Scheme B cpio extraction were not attempted.
`rpm -q` confirms `musl-libc-demo-1.0.0-1.armv7l`; RPM database semantics are
therefore intact. Board bin hashes exactly match the host artifact manifest,
all bin/lib entries have `User::Shell` labels, and all three no-argument smokes
returned status 0. `micro.musl-dyn` successfully used package loader
`ld-musl-arm.so.1`.

## Measurement remediation: complete, awaiting FatTank review

`SDB_TARGET=BOARD_RPI4 scripts/run_board.sh` completed and generated raw
results plus a report. It captured 30/30 frequency-valid startup triples, nine
memory configs, three thread configs, DNS and locale matrices, and stable
1.5 GHz pre/post frequencies.

Post-run audit found that the malloc matrix had one truncated sample. The raw
stream remains unchanged and contains:

```text
malloccfg=musl-dyn,rep=2,threads=4
malloc.threads=4malloccfg=musl-static,rep=3,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=310.7
```

The authorized root cause is undrained `sdb shell` output: the sample ended
without a newline and the next header was concatenated. No OOM kill, segfault,
micro-process exception, or matching journal event was found. The original
parser lacked completeness checks and consequently misattributed `310.7`.

The original `results/results.txt` remains read-only at SHA-256
`24ffb2ab105b3dcbe11c73a60aa0b5bfb18348062c748b19a40a6fff394d8faf`.
The parser now resynchronizes mid-line headers and requires four malloc keys;
new runs require the `sample_end=OK` sentinel. The authorized rep=6 t=4
supplement passed all board gates and added three VALID samples. The merged
set has 32 VALID and 1 preserved INVALID sample, with expected per-cell n.

The report has been regenerated and all startup, memory, thread, DNS, and
locale sections passed cardinality/completeness auditing. Delivery is complete
and execution is stopped pending FatTank data verification; no performance
conclusion is recorded.
