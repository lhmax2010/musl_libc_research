# Incident: ffmpeg F2 build tool requires undeployed private musl loader

Status: **PARKED — new failure requires authorization**

## Scope and stopping point

The formal rerun command was:

```text
scripts/build_gbs_ffmpeg.sh
```

The Source0--Source8 preflight, FatTank review gate, frozen commit and source
hash gates, clang 22.1.8 gate, patch-consistency gate, musl linker-wrapper gate,
mimalloc LFS64 gate, and clang resource-header assertion passed. F1 baseline
configured and linked. F2 baseline configured successfully with pthreads,
native `h264` as its only decoder, an empty hwaccel section, and LGPL 2.1-or-
later licensing. The run then stopped while building F2.

F3, the formal configure-equivalence comparison, all gc-sections builds, the
ELF/F3 gates, RPM, deployment, board measurements, and `report-ffmpeg.md` are
`NOT_RUN`.

## Failure text

```text
HOSTLD  ffbuild/bin2c
BIN2C   fftools/resources/graph.html.c
BIN2C   fftools/resources/graph.css.c
qemu-arm: Could not open '/opt/usr/ffmpeg-demo/lib/ld-musl-arm.so.1': No such file or directory
make: *** [.../ffbuild/common.mak:179: fftools/resources/graph.html.c] Error 255
qemu-arm: Could not open '/opt/usr/ffmpeg-demo/lib/ld-musl-arm.so.1': No such file or directory
make: *** [.../ffbuild/common.mak:175: fftools/resources/graph.css.c] Error 255
make: Target 'ffmpeg' not remade because of errors.
BUILD_GATE_FAIL: F2 baseline ffmpeg binary missing
```

No unresolved `__atomic_*` symbol was reported.

## Confirmed mechanism

FFmpeg's generated F2 configuration selected the musl target wrapper for both
the target compiler/linker and the build-machine compiler/linker:

```text
CC=.../musl-inst/bin/musl-clang
LD=.../musl-inst/bin/musl-clang
HOSTCC=.../musl-inst/bin/musl-clang
HOSTLD=.../musl-inst/bin/musl-clang
```

Consequently the build helper is an ARM target executable rather than a native
chroot build-machine tool:

```text
ffbuild/bin2c: ELF 32-bit LSB pie executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /opt/usr/ffmpeg-demo/lib/ld-musl-arm.so.1
[Requesting program interpreter: /opt/usr/ffmpeg-demo/lib/ld-musl-arm.so.1]
```

The make rules execute this helper immediately to generate embedded resource C
files. The private musl loader path is a deployment path and does not exist in
the build chroot, so QEMU cannot start the helper. This is a build-tool/target-
tool role separation failure, not the previously fixed header lookup failure.

## Evidence

- `results/logs/gbs-build-ffmpeg.log`, SHA-256
  `f8ee2ff614d05dd5b200f3505f5ccdfbdd5b5d206288f3a9337ef418840cf38e`
  - resource header assertion: line 2169
  - F2 configure summary: lines 2674--2747
  - QEMU loader errors: lines 3135 and 3137
  - terminal build gate: line 3144
- Failed-build chroot probes (not delivery artifacts):
  - F2 `ffbuild/config.log` SHA-256
    `8c063b3df6fbccc438f1030a0faefb3e37570e5367499a672e7d1f1729ca4e50`
  - F2 `ffbuild/config.mak` SHA-256
    `09e4730e620d1c01fa07f2faefd5dd5eb7e1f436c0e69c1cec2a4a8ec52cd500`

## Parking discipline

No configure flag, wrapper, loader path, chroot filesystem, FFmpeg source,
thread setting, or gate was changed. No `libatomic` was introduced. Deployment
and measurements were not started.

A likely remediation would explicitly separate FFmpeg's native build-machine
compiler/linker from its musl target compiler/linker (for example via the
upstream host-compiler configure mechanism), while retaining musl for target
objects. That change is not authorized by the current prompt and was not
attempted.
