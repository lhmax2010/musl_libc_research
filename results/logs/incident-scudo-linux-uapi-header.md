# Incident: Scudo standalone cannot see Linux UAPI futex header

Status: **PARKED — authorization required**

## Context

- Branch: `execution/allocator-shootout`
- FatTank rpmalloc review commit:
  `23a76a0f95f2ad58a7793de70afed12fdd6210a8`
- GBS target: Tizen unified `armv7l`
- Compiler: clang `22.1.8`
- Scudo source: LLVM `llvmorg-22.1.8`, commit
  `ca7933e47d3a3451d81e72ac174dcb5aa28b59d1`
- Full build log: `results/logs/gbs-build-shootout.log`
- Full build log SHA-256:
  `e5a1176d42cb5d25a6d293523e9be6704c3633e798fce1c58ab55913fc686915`

## S5 status before the incident

S5 completed compilation and linking. Its mechanical gates passed before S6
started:

```text
gate.rpmalloc_lfs64=PASS
gate.rpmalloc_symbol.malloc=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.free=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.calloc=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.realloc=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.posix_memalign=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.aligned_alloc=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_symbol.malloc_usable_size=PASS owner= .text          0x00010b68     0x5fb8 /home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/rpmalloc.o
gate.rpmalloc_musl_allocator_members=PASS count=0
gate.s5_rpmalloc.elf_softfp=PASS vfp=ABSENT
```

## Failure, verbatim

```text
/home/abuild/rpmbuild/BUILD/allocator-shootout-demo-1.0.0/scudo-standalone-22.1.8/condition_variable_linux.cpp:18:10: fatal error: 'linux/futex.h' file not found
   18 | #include <linux/futex.h>
      |          ^~~~~~~~~~~~~~~
1 error generated.
BUILD_GATE_FAIL: S6 failed outside the pre-authorized C++ runtime friction boundary; rc=1
error: Bad exit status from /var/tmp/rpm-tmp.7vxbzT (%build)
```

## Classification and stop decision

The failure occurs while compiling Scudo against the musl wrapper's isolated
header environment. `linux/futex.h` is a Linux UAPI header, not a C++ runtime,
exception, RTTI, or libc++ symbol failure. It therefore does not meet the
prompt's pre-authorized S6 downgrade condition.

No host include directory was added, the musl wrapper and `-nostdinc` were not
changed, libc++ was not introduced, and no gate was relaxed. The GBS build did
not produce an installable RPM, so deployment and board measurement remain
`NOT_RUN`.

## Decision needed

A separate ruling is required to choose either a narrowly ordered Linux-UAPI
header fill for S6 or an immediate S6 P1 downgrade that lets the already-gated
S5 path proceed to RPM. No option has been applied automatically.
