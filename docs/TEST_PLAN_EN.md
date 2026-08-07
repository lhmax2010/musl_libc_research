# Test plan: Tizen armv7l libc and allocator comparison

## 1. Objective and scope

The test compares four deliberately related runtime configurations on Tizen
armv7l softfp. It asks two attribution questions:

1. What changes when a small C probe moves from the platform glibc dynamic
   runtime to musl 1.2.5, while compiler and platform optimization flags stay
   fixed?
2. Within the musl-static configuration, what changes when musl mallocng is
   replaced at link time by mimalloc 2.1.7?

This is a solution-level micro-probe comparison, not a general libc ranking.
It does not claim application-wide performance, production readiness, complete
POSIX compatibility, security equivalence, or numerical portability across
boards. It does not deeply characterize external DNS because the recorded
external lookup was unavailable in the board environment. It does not test
glibc ABI shared objects inside the musl ABI world, ordinary `dlopen` plugins
from a static musl executable, or a full locale catalogue.

## 2. Variants and attribution design

| Variant | libc / allocator | Link model | Attribution role |
|---|---|---|---|
| `micro.glibc-dyn` | Tizen platform glibc / glibc allocator | Dynamic, platform loader | Platform baseline |
| `micro.musl-static` | musl 1.2.5 / mallocng | Static | Combined libc plus static-link solution |
| `micro.musl-dyn` | musl 1.2.5 / mallocng | Dynamic, package-private `ld-musl-arm.so.1` | Separates musl choice from static-link contribution |
| `micro.musl-mi` | musl 1.2.5 / mimalloc 2.1.7 | Static | Allocator intervention against `micro.musl-static` |

All four probes are built in one GBS chroot by the same platform clang 22.1.8,
with the same expanded `%optflags` and the same selected builtins archive
(`libgcc.a`). The musl variants use `musl-clang`, whose backend remains that
same clang. The only authorized command delta for `micro.musl-mi` is the
additional `mimalloc.o` link input. The link map must attribute `malloc`,
`free`, `calloc`, `realloc`, `posix_memalign`, `aligned_alloc`, and
`malloc_usable_size` to `mimalloc.o`.

The allocator comparison is fair only when `micro.musl-static` and
`micro.musl-mi` run in the same board session, alternate with the other
variants, and differ only by the audited allocator object. The runtime banner
gate is one positive control (`micro.musl-mi`) and three negative controls.

## 3. Metrics and instruments

| Dimension | What is measured | Instrument | Reason for the instrument |
|---|---|---|---|
| Startup | `fork` + `exec` to process exit, in nanoseconds | Package `timer` binary around `startup` mode | Measures complete process launch without mixing clocks from different processes |
| Installed binary size | Stripped probe and private `libc.so` byte sizes | Board `ls -l`; pre-strip sizes are also retained in the RPM | Shows deployment-size trade-offs while preserving both installed and pre-strip evidence |
| Process memory | `Rss`, `Pss`, `Private_Clean`, `Private_Dirty` | `/proc/<pid>/smaps_rollup` while `mem` mode stays alive | Uses kernel accounting and separates private dirty cost from shared mappings |
| Thread footprint | `VmSize`, `VmRSS`, `VmData`, and created thread count at 200 threads | Probe output from `/proc/self/status` | Exposes virtual-address reservation and resident footprint under a fixed thread count |
| Allocation churn | Mean nanoseconds per operation, checksum, and worst-thread wall time | Probe `malloc T 2000000` | Exercises allocate/touch/free churn at one and four threads; checksum prevents dead-code removal |
| DNS | Resolution status, elapsed time, and returned addresses for `localhost` and `www.tizen.org` | `getaddrinfo` probe plus archived `/etc/resolv.conf` | Captures resolver behavior without modifying board resolver configuration |
| Locale | Active locale, codeset, formatting, collation sign, and iconv availability | `setlocale`, `nl_langinfo`, `strftime`, `strcoll`, and `iconv` in the probe | Records structural locale differences rather than reducing them to a timing number |

The allocator remediation adds `micro.musl-mi` to startup, allocation, memory,
thread, and size measurements. DNS and locale were not repeated because the
allocator is not in their attribution path; their original three-variant raw
evidence remains part of the package.

## 4. Measurement controls

- The reference target is one RPI4 running Tizen armv7l softfp. Every available
  CPU governor is set to `performance` and verified.
- `scaling_cur_freq` and `scaling_max_freq` are captured before and after every
  startup round. A round with any current frequency below maximum is retained
  in raw data but marked `startup_invalid` and excluded from statistics.
- Startup uses rotating order: 30 paired triples in the baseline session and
  30 paired quads in the allocator session.
- Malloc uses five rounds at one thread and five rounds at four threads, with
  all variants rotated within each round. The authorized baseline supplement
  adds only rep 6 at four threads after one truncated sample.
- Memory uses three samples per variant. Threads uses one 200-thread sample per
  variant. Residual probe processes are checked before and after the allocator
  session.
- Each current probe invocation appends an independent `sample_end=OK` line.
  A declared-sentinel sample without it is INVALID.
- A malloc sample is VALID only when it has `threads`, `iters_per_thread`,
  `ns_per_op_mean`, and `checksum` in the same header-bounded sample. A header
  found in the middle of a line resynchronizes parsing and invalidates the
  partial sample. Values never cross a sample header.
- The reference baseline contains 30 valid startup rounds, 32 valid malloc
  samples, and one retained INVALID truncated malloc sample. The supplement
  has three valid samples and no INVALID samples. The allocator session has
  30 valid startup rounds, 40 valid malloc samples, 12 valid memory samples,
  four valid thread samples, and no INVALID samples.
- Temperature, frequency, ordering, raw values, and invalid reasons remain in
  the result files. No outlier selection, trimming, or post-hoc exclusion is
  permitted.

## 5. Build and integrity gates

All gates fail closed and must be visible in archived output:

1. **Source consensus:** musl is downloaded from its official release endpoint
   and corroborated by at least two independent published digests; the official
   signature is verified when available. mimalloc's official archive is checked
   against frozen vcpkg and Conan Center records and requires independent
   reviewer sign-off.
2. **Double hash verification:** host fetch verifies the frozen archive, then
   the GBS `%build` verifies Source1 (musl) and Source5 (mimalloc) again.
3. **Source export preflight:** every `SourceN` declared by the spec must exist
   under `packaging/` before GBS starts.
4. **Compiler gate:** clang must report exactly 22.1.8. The selected runtime
   archive and its digest must be identical for the compared variants.
5. **Wrapper and allocator gates:** the musl linker-wrapper archive group patch,
   clang resource header, absence of forbidden LFS64 undefined symbols, allowed
   command delta, link-map ownership, and a prefixed `mi_` symbol must pass.
6. **ELF gates:** every probe must be ELF32 ARM. musl-static and musl-mi must
   have no interpreter, `DT_NEEDED`, or `GLIBC_` dependency. musl-dyn must use
   `/opt/usr/musl-demo/lib/ld-musl-arm.so.1` and need only `libc.so`. The glibc
   probe must use the platform loader with only its pre-authorized dependencies.
7. **ABI gate:** the three original variants, the mimalloc variant, and chroot
   `/bin/sh` must agree on the ARM VFP-argument attribute. A `VFP registers`
   result fails because the platform contract is softfp.
8. **RPM and deployment gates:** the release-2 RPM digest, RPM-contained payload
   manifest, host-versus-board binary hashes, four smoke invocations, private
   musl loader, and RPM database installation semantics must pass. The board
   environment uses `rpm --noplugins` to skip the failing security plugin only.
9. **Allocator runtime gate:** mimalloc's verbose banner must appear for
   `micro.musl-mi` and must be absent from the other three probes.
10. **Measurement integrity:** governor, frequency, residual-process, sentinel,
    required-key, sample-count, and INVALID-accounting checks must pass.

## 6. Statistics

Startup reports the median of per-round paired relative differences, not the
difference between two unpaired medians. The baseline reports
`musl-static` versus `glibc-dyn` and `musl-static` versus `musl-dyn`.

Every malloc cell reports the median of all VALID samples and its own `n`.
The original and authorized supplemental samples are pooled without weighting,
selection, or deletion. Ratios are computed from the displayed per-cell
medians. Memory and size costs use medians where repeated samples exist and
retain the available `n`.

## 7. Known limitations and caveats

- Results come from one RPI4 board and one measurement day with limited sample
  counts. Values will differ on other armv7l softfp hardware.
- These are micro probes, not complete applications. Scheduling, temperature,
  storage, kernel, and board-specific effects remain.
- Compiler confounding is reduced by one clang and one `%optflags` set, but the
  remaining solution variable includes libc and link model unless musl-static
  is compared with musl-dyn.
- The builtins selection is `libgcc.a` and its cross-variant consistency gate
  passed; this does not make the result portable to another toolchain version.
- musl is a separate ABI world: it cannot directly consume platform glibc ABI
  shared objects. A static musl program does not support the ordinary dynamic
  plugin model, musl ignores `nsswitch.conf`, and its locale model is primarily
  C/C.UTF-8.
- The board RPM was installed with `--noplugins` because the Tizen security
  plugin could not write Smack policy in that environment. Files, scriptlets,
  RPM database semantics, payload hashes, and direct root-sdb execution were
  still verified; no Smack configuration was changed.
- One baseline malloc sample was truncated by incomplete `sdb shell` output.
  It is retained as INVALID, the parser is header-bounded and sentinel-aware,
  and the authorized replacement round is a separate immutable file.
- The external DNS name returned temporary failure on the reference board, so
  no deep DNS performance conclusion is made. DNS and locale were not repeated
  in the allocator-only session.
- mimalloc adds version/CVE maintenance obligations and does not preserve the
  heap-hardening properties of musl mallocng. In the reference session it also
  increased binary size, private dirty memory, and 200-thread virtual size.
