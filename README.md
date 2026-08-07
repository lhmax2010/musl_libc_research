# Tizen armv7l libc and allocator reproduction package

This repository is an evidence-preserving reproduction package for a controlled
comparison of Tizen glibc, musl 1.2.5, and musl 1.2.5 with mimalloc 2.1.7. Four
probe variants are built by GBS in one pinned Tizen armv7l softfp chroot with
the same clang 22.1.8 and `%optflags`, deployed under a private prefix, measured
in alternating order on a reference RPI4 board, and checked by a scripted
two-level acceptance test.

## Package map

| Start here | Purpose |
|---|---|
| [`docs/TEST_PLAN_EN.md`](docs/TEST_PLAN_EN.md) | Scope, attribution design, metrics, controls, gates, statistics, and limitations |
| [`docs/REPRODUCTION_EN.md`](docs/REPRODUCTION_EN.md) | Independent source review, pinned build, board run, reporting, and troubleshooting |
| [`docs/ACCEPTANCE_EN.md`](docs/ACCEPTANCE_EN.md) | L1 integrity gates and L2 directional acceptance criteria |
| [`docs/reference-results.json`](docs/reference-results.json) | Machine-readable reference values with evidence pointers |
| [`scripts/verify_reproduction.py`](scripts/verify_reproduction.py) | Reproduction verifier; standard-library Python only |
| [`results/report.md`](results/report.md) | Three-variant baseline report, including DNS and locale observations |
| [`results/report-mimalloc.md`](results/report-mimalloc.md) | Four-variant allocator report |
| [`results/results.txt`](results/results.txt) | Immutable baseline board output |
| [`results/results-supplement.txt`](results/results-supplement.txt) | Immutable authorized supplement for one truncated baseline sample |
| [`results/results-mimalloc.txt`](results/results-mimalloc.txt) | Immutable four-variant board output |
| [`results/logs/`](results/logs/) | Build, deploy, integrity, measurement, and incident evidence |
| [`LICENSES/`](LICENSES/) and [`NOTICE.md`](NOTICE.md) | Third-party license texts and component notice |

## Reproduction outline

Use a fresh clone or an extracted release archive, then follow the commands and
reviewer sign-off procedure in `docs/REPRODUCTION_EN.md`. The high-level flow is:

```bash
export REPO_ROOT="$PWD"
cd "$REPO_ROOT"
scripts/fetch_musl.sh
scripts/fetch_mimalloc.sh
# Complete the independent Reviewer sign-off described in the guide.
MIMALLOC_REVIEW_FILE="$REPO_ROOT/tmp/reviewer-signoff.md" scripts/build_gbs.sh
# The remaining commands require a reachable Tizen armv7l softfp board.
SDB_TARGET="$SDB_TARGET" scripts/deploy.sh
SDB_TARGET="$SDB_TARGET" scripts/run_board.sh
python3 scripts/verify_reproduction.py
```

The RPM installs only below `/opt/usr/musl-demo`; it does not replace or
advertise a system libc. All gates fail closed. Do not bypass source hashes,
compiler/ABI/ELF checks, payload hashes, the mimalloc positive/negative runtime
controls, frequency controls, sentinels, or INVALID-sample handling.

## Reference artifact

The reviewed release-2 RPM is
`results/rpms/musl-libc-demo-1.0.0-2.armv7l.rpm`, SHA-256
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
The annotated tag `demo-v1.0-repro` identifies the complete reproduction
package; its tag message records the RPM and raw-result hashes.
