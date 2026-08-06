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

## Measurement: parked after integrity audit

`SDB_TARGET=192.168.108.25 scripts/run_board.sh` completed and generated raw
results plus a report. It captured 30/30 frequency-valid startup triples, nine
memory configs, three thread configs, DNS and locale matrices, and stable
1.5 GHz pre/post frequencies.

Post-run audit then found a new unpreauthorized failure: the malloc matrix has
29 rather than 30 independently parseable configurations and values. The raw
stream contains:

```text
malloccfg=musl-dyn,rep=2,threads=4
malloc.threads=4malloccfg=musl-static,rep=3,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=310.7
```

The generated report misattributes `310.7` to the preceding musl-dynamic
four-thread configuration, so its malloc table is explicitly marked invalid.
No OOM kill, segfault, micro-process, or matching journal event was found; root
cause remains unconfirmed.

No raw sample or parser was changed, and no corrective rerun was attempted.
`results/results.txt`, `results/report.md`, and the integrity audit are retained
for review. Further measurement work awaits explicit authorization.
