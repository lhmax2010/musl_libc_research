# Incident: truncated malloc sample corrupted report attribution

Date: 2026-08-06

## Reached state

Scheme A installation and all deployment validations passed. The full board
measurement command ran from `2026-08-06T08:27:02Z` to
`2026-08-06T08:28:20Z` and printed `MEASUREMENT_PASS`. All 30 startup triples
were frequency-valid; memory, thread, DNS, and locale sections were captured.

## Integrity failure

Post-run cardinality auditing found 29 malloc configuration markers and 29
values where the matrix requires 30. The immutable raw stream contains:

```text
malloccfg=musl-dyn,rep=2,threads=4
malloc.threads=4malloccfg=musl-static,rep=3,threads=1
malloc.threads=1
malloc.iters_per_thread=2000000
malloc.ns_per_op_mean=310.7
malloc.wall_worst_thread_ns=621337092
malloc.checksum=7dc87e4
```

The musl-dynamic four-thread sample stopped after its first field. Because it
did not end with a newline, the following musl-static configuration marker was
concatenated to that field and ceased to be parseable as a marker. The report
generator consequently attributes the musl-static value `310.7` to the prior
musl-dynamic four-thread configuration.

Therefore the generated malloc table is invalid and must not be used. The raw
startup, memory, thread, DNS, and locale evidence remains archived, but the
complete measurement/report phase is not marked PASS.

## Read-only investigation and disposition

The relevant dmesg filter showed only boot-time Smack initialization/denials
and an `oom_control` deprecation warning; it showed no corresponding OOM kill,
segfault, or micro-process event. The measurement-time journal filter returned
no matching lines. The cause is therefore unconfirmed; it is not attributed to
Smack, memory pressure, or transport without evidence.

No sample was edited or deleted, no parser was changed, and no benchmark was
rerun. This is a new unpreauthorized measurement-integrity failure, so execution
parked pending direction. Exact counts and raw evidence are preserved in
`measurement-integrity-audit.log`.
