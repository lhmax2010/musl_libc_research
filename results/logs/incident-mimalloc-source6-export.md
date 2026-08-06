# Incident: mimalloc Source6 digest was not exported

Date: 2026-08-06

## Reached state

FatTank source review was explicitly confirmed and recorded. The frozen
mimalloc archive still matched SHA-256
`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`.
The formal `scripts/build_gbs.sh` run passed the host review gate, exported
release 2, initialized the armv7l chroot, and reached RPM prep. It did not reach
the Source5 hash gate or any compiler/linker gate.

## Failure

The exact first failing lines in `gbs-build-mimalloc.log` are:

```text
[   17s] + cp -p /home/abuild/rpmbuild/SOURCES/mimalloc-2.1.7.sha256 mimalloc-2.1.7.sha256
[   17s] cp: cannot stat `/home/abuild/rpmbuild/SOURCES/mimalloc-2.1.7.sha256': No such file or directory
[   17s] error: Bad exit status from /var/tmp/rpm-tmp.dX8NYR (%prep)
```

## Read-only diagnosis

The spec declares `Source6: mimalloc-2.1.7.sha256`, but the file exists only at
`scripts/mimalloc-2.1.7.sha256`. GBS exports spec sources from the packaging
surface. The exported source directory contains `musl-1.2.5.sha256` because
that digest has a tracked `packaging/` copy, but contains no mimalloc digest:

```text
build-demo.sh
micro.c
mimalloc-2.1.7.tar.gz.frozen
musl-1.2.5.sha256
musl-1.2.5.tar.gz.frozen
musl-libc-demo.spec
timer.c
```

The failure is therefore a packaging/export omission in the new implementation,
not a digest mismatch and not a mimalloc compile failure. No RPM was produced.

## Disposition

This failure was not preauthorized. No file was copied, no spec/source mapping
was changed, and no rerun was attempted. The likely minimal remediation is to
provide a tracked packaging-side Source6 file byte-identical to the reviewed
digest, following the existing Source3 layout, but that action requires an
explicit authorization prompt.

Deployment, the four runtime banner gates, the four-variant board session, and
the data-filled report remain NOT_RUN. Execution is parked without a performance
conclusion.

## Authorized remediation

The packaging surface now contains `packaging/mimalloc-2.1.7.sha256`, copied
byte-for-byte from the reviewed `scripts/mimalloc-2.1.7.sha256`. `diff` is
empty, and both files contain the exact FatTank-reviewed SHA-256
`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`.

`scripts/build_gbs.sh` now parses every `SourceN` declaration from the spec and
checks the same-named file under `packaging/` before invoking GBS. It reports
each Source0 through Source6 individually, prints a complete missing list on
failure, and exits 8 without entering GBS if any source is absent. The initial
full scan passed all seven declarations. Mechanical self-check output is
archived in `source6-packaging-fix.log`.
