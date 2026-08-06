# Continue execution status — 2026-08-06

## Build

The softfp alignment commit `c250c88` changed the active loader name and the
two explicitly authorized ABI gates. Its first GBS run passed both musl gates
and exposed this complete glibc-dynamic NEEDED list:

```text
libpthread.so.0
libc.so.6
ld-linux.so.3
```

The earlier continue-execution prompt pre-authorized this exact platform-loader
whitelist case. Commit `676f0e3` added only `ld-linux.so.3`; the authorized
single retry then completed successfully:

```text
gate.source1_sha256=PASS value=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
rtlib_consistency=PASS
gate.ldwrapper_patch=PASS style=ld
gate.micro.musl-static=PASS
gate.micro.musl-dyn=PASS interpreter=/opt/usr/musl-demo/lib/ld-musl-arm.so.1 needed=libc.so
gate.micro.glibc-dyn=PASS interpreter=/lib/ld-linux.so.3
gate.arm32_softfp_abi_consistency=PASS
BUILD_GATE_PASS: all comparison artifacts passed
BUILD_GBS_PASS
```

Produced artifact:

```text
results/rpms/musl-libc-demo-1.0.0-1.armv7l.rpm
sha256=ed42d8978ffd838fc59e4b02a6ab7b36c2825475cd3be434ed952c5341f2fcfa
```

## Deployment parking point

`scripts/deploy.sh` passed host-side RPM payload hashes, connected to
`192.168.108.25`, enabled root mode, and pushed the RPM. Board installation
then failed:

```text
error: Can't write smack rules
error: Setting up smack rules for musl-libc-demo failed
error: Plugin msm: hook psm_pre failed
warning: Plugin msm: hook psm_post failed
error: musl-libc-demo-1.0.0-1.armv7l: install failed
error: Unable to write device security policy to /etc/device-sec-policy
```

`/opt` and `/opt/usr` are mounted read-write, but `rpm -q musl-libc-demo`
reports that the package is not installed. The complete deploy output and
required `ls -Z`/mount evidence are archived under `results/logs/`.

The authorized parking rule was followed: no manual-copy fallback or policy
change was attempted. Smoke, `run_board`, `results/results.txt`, and the measured
report are `NOT_RUN`.

## Continuation

After explicit authorization resolves board RPM/Smack installation:

```bash
SDB_TARGET=192.168.108.25 scripts/deploy.sh
SDB_TARGET=192.168.108.25 scripts/run_board.sh
```

`run_board.sh` generates the measured report only after deployment succeeds.
