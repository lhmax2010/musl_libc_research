# HQ reproduction package host dry-run summary

## Result

`PASS`. The complete console transcript is
`results/logs/repro-host-dry-run.log`, SHA-256
`c84c0bf4bcf84a6b189b00c339f4c1cc52aace5e86229cf6a784e9b0fb57a661`.

The run used an isolated clone under `$REPO_ROOT/tmp/` so the checked-in raw
measurements and historical build/deploy evidence were not modified. It ran
from 2026-08-07T10:55:25Z to 2026-08-07T10:59:36Z.

## Executed host steps

- rendered `config/gbs_llvm.conf.example` and verified both pinned snapshot
  timestamps;
- ran `scripts/fetch_musl.sh` through its frozen-archive short circuit;
- ran `scripts/fetch_mimalloc.sh` and confirmed both fixed-commit digest
  sources;
- exercised the external Reviewer sign-off accepted by `scripts/build_gbs.sh`;
- created a cold 105-package GBS 2.0.6 chroot and built release 2;
- passed Source0–Source6 preflight, both source hashes, clang 22.1.8,
  builtins consistency, mimalloc construction/ownership, ELF, private loader,
  and softfp ABI gates;
- generated both reports from immutable reference inputs;
- ran `scripts/verify_reproduction.py`: 18 PASS, 0 FAIL, 0 INCONCLUSIVE,
  exit code 0.

The decisive build markers were `BUILD_GATE_PASS` and `BUILD_GBS_PASS`. The
overall terminal marker was `HOST_DRY_RUN_PASS`.

## Artifact note

The isolated rebuild produced a valid `musl-libc-demo-1.0.0-2.armv7l.rpm` with
SHA-256 `b4d952dce5c4c673ea0dd027051e9f97121b8f830c36a8d7ac7c96cc5ccf49f4`.
It is not byte-identical to the reviewed reference RPM, whose SHA-256 is
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
The rebuilt payload manifest also differs bytewise, while the extracted
compiler-decision record is identical and every L1 construction gate passes.
The rebuild is dry-run evidence only; it does not replace the reviewed reference
RPM. Cross-build byte equality is not an L1 or L2 acceptance criterion.

## Board steps

Board work was intentionally not repeated during this host dry run:

```text
BOARD_STEP=deploy NOT_RUN reason=requires_board
BOARD_STEP=run_board NOT_RUN reason=requires_board
```

Exact parameterized commands are recorded in `docs/REPRODUCTION_EN.md` and at
the end of the full dry-run log. The package already contains the reviewed board
deployment, runtime-control, raw measurement, and report evidence used by the
self-test baseline.
