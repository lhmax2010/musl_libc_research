# Incident: mimalloc object references unavailable mmap64

Date: 2026-08-06

## Reached state

The authorized Source6 remediation passed. The host preflight found all seven
spec sources under `packaging/`, GBS exported release 2, and RPM prep passed
both frozen-source gates:

```text
SOURCE_PREFLIGHT_PASS count=7
[    3s] gate.source1_sha256=PASS value=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
[    3s] gate.source5_sha256=PASS value=0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d
```

The musl build and linker-wrapper gate passed. The build compiled
`mimalloc-2.1.7/src/static.c` into `mimalloc.o`, linked the existing glibc-dyn,
musl-static, and musl-dyn variants, then failed while linking
`micro.musl-mi`. The later mimalloc symbol, ELF, softfp, and RPM gates were not
reached.

## Failure

The exact failure in `gbs-build-mimalloc.log` is:

```text
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc.o: in function `unix_mmap_prim':
[   16s] /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234:(.text+0x3560): undefined reference to `mmap64'
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234:(.text+0x372a): undefined reference to `mmap64'
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234:(.text+0xab40): undefined reference to `mmap64'
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234:(.text+0xfa80): undefined reference to `mmap64'
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234:(.text+0xfb68): undefined reference to `mmap64'
[   16s] /usr/bin/ld: /home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc.o:/home/abuild/rpmbuild/BUILD/musl-libc-demo-1.0.0/mimalloc-2.1.7/src/prim/unix/prim.c:234: more undefined references to `mmap64' follow
[   16s] clang: error: linker command failed with exit code 1 (use -v to see invocation)
[   16s] error: Bad exit status from /var/tmp/rpm-tmp.yoBQNT (%build)
```

## Read-only diagnosis

The recorded mimalloc compile command uses the platform `clang` and the exact
expanded RPM optflags, including `-D_FILE_OFFSET_BITS=64`, before including the
mimalloc headers. The source at `prim.c:234` calls `mmap`, but the compiled
object records an unresolved large-file symbol:

```text
$ nm -u mimalloc.o | grep mmap
         U mmap64
```

The musl archive selected by the fourth variant exposes `mmap`, not `mmap64`:

```text
$ nm -A musl-inst/lib/libc.a | grep mmap
musl-inst/lib/libc.a:mmap.lo:00000001 W mmap
```

The evidence therefore indicates a header/link-world mismatch: the platform
large-file configuration remapped mimalloc's `mmap` call to `mmap64` while the
musl static link world provides `mmap`. This is a strongly evidenced inference,
not an authorized remediation decision.

## Disposition

This is a new, unpreauthorized failure. No optflag was removed, no compatibility
macro or symbol alias was added, no mimalloc or musl source was changed, and no
second rerun was attempted. Choosing whether mimalloc must compile against the
musl header world or receive a narrowly scoped large-file compatibility
treatment requires explicit authorization.

No release 2 RPM was generated. Deployment, the one-positive/three-negative
runtime banner gate, the four-variant board session, and the data-filled report
remain NOT_RUN. There is no performance conclusion.
