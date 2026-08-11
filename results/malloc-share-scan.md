# malloc CPU-share scan — parking report

> Status: **BLOCKED at perf availability gate; no process sampling was run.**

## Expected result declared before sampling

Existing L6 measurements indicate that allocation is generally inactive in resident platform daemons. This scan may therefore place every sampled process in `OUT`; that result would remain valid and would mean that the platform-daemon layer can run bare mallocng without concern. This is a falsifiable expectation, not a measured conclusion from this blocked run.

## Board identity gate

Target identity passed before any other board operation:

- Kernel: `6.12.80-arm-rpi4-v7l` (`rpi4` present).
- Image: Tizen 11.0 Unified, build `tizen-unified-toolchain_20260728.012216_tizen-headed-armv7l`.
- Full command output: `results/logs/malloc-share-scan-preflight.log`.

## Blocking condition

`perf` is not installed: neither `/usr/bin/perf` nor `/prd/bin/perf` exists, and `rpm -q perf` reports `package perf is not installed`.

The sole authorized installation route cannot be used because the board image has no `zypper` executable. The exact authorized command returned:

```text
/bin/sh: zypper: command not found
```

The prompt requires a parking report when the zypper route is unavailable and states that a GBS-packaged alternative needs separate authorization. No alternate installer, package source, copied binary, or GBS build was attempted.

## Scan table

| Process | Threads | VmRSS | idle share | stimulus share | samples | routing result |
|---|---:|---:|---:|---:|---:|---|
| All requested candidates | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | 0 | BLOCKED_BEFORE_SAMPLING |

No mechanical `OUT` / `GREY` / `SHOOTOUT` classification is possible without valid perf samples.

## Evidence and cleanup

- Preflight, installation attempt, absence confirmation, and cleanup verification: `results/logs/malloc-share-scan-preflight.log`.
- `results/perf-raw/`: not created because there are no raw `perf.data` files.
- Board `/tmp`: verified to contain no `p_*.data` or `p_*_report.txt` scan artifacts.
- Persistent board changes: none; the failed command did not install a package.

## NOT_RUN list

- `dlog_logger` or equivalent dlog daemon: perf unavailable.
- `dbus-daemon` system instance: perf unavailable.
- `enlightenment`: perf unavailable.
- `pulseaudio`: perf unavailable.
- `resourced`: perf unavailable.
- `SystemUI` / homescreen: perf unavailable.
- Chromium / WebEngine driveability probe: not attempted because the mandatory perf gate failed first.

Execution stops here pending explicit authorization for a perf provisioning route.
