# Incident: S5 rpmalloc runtime segmentation fault

Status: **PARKED — new, unpreauthorized failure**

## Scope and stopping point

The RPI4 identity gate, both RPM installations, and the host/board SHA-256
comparison passed. The allocator runtime smoke then failed for S5, so the
shootout measurement was not started and `results/results-shootout.txt` was
not created.

S1, S2, S3, S4, and S6 completed the same allocator smoke successfully. S5
was built with all authorized link-time ownership, musl allocator extraction,
LFS64, ELF, and softfp gates passing, but failed at first allocator exercise on
the board.

## Exact failure

Command:

```text
/opt/usr/musl-demo/bin/micro.musl-rp malloc 1 1000
```

Captured output in `results/logs/deploy-shootout.log`:

```text
/bin/sh: line 1:  6916 Segmentation fault      (core dumped) '/opt/usr/musl-demo/bin/micro.musl-rp' malloc 1 1000
allocator_smoke.variant=micro.musl-rp,rc=139
```

Kernel audit evidence:

```text
[31888.784418] audit: type=1701 audit(1786545080.889:6749): auid=4294967295 uid=0 gid=0 ses=4294967295 subj=User::Shell pid=6916 comm="micro.musl-rp" exe="/opt/usr/musl-demo/bin/micro.musl-rp" sig=11 res=1
```

The board binary hash still matches the packaged/host artifact:

```text
fee7c8f329835fb47a18cb43d95b121aafbb4aeaf240ec86b85e04a7df3a389c  /opt/usr/musl-demo/bin/micro.musl-rp
```

No residual S5 process and no plain core file in `/root` were found. The board
uses a crash-manager pipe as `core_pattern`; no crash artifacts were modified
or removed.

## Fail-closed transport defect observed

The SDB client did not propagate the remote shell's rc=139 as its own host-side
exit status. Consequently, the current deployment script continued and printed
`DEPLOY_SHOOTOUT_PASS` after the explicit `allocator_smoke...rc=139` line. That
final marker is invalid and must not be treated as a passing gate. No fix was
attempted because work stopped at the newly observed S5 runtime failure.

## Evidence integrity

- `results/logs/deploy-shootout.log` SHA-256:
  `f71f858ed433b20dae631d3d87514e3a56bac937ed9721fae13ebf07cf4708f9`
- Board identity: kernel `6.12.80-arm-rpi4-v7l`, Tizen 11 Unified.
- Add-on RPM SHA-256:
  `317c39240ffa5e1e9400b37750c4f662dae7d410125c075942f0013d853af19d`
- S6 status remains `BUILT`; the S6 friction budget was not triggered.

## Required decision

FatTank authorization is required before diagnosing or changing the S5
rpmalloc runtime integration. Until then, S5 is not eligible for measurement,
and neither five- nor six-variant data collection will run.

## Authorized diagnosis: host reproduction

FatTank subsequently authorized the bounded H1/H2 diagnosis. The exact
packaged S5 binary was extracted without modification. Its SHA-256 remained
`fee7c8f329835fb47a18cb43d95b121aafbb4aeaf240ec86b85e04a7df3a389c`.
The host provides the static qemu-user executable as
`/usr/bin/qemu-arm-static` (there is no `qemu-arm` symlink in `PATH`).

```text
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
qemu_plain_rc=139
```

The last 20 strace lines include:

```text
set_tid_address(1109384,1108120,1108076,3,1109412,65684) = 21016
rt_sigprocmask(SIG_UNBLOCK,0x407ff098,NULL) = 0
mmap2(NULL,143360,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = 0x3ffdd000
mprotect(0x3ffdf000,135168,PROT_READ|PROT_WRITE) = 0
rt_sigprocmask(SIG_BLOCK,0x00047960,0x407ff0a0) = 0
clone(CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID|CLONE_DETACHED,child_stack=0x3fffff60,parent_tidptr=0x3fffff88,tls=0x3fffffe8,child_tidptr=0x0010ed88) = 21019
rt_sigprocmask(SIG_SETMASK,0x407ff0a0,NULL) = 0
futex(0x3fffff90,FUTEX_PRIVATE_FLAG|FUTEX_WAIT,2,NULL,NULL,0)
rt_sigprocmask(SIG_SETMASK,0x3fffff70,NULL) = 0
Unknown syscall 403
--- SIGSEGV {si_signo=SIGSEGV, si_code=1, si_addr=0x000000c4} ---
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
qemu_strace_rc=139
```

Phase classification: **first allocator use in the newly created worker
thread**, rather than process startup. The rpmalloc 1.4.5 source explains this
mechanically: `rpmalloc.c:775-784` makes `get_thread_heap()` return the raw null
TLS heap when `ENABLE_PRELOAD` is false, and `rpmalloc.c:3080-3089` immediately
passes that heap to `_rpmalloc_allocate`. The test's `micro.c:100-105` creates a
worker; its first allocation is at `micro.c:85`. This is consistent with the
successful process startup/no-argument smoke and the post-`clone` SIGSEGV.

The upstream build design had enabled only `ENABLE_OVERRIDE`, despite the
rpmalloc README requiring explicit process/thread initialization and describing
`ENABLE_PRELOAD` as the automatic initialization mode. H1 therefore tests both
defines together. Its static-link risk is also explicit in source:
`malloc.c:450-466` overrides `pthread_create` on Linux and calls
`dlsym(RTLD_NEXT, "pthread_create")`; the build records both symbol owners and
qemu decides whether that fallback is viable under static musl.

## H1 result: FAIL

H1 was built with exactly `ENABLE_PRELOAD=1 ENABLE_OVERRIDE=1`. All seven
public allocator interfaces still resolved to `rpmalloc.o`, but the frozen
zero-extraction gate found both musl allocator members `free.lo` and
`malloc.lo` in the static link map. Representative evidence:

```text
gate.rpmalloc_symbol.malloc=PASS owner=.../rpmalloc.o
gate.rpmalloc_symbol.malloc_usable_size=PASS owner=.../rpmalloc.o
.../musl-inst/lib/libc.a(free.lo)
.../musl-inst/lib/libc.a(malloc.lo)
BUILD_GATE_FAIL: musl primary allocator members were extracted into S5
```

This mechanically rejects H1 before qemu or board execution. No gate was
relaxed. The observed extraction is consistent with the PRELOAD Linux hook's
`dlsym(RTLD_NEXT, "pthread_create")` fallback pulling static musl allocation
internals into the executable. H2 therefore restores OVERRIDE-only and adds
only the separately authorized constructor object.

Source review also establishes H2's limitation before testing: with
`ENABLE_PRELOAD=0`, `rpmalloc.c:775-784` has no lazy initialization branch in
`get_thread_heap()`. `rpmalloc_thread_initialize` at `rpmalloc.c:3042-3054`
would initialize a worker heap, but the authorized constructor calls only
`rpmalloc_initialize`, which initializes the constructor's thread. H2 is still
built exactly as specified; qemu t1/t4/threads decides whether it is sufficient.

## H2 result: FAIL — friction budget exhausted

The H2 formal build passed the seven-interface ownership gate, LFS64 gate,
musl allocator zero-extraction gate, ELF/softfp gate, and produced an RPM with
SHA-256
`678b5be6e3fe715f1e55cb920454d7dbde8f8891054178d82c79ed9a1dc0af3d`.
The constructor object was linked before `rpmalloc.o`, exactly as authorized.

Qemu tests of the formal artifact:

```text
malloc 1 1000 -> rc=139
malloc 4 1000 -> rc=139
threads 4     -> rc=0
```

An independent diagnostic link used `-O0 -g -gdwarf-4
-fno-omit-frame-pointer`; it did not overwrite or enter the formal RPM. Its
complete valid crash-thread backtrace is archived at
`results/logs/shootout-h2-gdb-backtrace.log`. The decisive frames are:

```text
#0 _rpmalloc_allocate_small (heap=0x0) at rpmalloc.c:2202
#1 _rpmalloc_allocate (heap=0x0) at rpmalloc.c:2285
#2 rpmalloc (...) heap=0x0 at rpmalloc.c:3089
#3 malloc_worker (...) at micro.c:88
#4 start (...) at pthread_create.c:207
#5 __clone () at clone.s:23
```

This confirms the failure phase and mechanism: the worker reaches its first
allocation with a null rpmalloc thread heap. The H2 process constructor does
not initialize future worker threads, and OVERRIDE-only has no lazy worker
initialization path.

Both authorized hypotheses are now exhausted. Per the frozen budget, no H3,
source patch, rpmalloc version change, S5 downgrade, board retest, deployment
transport fix, or measurement was attempted. The task is parked for FatTank to
choose between a newer rpmalloc branch and `S5 P1-DEFERRED` (or to authorize a
different bounded integration).

H2 evidence hashes:

- `results/logs/shootout-h2-gdb-backtrace.log`:
  `a03ecff04ff9dc61957785b723748cef940e9ba4f219697f52a95a0b90a82e4e`
- `results/logs/shootout-h2-qemu.txt`:
  `7603898b5b1babe0e402a2d07212474de9d61c814a76f3d6d7f9caf15013b1f1`
- `results/logs/gbs-build-shootout.log`:
  `fcf6b5492f83d938ee264a7dc69fa8e43230e013fd41934b309fe9b291a49384`
