# Reproduction acceptance criteria

Acceptance has two mandatory layers. L1 establishes that the artifact and data
are structurally trustworthy. L2 checks whether the conclusion directions and
minimum effect magnitudes reproduce on hardware whose absolute timings may
differ. A run is accepted only when every L1 and L2 item is `PASS`.

## L1: build, deployment, and measurement integrity

The verifier requires all of the following hard gates:

| Area | Required evidence |
|---|---|
| Source export and hashes | `SOURCE_PREFLIGHT_PASS count=7`, Source1 SHA-256 PASS, Source5 SHA-256 PASS |
| Compiler and runtime | clang 22.1.8, one selected builtins archive, `rtlib_consistency=PASS` |
| mimalloc construction | resource `stdatomic.h` PASS, forbidden LFS64 scan PASS, allowed command delta PASS, required allocator symbols owned by `mimalloc.o` |
| ELF and ABI | static/dynamic structure gates PASS, package-private musl interpreter, ELF32 ARM softfp consistency PASS, final `BUILD_GATE_PASS` and `BUILD_GBS_PASS` |
| Deployment | payload manifest PASS, host/board binary hashes equal, all four smoke probes complete, package-private musl loader works |
| Allocator runtime | mimalloc banner present for `micro.musl-mi` and absent for all three controls; aggregate one-positive/three-negative gate PASS |
| Board controls | no residual probe before/after, performance governors recorded, frequency snapshots valid, measurement completion marker present |
| Baseline startup | at least 30 complete VALID triples; any declared INVALID round is retained and excluded mechanically |
| Baseline malloc | every cell has at least five VALID samples after an explicitly supplied supplement; incomplete samples remain INVALID and never contribute values |
| Allocator startup | at least 30 complete VALID quads |
| Allocator malloc | at least five VALID samples in each of eight variant/thread cells; every declared-sentinel sample has exactly one sentinel and all four required keys; no INVALID sample |
| Allocator memory/threads | at least three VALID memory samples per variant and one VALID 200-thread sample per variant; no INVALID sample |
| Baseline qualitative probes | all three variants have `localhost` and external-name DNS records plus default and `ko_KR.UTF-8` locale records; external DNS success itself is not required |

The shipped baseline deliberately contains one truncated malloc sample marked
INVALID and a separately authorized supplement. L1 requires the parser to
identify and exclude it; it does not pretend the sample never existed. A new
sentinel-enabled allocator session is expected to have zero INVALID samples.

## L2: directional and magnitude checks

L2 compares reproduced values with the reference values in
`docs/reference-results.json`, but does not require numerical equality.

| Check | Hard criterion | Reference value |
|---|---:|---:|
| Paired startup delta, musl-static versus glibc-dyn | `<= -30%` | `-58.1%` |
| 200-thread VmSize, glibc divided by musl-static | `>= 20x` | `57.84x` |
| Four-thread mallocng time divided by glibc time | `>= 2x` | `4.79x` |
| Four-thread mimalloc time divided by mallocng time | `<= 0.5` | `0.193x` |
| Median `Private_Dirty` | musl-static `<` glibc | `8 kB < 76 kB` |

The startup value is the median of paired relative differences for valid
rounds. Malloc ratios use the median of all VALID samples in each cell. Memory
uses the median of VALID samples. L2 validates reproducible conclusion direction
and a deliberately broad minimum magnitude; it does not validate identical
timings or byte-for-byte performance results.

## Verifier command and statuses

Run the package baseline:

```bash
python3 scripts/verify_reproduction.py
```

Or supply reproduced paths:

```bash
python3 scripts/verify_reproduction.py \
  --results "$REPO_ROOT/results/results.txt" \
  --supplement "$REPO_ROOT/results/results-supplement.txt" \
  --mimalloc-results "$REPO_ROOT/tmp/reproduction/results-mimalloc.txt" \
  --evidence-root "$REPO_ROOT/results" \
  --build-log "$REPO_ROOT/results/logs/gbs-build-mimalloc.log" \
  --deploy-log "$REPO_ROOT/tmp/reproduction/deploy.log" \
  --reference "$REPO_ROOT/docs/reference-results.json"
```

Each item prints one of:

- `PASS`: required evidence exists and the criterion is satisfied;
- `FAIL`: evidence is present but contradicts a hard gate or threshold;
- `INCONCLUSIVE`: required input is absent or cannot be parsed, so no direction
  may be claimed.

Exit code `0` means every L1 and L2 item passed. Exit code `1` means at least
one item failed. Exit code `2` means there was no explicit failure but at least
one item was inconclusive. Inputs are read-only; the verifier writes nothing.
