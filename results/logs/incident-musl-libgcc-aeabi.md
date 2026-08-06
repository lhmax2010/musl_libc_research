# Incident: unresolved ARM EABI builtins in musl-static link

Date: 2026-08-06

## Reached state

The GBS run passed export, Source1 integrity, clang version, Bash compatibility,
and runtime-library consistency checks. The failed-build evidence recorded:

```text
clang version 22.1.8
Target: armv7l-tizen-linux-gnueabi
selected_rtlib=libgcc.a
selected_rtlib_archive=/usr/bin/../lib/gcc/armv7l-tizen-linux-gnueabi/14.2.0/libgcc.a
rtlib_consistency=PASS
```

musl configured with clang, built, and installed both `musl-clang` wrappers.
`micro.glibc-dyn` linked, after which `micro.musl-static` failed.

## Failure

The linker reported unresolved builtins introduced by musl objects, including:

```text
undefined reference to `__aeabi_uidiv'
undefined reference to `__aeabi_idiv'
undefined reference to `__aeabi_uldivmod'
undefined reference to `__aeabi_uidivmod'
undefined reference to `__aeabi_ldivmod'
```

Read-only inspection of `micro.musl-static.map` confirmed that the selected
`libgcc.a` and `libgcc_eh.a` were loaded and supplied other ARM EABI symbols,
but the division helpers above remained unresolved. The failed build reached
only the glibc-dynamic and musl-static compile commands; musl-dynamic, timer,
strip, ELF gates, artifact hashes, and RPM packaging did not run.

This is a new, unpreauthorized link failure. No wrapper, link order, compiler,
runtime-library selection, or gate logic was changed, and the build was not
retried. Deployment, board measurement, and report generation remain NOT_RUN.

## Authorized follow-up

The subsequent authorization identified the `ld.musl-clang` archive ordering
as the root cause and allowed a bounded start group around `-lc`, the selected
absolute `libgcc.a`, and the same-directory `libgcc_eh.a`. Commit `6e8ba8a`
implemented only that wrapper post-processing step.

The next GBS run logged both `gate.ldwrapper_patch=PASS style=ld` and
`gate.micro.musl-static=PASS`, confirming that the group resolved this incident.
The run then stopped at a separate musl-dynamic interpreter mismatch, archived
in `incident-musl-dyn-interpreter.md`.
