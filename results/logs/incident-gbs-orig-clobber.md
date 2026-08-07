# Incident: GBS gbp orig clobbered musl Source1

Date: 2026-08-06

## Symptom and gate evidence

The first Git-backed GBS build exported successfully, entered `%build`, and
then stopped at the frozen Source1 integrity gate. The original lines in
`results/logs/gbs-build.log` were:

```text
BUILD_GATE_FAIL: Source1 sha256 mismatch expected=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4 actual=f21136ed8ec1d6ed950aaafbfe1c5438c779a78e71fb51b9ca58c160001e7d3f
```

GBS had previously logged:

```text
info: Creating (native) source archive musl-1.2.5.tar.gz from '019d2a09851752925680e0ec2d82fcf2890c491c'
```

The exported `f21136…` archive contained the complete Git workspace rather
than the official musl source tree. The same file reached the chroot RPM
SOURCES directory. The double-check gate therefore prevented an untrusted
substitution from entering the build.

## Root cause

GBS export's gbp orig heuristic treated the first archive-shaped, versioned
spec Source as the native package upstream archive and regenerated that exact
basename from the Git tree, clobbering the official `musl-1.2.5.tar.gz` in the
export directory.

## Authorized fix

Source1 is stored as `musl-1.2.5.tar.gz.frozen`, whose suffix is outside the
archive heuristic. `%prep` copies it back to the canonical
`musl-1.2.5.tar.gz` build-local name. `build-demo.sh` and every integrity/ELF
gate remain unchanged.

Content identity was checked immediately around `git mv`:

```text
rename_before.path=packaging/musl-1.2.5.tar.gz
rename_before.sha256=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
rename_after.path=packaging/musl-1.2.5.tar.gz.frozen
rename_after.sha256=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
```

## Rerun evidence

The authorized rerun was started with:

```bash
scripts/build_gbs.sh
```

GBS stopped during export, before creating an export archive and before the
Source1 integrity gate:

```text
error: RPM error while parsing None: can't parse specfile
 (error: line 30: second %prep)
error: <gbs>Failed to export packaging files from git tree
=== Total succeeded built packages: (0) ===
```

Read-only inspection identified the literal `%prep` in the new explanatory
comment immediately before `Source1`; the real `%prep` section is at spec line
30. The GBS parser treated the comment token as a section despite the comment
marker. This failure was not among the prompt's pre-authorized corrections, so
the comment, spec, and gate logic were not changed and no further build was
attempted.

Consequently, no RPM, compiler decision, build commands, deployment, board
measurement, or report was produced in this rerun.

## Subsequent validation

After the spec-comment issue received a separate authorized fix, GBS export
completed without regenerating `musl-1.2.5.tar.gz.frozen`. The exported file
retained SHA-256
`a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4`,
and the chroot emitted:

```text
gate.source1_sha256=PASS value=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
```

This confirms that the `.frozen` suffix resolved the original clobber and
that the integrity chain remained intact. A later, unrelated Bash compatibility
failure stopped that build and is recorded separately.
