# Incident: RPM auto-debuginfo leaves timer files unpackaged

Status: **AUTHORIZED FIX COMMITTED — RPM rerun pending**

## Scope and stopping point

The formal command was:

```text
scripts/build_gbs_ffmpeg.sh
```

All six FFmpeg variants built. F2/F3 static host-tool verification passed for
both baseline and gc-sections builds. Configure equivalence, ELF/softfp, F3
mimalloc symbol ownership and mallocng exclusion, source-tree immutability,
function-surface capture, size capture, artifact hashing, and the build-script
terminal gate all passed:

```text
gate.configure_equivalence=PASS decoder=h264 hwaccels=EMPTY arm_neon=identical
gate.elf_softfp=PASS
gate.mimalloc_link_map=PASS owner=mimalloc.o mallocng_members=0
BUILD_GATE_PASS: ffmpeg F1/F2/F3 and size matrix passed
```

The run stopped during RPM post-install processing. No RPM was emitted.
Deployment, smoke tests, board measurements, and `report-ffmpeg.md` are
`NOT_RUN`.

## Failure text

```text
/usr/lib/rpm/find-debuginfo.sh ...
extracting debug info from .../opt/usr/ffmpeg-demo/bin/timer
Checking for unpackaged file(s): /usr/lib/rpm/check-files ...
error: Installed (but unpackaged) file(s) found:
   /usr/lib/debug/opt/usr/ffmpeg-demo/bin/timer.debug
   /usr/src/debug/ffmpeg-musl-demo-8.0.1-1.arm/timer.c
```

The missing-build-id lines for the installed binaries are RPM warnings. The
fatal condition is the two files listed as installed but unpackaged.

## Confirmed mechanism

The timer helper is compiled with the RPM optflags, which include DWARF debug
information, and is installed into the package buildroot without being stripped
by the island build script. The Tizen RPM post-install pipeline invoked
`find-debuginfo.sh`, which extracted `timer.debug` and copied the corresponding
source under `/usr/src/debug`.

The spec declares `%global debug_package %{nil}` and its `%files` section owns
only `/opt/usr/ffmpeg-demo/bin/*` and `/opt/usr/ffmpeg-demo/share/*`. In this
observed Tizen pipeline the macro did not prevent automatic extraction, while
no generated debug subpackage file list claimed the extracted paths. The final
`check-files` stage therefore rejected them.

The already stripped FFmpeg F1 binaries produced only “already stripped”
warnings; the explicit extraction shown in the log is for `timer`.

## Evidence

- `results/logs/gbs-build-ffmpeg.log`, SHA-256
  `1dea4386a8e19536179ff031af4e91cc06f92898cfa9a52ad2e62b9d29113030`
  - four static host-tool gates: lines 3168, 3660, 4658, and 5150
  - configure/ELF/F3 gates: lines 5151--5160
  - terminal build gate: line 5161
  - debuginfo extraction: lines 5180--5184
  - unpackaged-file failure: lines 5234--5237
  - terminal GBS failure: line 5252
- Failed-build buildroot probes confirmed both generated files existed. The
  `timer.debug` file was an ARM ELF with debug information; the second file was
  the copied C source.

## Parking discipline

No debuginfo macro, optflag, timer compile command, strip behavior, `%files`
list, buildroot content, or RPM policy was changed. The files were not deleted
or retroactively claimed. No deployment or board command was run.

Possible dispositions include making the Tizen debuginfo suppression effective,
explicitly accounting for the generated debug files, or changing the timer's
debug/strip treatment. These choices alter packaging policy or artifact
treatment and require a separate ruling; none was attempted.

## Authorized disposition

FatTank authorized explicit suppression of both debuginfo package generation
and the debug extraction post-processing step. The spec header therefore keeps
`%global debug_package %{nil}` and adds
`%global __debug_install_post %{nil}`. The existing `%global __strip /bin/true`
remains unchanged. This policy does not alter compilation, linking, or the six
FFmpeg binaries; their hashes are frozen before the packaging-only rerun in
`results/logs/ffmpeg-rpm-prechange-artifacts.sha256`.

The companion `musl-libc-demo.spec` did not expose this failure because
`packaging/build-demo.sh` explicitly strips every payload executable,
including `timer`, before `%install`; no timer DWARF remained for the RPM debug
extractor. That spec also already disabled the debug subpackage. With the added
post-processing macro, both demo specs now make the no-debuginfo packaging
policy explicit; the FFmpeg spec needs the extra safeguard because its timer is
intentionally left unstripped while independent pre/post-strip size evidence is
preserved under `share/`.

The post-rerun checks must prove that the RPM file list is exactly the two
authorized `/opt/usr/ffmpeg-demo/{bin,share}` payload trees, contains no
`/usr/lib/debug` or `/usr/src/debug`, and that all six FFmpeg binary hashes are
byte-for-byte identical to the frozen values.
