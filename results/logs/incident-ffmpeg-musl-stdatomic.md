# Incident: ffmpeg F2 configure cannot see clang `stdatomic.h`

Status: **RESOLVED — precedent reuse applied and F2 configure passed**

## Scope and stopping point

The formal command was:

```text
scripts/build_gbs_ffmpeg.sh
```

Host source preflight, the FatTank review gate, all three frozen source hashes,
the clang 22.1.8 gate, the musl linker-wrapper gate, the mimalloc LFS64 gate,
and the Tizen patch-consistency gate passed. F1 baseline configured and linked.
Execution stopped during F2 baseline configure. F3, all gc-sections builds, the
RPM, deployment, board measurements, and `report-ffmpeg.md` are `NOT_RUN`.

## Failure text

```text
Threading is enabled, but no atomics are available
BUILD_GATE_FAIL: F2 baseline ffmpeg binary missing
```

The underlying configure probes failed twice with:

```text
fatal error: 'stdatomic.h' file not found
```

## Confirmed root cause

The installed musl wrapper invokes clang with `-nostdinc`, then adds only the
musl include directory. musl 1.2.5 does not provide `stdatomic.h`; that header
is supplied by clang's compiler-resource directory. The chroot does contain:

```text
/usr/lib/clang/22/include/stdatomic.h
```

Therefore ffmpeg's C11 atomics probe cannot see an existing compiler header
when it runs through `musl-clang`. This is the same wrapper limitation already
observed for the isolated mimalloc object, but the previous authorization was
limited to that compilation command and does not authorize changing ffmpeg's
F2/F3 configure flags.

No fallback atomics implementation, `libatomic`, wrapper modification, thread
disablement, or include-path change was attempted.

## Evidence

- `results/logs/ffmpeg-f2-config.log`, SHA-256
  `2cba549fe00a80d416c0fbb388aa7b94177d20a8415d4f6a6c6658b4480d01ca`
  - missing header: lines 16036 and 16049
  - terminal configure diagnosis: line 17462
- The initial `results/logs/gbs-build-ffmpeg.log` had SHA-256
  `82dfcf33da657f4792fcccdbc4ec05aa10549d6e36a1dce96ca494fbb9dcde7e`
  (terminal diagnosis at line 3045 and build-gate stop at line 3052). The
  authorized formal rerun subsequently replaced that rolling build-log path;
  the immutable failed-config log above retains the underlying probe evidence.
- Chroot resource header SHA-256:
  `728b690f127fc85faa32b9031e3a0019da92f77db92ca91b749571e45617a9ea`

## Candidate remediation requiring approval

Add clang's measured resource include directory to the ffmpeg F2/F3 compiler
arguments after the musl wrapper's own include directory, with a precondition
that `stdatomic.h` exists. This would mirror the already approved mimalloc
header-fill ordering while keeping the musl headers first. The initial parked
run did not apply that change.

## Authorized disposition

FatTank classified this as a direct reuse of the already adjudicated
`incident-mimalloc-stdatomic-include` precedent. The F2/F3 ffmpeg configure
compiler flags now append the measured clang resource include directory after
the musl wrapper arguments. A mechanical precondition requires
`$RESDIR/include/stdatomic.h` to exist and records both the actual path and the
include ordering in `compiler-decision-ffmpeg.txt`.

F1 remains unchanged. The wrapper, `-nostdinc`, pthread configuration, linker
flags, and all configure/ELF/F3 gates remain unchanged. No `libatomic` was
introduced.

Rerun after authorization:

```text
scripts/build_gbs_ffmpeg.sh
```

The rerun recorded:

```text
gate.clang_resource_stdatomic=PASS path=/usr/lib/clang/22/include/stdatomic.h
threading support         pthreads
Enabled decoders:
h264
Enabled hwaccels:
License: LGPL version 2.1 or later
```

F2 configure therefore progressed past the original C11 atomics failure. The
formal three-way configure-equivalence gate was not reached because a separate,
new build-host-tool incident stopped the run; see
`incident-ffmpeg-build-tool-private-loader.md`.
