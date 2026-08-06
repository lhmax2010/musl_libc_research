# Continue execution status — 2026-08-06

## Executed command

```bash
scripts/build_gbs.sh
```

GBS elapsed time before failure: 249 seconds. The build successfully recognized
the Git source package, downloaded and installed the armv7l buildroot, and
entered the spec `%build` section.

## Failure

The frozen Source1 gate failed before compiler selection and before musl was
built:

```text
BUILD_GATE_FAIL: Source1 sha256 mismatch expected=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4 actual=f21136ed8ec1d6ed950aaafbfe1c5438c779a78e71fb51b9ca58c160001e7d3f
```

Read-only inspection established:

- `packaging/musl-1.2.5.tar.gz` remains the official archive with SHA-256
  `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4`.
- GBS logged `Creating (native) source archive musl-1.2.5.tar.gz` and exported
  a tarball with SHA-256
  `f21136ed8ec1d6ed950aaafbfe1c5438c779a78e71fb51b9ca58c160001e7d3f`.
- Listing that exported tarball shows the complete workspace (`README.md`,
  `config/`, `docs/`, `packaging/`, `results/`, and `scripts/`) rather than the
  official musl source tree.
- The same `f21136…` file was copied into the chroot RPM SOURCES directory.

This is a GBS native-source archive basename collision. It is not an upstream
musl integrity failure, and the fail-closed gate behaved as designed. The
continue-execution prompt did not pre-authorize a fix for this failure type, so
no spec, Source tag, archive name, or gate logic was changed and the build was
not retried.

## Produced and missing artifacts

- `results/logs/gbs-build.log`: produced; contains the complete failure log.
- RPM: not produced (`Total succeeded built packages: (0)`).
- `results/logs/compiler-decision.txt`: NOT_RUN because the Source1 gate runs
  first.
- `build-commands.txt`: NOT_RUN.
- Deploy and board smoke: NOT_RUN because no RPM exists.
- `results/results.txt`: NOT_RUN.
- `results/report.md`: NOT_RUN.

## Exact continuation commands

After FatTank approves a Source1 basename-collision fix:

```bash
scripts/build_gbs.sh
SDB_TARGET=192.168.108.25 scripts/deploy.sh
SDB_TARGET=192.168.108.25 scripts/run_board.sh
python3 scripts/gen_report.py results/results.txt > results/report.md
```
