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
