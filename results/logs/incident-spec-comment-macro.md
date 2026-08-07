# Incident: RPM macro token in a spec comment

Date: 2026-08-06

## Symptom

The first GBS rerun after the Source1 `.frozen` fix stopped while exporting
packaging files:

```text
error: RPM error while parsing None: can't parse specfile
 (error: line 30: second %prep)
error: <gbs>Failed to export packaging files from git tree
```

## Root cause

The new Source1 explanatory comment contained a literal RPM section token.
RPM spec comments still pass through macro/section parsing, so GBS treated the
comment token as the first section and the real section at line 30 as a
duplicate.

## Authorized fix

Commit `bc76088` rewrote the comment as plain prose without any percent-sign
macro notation. No Source, build, or gate behavior changed.

The required full-comment self-check produced:

```text
self_check.command=grep -n '^#.*%' packaging/musl-libc-demo.spec
self_check.exit_code=1
self_check.output=<no matches>
rpmspec_parse=PASS
```

Lesson: explanatory comments in RPM specs must avoid percent-sign macro and
section notation rather than relying on comment semantics or escaping.

## Rerun evidence

The next GBS run exported the package and reached the Source1 gate, proving the
parser issue was resolved:

```text
gate.source1_sha256=PASS value=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
```

It then stopped at a new, unpreauthorized environment compatibility failure:

```text
./build-demo.sh: line 54: mapfile: command not found
find: `(runtime dir is not present)': No such file or directory
=== Total succeeded built packages: (0) ===
```

The chroot package set contains Bash 3.2.57, which predates the `mapfile`
builtin. Per execution discipline, `build-demo.sh` was not changed and the
build was not retried. No RPM, compiler decision, deployment, measurement, or
report was produced.
