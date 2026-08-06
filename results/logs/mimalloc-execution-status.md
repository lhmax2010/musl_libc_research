# mimalloc fourth-variant execution status

Date: 2026-08-06

## Source validation and FatTank review: PASS

The official mimalloc v2.1.7 release archive has SHA-256
`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`
and SHA-512
`4e30976758015c76a146acc1bfc8501e2e5c61b81db77d253de0d58a8edef987669243f232210667b32ef8da3a33286642acb56ba526fd24c4ba925b44403730`.
Conan Center Index publishes the same SHA-256 and vcpkg publishes the same
SHA-512 for version 2.1.7. Raw fixed-commit records are archived under
`results/logs/mimalloc-hash-sources/`; `fetch-mimalloc.log` records two
confirmed independent sources.

FatTank review was explicitly confirmed and the checkbox in
`mimalloc-source-review.md` is checked. The formal build gate opened.

## Source6 remediation: PASS

`packaging/mimalloc-2.1.7.sha256` is byte-identical to the reviewed scripts
copy. The new host preflight parsed Source0 through Source6 and found every
same-named packaging file before invoking GBS. The authorized fix is commit
`28c976f`; full self-check output is in `source6-packaging-fix.log`.

## clang resource-header remediation: PASS

Commit `6ffd58c` changed only the authorized compile environment and added the
specified LFS64 family gate and decision record. Commit `87b0b6c` added only the
explicit clang resource include to that mimalloc compile invocation, preserving
the wrapper and its `-nostdinc`. The wrapper's musl include remains before the
user argument segment, so the resource directory only fills missing headers.

```text
gate.mimalloc_resource_dir=/usr/lib/clang/22
gate.mimalloc_stdatomic_header=PASS path=/usr/lib/clang/22/include/stdatomic.h
gate.mimalloc_lfs64_symbols.scan_begin
gate.mimalloc_lfs64_symbols.scan_end
gate.mimalloc_lfs64_symbols=PASS
```

The empty scan region is the raw evidence that no forbidden LFS64-family symbol
was present. No unresolved `__atomic_*` symbol was found. The fourth variant
linked, all seven allocator symbols were owned by `mimalloc.o`, all ELF and
softfp gates passed, and the compiler decision records the resolved resource
path and musl-first include order. See `incident-mimalloc-stdatomic-include.md`.

## Formal host build: PASS

`BUILD_GATE_PASS` and `BUILD_GBS_PASS` are both present. GBS produced
`results/rpms/musl-libc-demo-1.0.0-2.armv7l.rpm` with SHA-256
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
The extracted artifact digests, compiler decision, and full mimalloc link map
are archived in `results/`.

## Implementation verified by host build

- Source5/Source6, canonical prep names, RPM payload, artifact hashes,
  pre-strip sizes, and the full link map include `micro.musl-mi`.
- The existing three variant commands remain unchanged. The fourth static link
  core is mechanically checked to differ only by `mimalloc.o`.
- New gates cover static ELF structure, no interpreter/NEEDED/GLIBC markers,
  ARM32 softfp consistency, all seven allocator-family symbol owners, and an
  `mi_` text symbol before stripping.
- Deployment captures one positive mimalloc verbose banner and three negative
  controls before passing.
- Board measurement writes only `results/results-mimalloc.txt`, rotates four
  variants within each startup/malloc round, retains sentinels and platform
  gates, and does not rerun allocator-independent DNS/locale probes.
- Report generation supports the four-way malloc table, startup medians, and
  Pss/Private_Dirty/VmSize/binary-size cost table. Four unit tests pass and the
  existing report regenerates byte-identically.

`packaging/micro.c` and `packaging/timer.c` match their committed blobs exactly.
The original `results/results.txt` remains unchanged at SHA-256
`78a1b548df00c7742e3fa5d3cca598faa1da5bdfccdf28c365e019bf5ee596f1`.

## Release 2 deployment and runtime gate: PASS

The released board window was used only after a read-only load check found no
residual demo process and no running user process other than the check itself.
Scheme A installed release 2 with `rpm -Uvh --noplugins --force`, preserving RPM
database semantics. The board-side RPM SHA-256 exactly matched
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
Package artifact hashes, host/board binary hashes, four smoke probes, and the
private musl loader all passed. Smack labels remained `User::Shell`.

The verbose runtime gate observed a mimalloc banner only for `micro.musl-mi`;
glibc-dyn, musl-static, and musl-dyn were clean negative controls. Full evidence
is in `deploy-mimalloc.log`, the four runtime logs, and
`board-rpm-release2-sha256.log`.

## Four-variant board measurement: PASS

One uninterrupted session ran 30 alternating startup quads, 12 mem samples,
four thread samples, and 40 alternating malloc samples. All 30 startup rounds
were frequency-valid, all 56 sentinel-bearing samples were complete, and the
final INVALID counts were startup 0, malloc 0, and mem/threads 0. The four CPUs
remained at 1.5 GHz with the performance governor. Temperature rose from
34.563 C to 39.433 C. Residual demo processes were NONE before and after, and no
other board command was launched during measurement.

`results/results-mimalloc.txt` is now immutable at SHA-256
`3ddc357e6dfe60dad842c9ec10aa9029a333bb8b3aab90fe79ec42240d4d842c`.
The data-filled report regenerates byte-identically when invoked with the same
absolute provenance paths, and all four parser unit tests pass. DNS and locale
remain explicitly carried from the previous allocator-independent run.

Execution completed through the authorized board and report boundary. The
report records measured values and caveats; this status file does not add a
separate performance conclusion.
