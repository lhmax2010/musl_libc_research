# Incident: musl wrapper suppresses clang stdatomic header

Date: 2026-08-06

## Reached state

The authorized musl-header remediation is commit `6ffd58c`. The formal rerun
passed the Source0--Source6 host preflight, GBS export, both frozen-source hash
gates, clang 22.1.8 selection, musl compilation, installation, and the existing
linker-wrapper patch gate. The recorded `mimalloc.o` command invokes
`musl-inst/bin/musl-clang` with the unchanged expanded RPM optflags.

## Failure

The first new failure in `gbs-build-mimalloc.log` is:

```text
[   14s] In file included from /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/static.c:17:
[   14s] In file included from /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/include/mimalloc/internal.h:17:
[   14s] In file included from /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/include/mimalloc/types.h:27:
[   14s] /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/include/mimalloc/atomic.h:41:10: fatal error: 'stdatomic.h' file not found
[   14s]    41 | #include <stdatomic.h>
[   14s]       |          ^~~~~~~~~~~~~
[   14s] 1 error generated.
[   14s] error: Bad exit status from /var/tmp/rpm-tmp.trMx7c (%build)
```

The object was not produced. Consequently the new LFS64 undefined-symbol gate,
all four variant links and later symbol/ELF/softfp gates were not reached.

## Read-only diagnosis

The installed musl wrapper invokes the same clang backend with this include
policy:

```text
-nostdinc
--sysroot /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/musl-inst
-isystem /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/musl-inst/include
```

The installed musl include tree has no `stdatomic.h`. Clang's compiler-resource
tree does contain it at `/usr/lib/clang/22/include/stdatomic.h`, but the
wrapper's `-nostdinc` suppresses compiler-provided standard include directories
as well as the platform libc include directories.

The evidence therefore indicates that switching to the stock musl wrapper
correctly selects musl libc headers but also hides a required compiler-owned C
standard header. The original mmap64 diagnosis remains valid; this is a new
include-environment requirement exposed before the LFS64 gate could run.

## Disposition

This failure was not preauthorized. No clang resource include path was added,
the installed wrapper was not changed, no flag was removed, and no rerun was
attempted. A narrowly scoped way to retain musl libc headers while explicitly
making clang's compiler-resource headers available requires a new authorization.

No release 2 RPM was generated. Deployment, the one-positive/three-negative
runtime banner gate, the four-variant board session, and the data-filled report
remain NOT_RUN. No performance conclusion is asserted.

## Authorized remediation

The stock wrapper remains unchanged and retains `-nostdinc`. Immediately before
the mimalloc compile, the build now resolves `RESDIR` with
`clang -print-resource-dir`, prints the actual value, and asserts that
`$RESDIR/include/stdatomic.h` exists. Failure prints the required `GATE:` line
and exits before compilation.

The existing `musl-clang` invocation receives one additional user argument,
`-isystem "$RESDIR/include"`, after the mimalloc project include. Because the
wrapper places its own `-isystem "$libc_inc"` before the complete user-argument
segment, musl headers retain priority and the clang resource tree fills only
missing compiler-owned headers. The compiler decision records both the resolved
resource include path and `mimalloc_include_order=musl_first_resource_fill`.

## Verification

The formal rerun resolved `RESDIR` to `/usr/lib/clang/22`, found
`/usr/lib/clang/22/include/stdatomic.h`, and compiled `mimalloc.o` successfully.
The raw build log records:

```text
gate.mimalloc_resource_dir=/usr/lib/clang/22
gate.mimalloc_stdatomic_header=PASS path=/usr/lib/clang/22/include/stdatomic.h
gate.mimalloc_lfs64_symbols.scan_begin
gate.mimalloc_lfs64_symbols.scan_end
gate.mimalloc_lfs64_symbols=PASS
```

The empty scan region proves no forbidden LFS64-family symbol was present.
There were also no unresolved `__atomic_*` symbols. The fourth variant linked,
all mimalloc owner, ELF, and softfp gates passed, and GBS produced release 2.
The RPM SHA-256 is
`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`.
Per the host-only authorization, deployment and board measurement remain
NOT_RUN.
