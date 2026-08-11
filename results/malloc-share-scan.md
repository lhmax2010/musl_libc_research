# malloc CPU-share screening — RPI4 bare-perf scan

> Status: **CAPTURE COMPLETE; all measured rounds are `LOW_SAMPLES`, so no threshold routing conclusion is made. Awaiting FatTank routing disposition.**

## Expected result declared before sampling

Existing L6 measurements indicate that allocation is generally inactive in resident platform daemons. This scan may therefore place every sampled process in `OUT`; that result would remain valid and would mean “the platform-daemon layer can run bare mallocng without concern.” This was declared for falsification before sampling. Because every completed round has fewer than 500 samples, this run neither validates nor falsifies that expectation.

## 1. Identity and perf gates

- Target: `192.168.108.26`; the address was not treated as identity.
- Kernel: `6.12.80-arm-rpi4-v7l` — RPI4 identity gate `PASS`.
- Image: Tizen 11.0 Unified, build `tizen-unified-toolchain_20260728.012216_tizen-headed-armv7l` — image gate `PASS`.
- Provisioning: route A `PASS`; routes B/C `NOT_RUN`.
- Installed and retained: `linux-kernel-perf-6.12.80-0.armv7l`, `libllvm-22.1.8-2.1.armv7l`, `perl-5.42.0-1.9.armv7l`, and `gdbm-1.8.3-1.9.armv7l`.
- `perf version 6.12.80`; CPU-active self-test captured 41 samples with zero lost samples.

The RPM installation is the task's only persistent board modification. It used `rpm -Uvh --noplugins`; the pushed RPMs were subsequently removed from `/tmp`, while the installed packages were intentionally retained.

## 2. Frozen method

Every completed round used:

```text
perf record -F 99 -g -p <PID> -o /tmp/p_<name>_<round>.data -- sleep 30
```

`Threads` and `VmRSS` were read from `/proc/<PID>/status` before and after each round. Dlog stimulus was a continuously running `dlogutil -v time` consumer. System D-Bus stimulus issued 150 successful `org.freedesktop.DBus.ListNames` calls at 5 Hz. No synthetic stimulus was invented for the other processes.

For each data file, the board generated full `--sort symbol`, `--sort dso`, and `--stats` reports. The malloc-family share is the sum of the `Self` column for:

```text
malloc | _int_malloc | _int_free* | free | calloc | realloc |
tcache* | malloc_consolidate | arena_get
```

The libc comparison is the sum of `Self` rows whose DSO is libc. Any round below 500 samples is `LOW_SAMPLES` and cannot feed the `<2% / 2–5% / >5%` routing thresholds. A one-thread process is always `SINGLE_THREADED_EXCLUDED`.

## 3. Screening table

Percentages below are retained observations, not routing inputs when marked `LOW_SAMPLES`. `N/A` means zero samples, so no percentage exists.

| Process | Threads | VmRSS before→after | idle malloc share | stimulus malloc share | samples idle/stimulus | routing result |
|---|---:|---:|---:|---:|---:|---|
| `dlog_logger` | 5 | 3432→3432 KiB | 0.00% (`LOW_SAMPLES`) | N/A (`LOW_SAMPLES`) | 2 / 0 | `LOW_SAMPLES — NO ROUTING` |
| `dbus-daemon --system` | 1 | 5804→5804 KiB | 0.00% (`LOW_SAMPLES`) | 4.76% (`LOW_SAMPLES`) | 1 / 21 | `SINGLE_THREADED_EXCLUDED`; both rounds also low |
| `enlightenment` | 15 | 17176→17176 KiB | 5.88% (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 17 / — | `LOW_SAMPLES — NO ROUTING` |
| `pulseaudio` | 5 | 5304→5304 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | `LOW_SAMPLES — NO ROUTING` |
| `resourced` | 12 | 7324→7324 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | `LOW_SAMPLES — NO ROUTING` |
| `SystemUI` | 13 | 19692→19692 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | `LOW_SAMPLES — NO ROUTING` |
| homescreen `runner` | 21 | 45972→46304 KiB | 0.00% (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 42 / — | `LOW_SAMPLES — NO ROUTING` |

No row is mechanically classified `OUT`, `GREY`, or `SHOOTOUT` because no round reaches the 500-sample gate. In particular, the observed 5.88% enlightenment value must not be promoted to `SHOOTOUT`.

## 4. libc control shares

| Process/round | samples | malloc-family Self | libc Self | quality |
|---|---:|---:|---:|---|
| dlog idle | 2 | 0.00% | 50.00% | `LOW_SAMPLES` |
| dlog stimulus | 0 | N/A | N/A | `LOW_SAMPLES` |
| D-Bus idle | 1 | 0.00% | 0.00% | `LOW_SAMPLES` |
| D-Bus stimulus | 21 | 4.76% | 9.52% | `LOW_SAMPLES` |
| enlightenment idle | 17 | 5.88% | 5.88% | `LOW_SAMPLES` |
| pulseaudio idle | 0 | N/A | N/A | `LOW_SAMPLES` |
| resourced idle | 0 | N/A | N/A | `LOW_SAMPLES` |
| SystemUI idle | 0 | N/A | N/A | `LOW_SAMPLES` |
| homescreen idle | 42 | 0.00% | 4.76% | `LOW_SAMPLES` |

The only retained malloc-family source rows were `_int_malloc` at 4.76% in the D-Bus stimulus round and `_int_free_merge_chunk` at 5.88% in the enlightenment idle round. Their full original lines are preserved in `results/logs/malloc-share-scan-analysis.log` and the per-round reports.

## 5. NOT_RUN list

- Chromium/WebEngine: `NOT_RUN`. `chromium-efl` was present. Owner execution was denied by the package security label; root execution created browser/zygote/renderer processes but reported a missing Wayland EGL dependency (`libGLESv2.so.2`), invalid window setup, and unavailable session D-Bus. Page loading could not be proven, so no empty-process sample was accepted. All spawned processes and temporary HOME/cache/config data were removed.
- No requested resident daemon was absent. All seven named process classes were located; homescreen was identified as `/usr/apps/org.tizen.homescreen/bin/runner`.

## 6. Evidence index

- Identity and original zypper parking evidence: `results/logs/malloc-share-scan-preflight.log`.
- Route A repository search, dependency closure, RPM hashes, install, and self-test: `results/logs/malloc-share-scan-perf-supply.log`.
- Process discovery, WebEngine probe disposition, per-round status, stimuli, and cleanup: `results/logs/malloc-share-scan-capture.log`.
- Mechanical extraction and source rows: `results/logs/malloc-share-scan-analysis.log`.
- Full board-generated reports: `results/logs/malloc-share-scan-reports/`.
- Immutable raw data: `results/perf-raw/`.

### Raw perf.data SHA-256

```text
1e8c7b7d37fda02ccf79f9797a253b897442fa52a1a62400f0e2a0b3a54eeca1  p_dbus_system_idle.data
ffa7c1228e01307846929943fd3e784be0cf8077d93cf54fa2fb11ad366a04ad  p_dbus_system_stimulus.data
1ac33b303f98d9d5d765961d5fd642e7ed2b2691d3718075ee899048603c15d4  p_dlog_logger_idle.data
43713ec4b9aefe0eb3641a3eb3e9ed0a790d8a4d6500b91dc646afcd5073e82e  p_dlog_logger_stimulus.data
b850bf59d8edd2c27b328d798cc10d3f326f622158aef7eafdbf0b529b9f98b1  p_enlightenment_idle.data
1c0e4c0a525aa731fbcccf076ec823fac9131ddf00dff5312ecff71b91a447e8  p_homescreen_idle.data
bf0cfe42ba0bb57ae01d696c11fa65200cb4def769df9f52f41b31b84d898ba0  p_pulseaudio_idle.data
b77e0e06c0e2fbd93d02037bcd90deb1204aac818631f06ab19f3dba1ee77715  p_resourced_idle.data
a362c10931ac9946aeff92d8164cf10d84fd1cfe50f4594485524607ebf7bc16  p_systemui_idle.data
```

## 7. Cleanup and stop state

- Board `/tmp` exact-name remainder scan: empty.
- Task-launched WebEngine process scan: empty.
- Raw host data: pulled, hash-matched, and set read-only.
- Installed perf RPM and its three supplied dependencies: retained as authorized.
- Other persistent board changes: none.

No shootout list is selected here. Execution stops for FatTank's routing decision.
