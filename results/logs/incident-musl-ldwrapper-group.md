# Incident: musl static archive ordering in `ld.musl-clang`

Date: 2026-08-06

## Phenomenon

The earlier GBS run loaded both `libgcc.a` and `libgcc_eh.a`, but the
`micro.musl-static` link still left ARM division builtins unresolved:

```text
undefined reference to `__aeabi_uidiv'
undefined reference to `__aeabi_idiv'
undefined reference to `__aeabi_uldivmod'
undefined reference to `__aeabi_ldivmod'
```

## Root cause

`ld.musl-clang` appended `-lc` after the compiler driver's runtime archives.
The armv7-a baseline does not guarantee hardware division, and both `micro.o`
and members selected from `libc.a` call `__aeabi_*div*` helpers. With a
single-pass archive scan, `libgcc.a` had already been scanned before `-lc`
introduced those unresolved references. The archive was therefore loaded but
could not resolve helpers introduced later. The shared `libc.so` path did not
expose this ordering problem because musl's shared library had already linked
in its builtins.

## Authorized fix

Commit `6e8ba8a` adds a post-install transformation only to
`packaging/build-demo.sh`. It recognizes whether the wrapper invokes the real
linker or the compiler driver, canonicalizes the already-selected runtime
archive, optionally adds the sibling `libgcc_eh.a`, and replaces only the
standalone `-lc` on the final linker line with a start group. It does not use
`--whole-archive`, alter musl sources, change `COMMON_FLAGS` or any of the three
variant commands, change runtime selection, or relax a gate.

The pre-patch and post-patch wrappers were printed in full in
`results/logs/gbs-build.log`. Their stored diff is:

```diff
--- ld.musl-clang.before
+++ ld.musl-clang
@@ -48,4 +48,4 @@
      esac
  done
-exec $($cc -print-prog-name=ld) -nostdlib "$@" -lc -dynamic-linker "$ldso"
+exec $($cc -print-prog-name=ld) -nostdlib "$@" --start-group -lc /usr/lib/gcc/armv7l-tizen-linux-gnueabi/14.2.0/libgcc.a /usr/lib/gcc/armv7l-tizen-linux-gnueabi/14.2.0/libgcc_eh.a --end-group -dynamic-linker "$ldso"
```

The post-patch `cc=clang` wrapper checks passed. `compiler-decision.txt`
recorded `ldwrapper_patch=start-group`, the real-ld style, both absolute
archive paths, both exact linker lines, and `ldwrapper_clang_gate=PASS`.

## Rerun result and lesson

The rerun logged:

```text
gate.ldwrapper_patch=PASS style=ld
gate.micro.musl-static=PASS
```

This validates the archive-order root cause and fix without whole-archive size
pollution. The next, unrelated gate rejected the musl-dynamic interpreter; the
run stopped there as an unpreauthorized failure. No RPM was produced and no
deployment or board measurement ran.

Lesson: when a wrapper adds a static libc archive after driver-supplied runtime
archives, cyclic or late-introduced runtime references must be resolved with a
bounded group using the already-selected runtime archives.
