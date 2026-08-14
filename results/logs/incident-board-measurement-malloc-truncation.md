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

The original generated malloc table was therefore invalid and was not used.
The raw startup, memory, thread, DNS, and locale evidence remains archived.

## Root cause

The relevant dmesg filter showed only boot-time Smack initialization/denials
and an `oom_control` deprecation warning; it showed no corresponding OOM kill,
segfault, or micro-process event. The measurement-time journal filter returned
no matching lines.

The authorized root-cause determination is that the board-side single-sample
output was truncated because `sdb shell` output was not fully drained. The raw
sample has no trailing newline, so the next header was concatenated to its
partial `malloc.threads` line. No corresponding process exception was
recorded. The report parser also lacked a sample-completeness check and carried
subsequent numeric fields across the concatenated header, causing the silent
misattribution.

## Remediation and verification

- `scripts/gen_report.py` now splits and resynchronizes any recognized sample
  header found mid-line, marks the preceding partial malloc sample INVALID,
  and requires all four malloc keys before accepting a sample. The immutable
  original data regresses to exactly 29 VALID and 1 INVALID sample; the next
  musl-static sample retains its original attribution.
- `scripts/run_board.sh` now emits a standalone `sample_end=OK` after every
  successful probe. New sentinel-declared data marks a missing sentinel
  INVALID instead of accepting a silently truncated sample.
- `results/results-supplement.txt` contains the authorized rep=6, t=4,
  three-variant alternating supplement. Its governor, frequency, temperature,
  and residual-process gates passed; all three samples include the sentinel
  and are VALID.
- The report merges all and only VALID samples without selection or weighting.
  Final t=1 counts are 5/5/5; final t=4 counts are glibc-dyn 6,
  musl-static 6, and musl-dyn 5. The final combined set is 32 VALID and
  1 INVALID, with no new supplement INVALID.

The original `results/results.txt` was neither edited nor deleted and remains
SHA-256
`24ffb2ab105b3dcbe11c73a60aa0b5bfb18348062c748b19a40a6fff394d8faf`.
The parser regression, final completeness audit, and raw incident evidence are
preserved under `results/logs/`. The regenerated report is delivered for
FatTank data review; no performance conclusion is asserted here.

## Lesson

Transport completion must be an explicit property of every board probe.
Field cardinality alone cannot prove sample completeness: a terminal sentinel,
header-bound attribution, and required-key validation are all necessary.
