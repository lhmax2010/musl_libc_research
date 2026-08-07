# Independent reproduction guide

## 1. Prerequisites

| Requirement | Reference environment / purpose |
|---|---|
| Host | x86_64 Linux with enough storage for a GBS armv7l buildroot |
| GBS | 2.0.6 in the recorded successful build; `gbs`, `rpm2cpio`, and `cpio` must be on `PATH` |
| Source tools | Bash, curl, GnuPG, awk, sed, sha1sum, sha256sum, and sha512sum |
| Reporting | Python 3 using only the standard library |
| Board transport | `sdb`, with permission to connect and enable root mode |
| Target ABI | Tizen armv7l softfp; RPI4 is the reference board. Another armv7l softfp board is usable because the build gate compares the generated ABI with chroot `/bin/sh` |
| Board state | No competing load during measurement; CPU frequency controls and `/proc`/`sysfs` interfaces used by the script must be available |

The host must reach these public endpoints:

- `https://musl.libc.org` for the musl archive, signature, and public key;
- `https://github.com` and `https://raw.githubusercontent.com` for pinned hash
  records and the mimalloc release archive;
- `https://download.tizen.org` for the two pinned GBS repositories;
- `https://gitlab.alpinelinux.org` is attempted as an optional corroborating
  source. Its absence does not pass a bad digest and does not remove the
  requirement for two confirmed musl sources.

Initialize parameterized paths from the repository root:

```bash
export REPO_ROOT="$PWD"
export SDB_TARGET="${SDB_TARGET:?set SDB_TARGET to the reachable board address}"
cd "$REPO_ROOT"
mkdir -p "$REPO_ROOT/tmp/reproduction"
```

Do not substitute a personal path into this guide or a committed template.

## 2. Evidence integrity

Historical logs and evidence intentionally retain the original operator
environment paths; sanitizing them would rewrite commit history and invalidate
the SHA-anchored evidence chain.

Those historical strings are evidence, not configuration. New commands use
`$HOME`, `$REPO_ROOT`, and `$SDB_TARGET`. Do not run filter-repo, BFG, a
force-push, or any other history rewrite.

## 3. Prepare the pinned GBS configuration

The checked-in `config/gbs_llvm.conf` is retained as original evidence. For a
byte-comparable chroot, render the example that pins the two dated snapshots:

```bash
sed "s|\\\$REPO_ROOT|$REPO_ROOT|g" \
  "$REPO_ROOT/config/gbs_llvm.conf.example" \
  > "$REPO_ROOT/tmp/gbs_llvm.repro.conf"
export GBS_CONFIG="$REPO_ROOT/tmp/gbs_llvm.repro.conf"
export GBS_ROOT="$REPO_ROOT/tmp/GBS-ROOT-TIZEN-UNIFIED-LLVM-CODES"
```

The timestamps `20260722.045200` and `20260725.003315` are part of the
reproduction environment. Do not replace them with `reference` or a newer
snapshot when byte-comparable chroot contents are required.

## 4. Fetch and verify musl 1.2.5

```bash
scripts/fetch_musl.sh
```

Expected duration is under five minutes on a normal connection; an intact
frozen archive takes only seconds through the idempotent path. A full successful
run ends with output equivalent to:

```text
source_verdict.S1-richfelker=PASS
source_verdict.S3-buildroot=PASS
source_verdict.S4-gpg=PASS
independent_sources_confirmed=2
consensus=PASS
```

An existing valid archive may instead report `short_circuit=PASS`. The
trust-root records are:

| Record | Pinned URL / value |
|---|---|
| Official archive | `https://musl.libc.org/releases/musl-1.2.5.tar.gz` |
| Official signature | `https://musl.libc.org/releases/musl-1.2.5.tar.gz.asc` |
| Official key | `https://musl.libc.org/musl.pub`; fingerprint `836489290BB6B70F99FFDA0556BCDB593020450F` |
| Rich Felker record | `https://raw.githubusercontent.com/richfelker/musl-cross-make/master/hashes/musl-1.2.5.tar.gz.sha1` |
| Buildroot record | `https://raw.githubusercontent.com/buildroot/buildroot/f7f03445cf320adbbc41270a806b38c911d3454a/package/musl/musl.hash` |
| Frozen SHA-256 | `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4` |

Do not continue after a mismatch or fewer than two confirmed digest sources.

## 5. Fetch and independently review mimalloc 2.1.7

```bash
scripts/fetch_mimalloc.sh
```

Expected duration is under five minutes. Success includes:

```text
frozen_sha256_verdict=PASS
source_verdict.vcpkg=PASS
source_verdict.conan_center=PASS
independent_sources_confirmed=2
validation=PASS
```

Reviewer sign-off is a human gate, not an automation step. Independently open
and compare every record below before checking the box:

| Record | Pinned URL / value |
|---|---|
| Official archive | `https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.7.tar.gz` |
| vcpkg port | `https://raw.githubusercontent.com/microsoft/vcpkg/d8e2b83a6b6981e7e019b9b6ad8884be1765720a/ports/mimalloc/portfile.cmake` |
| vcpkg manifest | `https://raw.githubusercontent.com/microsoft/vcpkg/d8e2b83a6b6981e7e019b9b6ad8884be1765720a/ports/mimalloc/vcpkg.json` |
| Conan Center record | `https://raw.githubusercontent.com/conan-io/conan-center-index/a8ab0ecbeaa1eeba447d8fccda1c43f110cdbdc3/recipes/mimalloc/all/conandata.yml` |
| Frozen SHA-256 | `0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d` |
| Frozen SHA-512 | `4e30976758015c76a146acc1bfc8501e2e5c61b81db77d253de0d58a8edef987669243f232210667b32ef8da3a33286642acb56ba526fd24c4ba925b44403730` |

Then create an untracked sign-off:

```bash
cp "$REPO_ROOT/config/reviewer-signoff.example.md" \
  "$REPO_ROOT/tmp/reviewer-signoff.md"
${EDITOR:-vi} "$REPO_ROOT/tmp/reviewer-signoff.md"
export MIMALLOC_REVIEW_FILE="$REPO_ROOT/tmp/reviewer-signoff.md"
```

Change `[ ]` to `[x]` only after the independent check. The build script accepts
the external Reviewer line and retains compatibility with the historical
FatTank record; it never checks the box itself.

## 6. Build the release-2 RPM

```bash
MIMALLOC_REVIEW_FILE="$MIMALLOC_REVIEW_FILE" \
GBS_CONFIG="$GBS_CONFIG" \
GBS_ROOT="$GBS_ROOT" \
scripts/build_gbs.sh
```

Allow 10–25 minutes for a cold build. The expected sequence is:

```text
SOURCE_PREFLIGHT_PASS count=7
gate.source1_sha256=PASS
gate.source5_sha256=PASS
gate.mimalloc_lfs64_symbols=PASS
gate.musl_mi_command_delta=PASS
gate.arm32_softfp_abi_consistency=PASS
BUILD_GATE_PASS: all comparison artifacts passed
BUILD_GBS_PASS
```

Confirm the release-2 RPM:

```bash
sha256sum "$REPO_ROOT/results/rpms/musl-libc-demo-1.0.0-2.armv7l.rpm"
```

The reference digest is
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
A different rebuild digest is not automatically a functional failure, but all
L1 build gates and the reproduced payload manifest must pass. Record the new
digest rather than replacing the reference record.

## 7. Deploy and run the runtime controls — requires board

Do not run this step during a host-only dry run. With a board reserved and no
competing workload:

```bash
SDB_TARGET="$SDB_TARGET" \
RPM_PATH="$REPO_ROOT/results/rpms/musl-libc-demo-1.0.0-2.armv7l.rpm" \
DEPLOY_LOG_FILE="$REPO_ROOT/tmp/reproduction/deploy.log" \
scripts/deploy.sh
```

Expected duration is one to three minutes. Success includes the RPM payload
hash checks, four smoke probes, and exactly one positive plus three negative
mimalloc banner controls:

```text
binary_hash_comparison=PASS
gate.runtime_mimalloc_override=PASS positive=1 negative_controls=3
DEPLOY_PASS musl-dyn used package interpreter /opt/usr/musl-demo/lib/ld-musl-arm.so.1 and mimalloc override passed
```

The script uses `rpm -Uvh --noplugins --force` because the reference Tizen
security plugin cannot update Smack policy in this environment. It does not
change system Smack configuration.

## 8. Run the four-variant board session — requires board

```bash
SDB_TARGET="$SDB_TARGET" \
RESULT_FILE="$REPO_ROOT/tmp/reproduction/results-mimalloc.txt" \
REPORT_FILE="$REPO_ROOT/tmp/reproduction/report-mimalloc.md" \
scripts/run_board.sh
```

Expected duration is approximately two to five minutes on the reference board.
Do not run other board workloads concurrently. Expected terminal output is:

```text
MEASUREMENT_PASS results=... report=...
```

The new result must contain 30 startup quads, 40 malloc samples, 12 memory
samples, four thread samples, independent sentinels, no residual probe process,
and no INVALID sample. DNS and locale are explicitly recorded as `NOT_RUN` in
this allocator-focused extension; their immutable baseline observations remain
in `results/results.txt` and `results/report.md`.

## 9. Generate reports

Regenerate the immutable baseline report without modifying raw input:

```bash
python3 scripts/gen_report.py \
  "$REPO_ROOT/results/results.txt" \
  "$REPO_ROOT/results/logs/compiler-decision.txt" \
  > "$REPO_ROOT/tmp/reproduction/report.md"
```

Regenerate the new allocator report if `run_board.sh` did not already do so:

```bash
python3 scripts/gen_report.py \
  "$REPO_ROOT/tmp/reproduction/results-mimalloc.txt" \
  "$REPO_ROOT/results/logs/compiler-decision-mimalloc.txt" \
  > "$REPO_ROOT/tmp/reproduction/report-mimalloc.md"
```

Each command normally takes less than one second. The generator never writes
the input result files.

## 10. Verify acceptance

For the shipped self-test baseline:

```bash
python3 scripts/verify_reproduction.py
```

For a new allocator session while retaining the shipped baseline DNS/locale
evidence:

```bash
python3 scripts/verify_reproduction.py \
  --results "$REPO_ROOT/results/results.txt" \
  --supplement "$REPO_ROOT/results/results-supplement.txt" \
  --mimalloc-results "$REPO_ROOT/tmp/reproduction/results-mimalloc.txt" \
  --evidence-root "$REPO_ROOT/results" \
  --build-log "$REPO_ROOT/results/logs/gbs-build-mimalloc.log" \
  --deploy-log "$REPO_ROOT/tmp/reproduction/deploy.log"
```

The verifier prints every L1 and L2 item and exits zero only when both layers
pass. See `docs/ACCEPTANCE_EN.md` for exact semantics.

## 11. Troubleshooting

| Symptom | Root cause | Authorized treatment / evidence |
|---|---|---|
| GBS reports that the generated `musl-1.2.5.tar.gz` differs and Source1 later fails | `gbs export`/gbp treated the version-shaped official archive as an orig archive and replaced it from the Git tree | Keep the `.frozen` Source name, copy it back to the canonical name in `%prep`, and retain the dual hash gate. See `incident-gbs-orig-clobber.md` |
| rpmbuild reports `second %prep` although the spec appears to contain one section | RPM expands macro tokens even in comments; a literal section token in prose became another declaration | Avoid percent-sign macro tokens in spec comments. See `incident-spec-comment-macro.md` |
| Chroot build says `mapfile: command not found` | The target chroot runs Bash 3.2.57; `mapfile` requires Bash 4 | Use the checked-in Bash-3.2-compatible `while read` array append. See `incident-bash32-mapfile.md` |
| musl-static reports unresolved `__aeabi_*div*` symbols although `libgcc.a` was loaded | The wrapper appended `-lc` after the compiler-driver runtime archive; one-pass archive scanning had already passed the builtins | The installed wrapper is mechanically patched to group `-lc` with the absolute runtime archive; do not use `--whole-archive`. See `incident-musl-libgcc-aeabi.md` and `incident-musl-ldwrapper-group.md` |
| Expected armhf loader/VFP-register gate fails; actual loader is `ld-musl-arm.so.1` | Tizen armv7l uses softfp; the earlier hard-float assumption was wrong | Preserve platform `%optflags`, use the arm loader name, and require four-way ABI consistency with chroot `/bin/sh`. See `incident-softfp-abi-alignment.md` |
| RPM transaction fails while writing Smack/device security policy | Tizen's RPM security plugin cannot update policy in this board environment; the package payload itself is not at fault | Use `rpm --noplugins`, then verify RPM database/payload hashes, labels, smoke, and runtime controls. Do not remount or alter Smack policy. See `incident-board-rpm-smack.md` |
| A malloc sample ends mid-line and the next header is concatenated | `sdb shell` output was not fully drained; the original parser lacked completeness checks | Keep the raw sample, mark it INVALID at the mid-line header, require four keys and a sentinel, and place any authorized replacement in a separate file. See `incident-board-measurement-malloc-truncation.md` |
| GBS `%prep` cannot find `mimalloc-2.1.7.sha256` | The spec Source6 file was present under `scripts/` but absent from `packaging/`, so GBS did not export it | Keep the byte-identical packaging copy and the pre-GBS `SourceN` existence check. See `incident-mimalloc-source6-export.md` |
| `mimalloc.o` has an unresolved `mmap64` reference | It was compiled against glibc LFS headers, but musl 1.2.5 does not provide that removed alias | Compile the object in the musl header environment and retain the forbidden-LFS64 undefined-symbol gate. See `incident-mimalloc-mmap64-link.md` |
| mimalloc compilation cannot find `stdatomic.h` | `musl-clang -nostdinc` also hides clang's compiler-resource headers; musl does not supply this compiler header | Add only clang's explicit resource include after the musl include path and keep the order gate. See `incident-mimalloc-stdatomic-include.md` |
| glibc probe lists the platform loader as a dependency | The Tizen platform toolchain emits this known loader dependency for the glibc probe | It is a narrowly pre-authorized platform exception; other unexpected dependencies still fail. See `incident-glibc-loader-needed.md` |
| A gate-clean rebuild has different RPM or binary SHA-256 values than the reviewed reference | RPM/build outputs embed build-instance inputs such as build time, host, and file mtimes; bit-reproducible output is not claimed | Do not compare hashes across builds. Require L1 gates and L2 conclusion direction, then use deploy-time host/board hash equality for the same artifacts. The host dry-run observed `b4d952dc…f49f4` versus reference `f55957aa…30ead`; see `results/logs/repro-host-dry-run-summary.md` and `docs/ACCEPTANCE_EN.md` |

For any symptom outside these documented cases, stop, archive the exact output,
and investigate before changing a gate or build variable.
