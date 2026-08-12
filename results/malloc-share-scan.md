# malloc CPU-share screening — RPI4 bare-perf scan

> Status: **FatTank routing disposition recorded; 9/9 measured rounds are `OUT_IDLE` or excluded.**

## Expected result declared before sampling

Existing L6 measurements indicate that allocation is generally inactive in resident platform daemons. This scan may therefore place every sampled process in `OUT`; that result would remain valid and would mean “the platform-daemon layer can run bare mallocng without concern.” This was declared for falsification before sampling. The final absolute-CPU disposition below supports that expectation.

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

The libc comparison is the sum of `Self` rows whose DSO is libc. Any round below 500 samples remains `LOW_SAMPLES` for malloc-share precision and cannot feed the original `<2% / 2–5% / >5%` malloc-share thresholds. FatTank's final disposition adds an absolute-CPU screen: a 30-second round at 99 Hz has 2,970 possible samples, so `est_CPU% = samples / 2970 × 100`. This is an estimate of the process's sampled CPU occupancy, not a precise utilization measurement. A round with `est_CPU% < 5%` and `LOW_SAMPLES` is `OUT_IDLE`: allocator performance does not constitute a selection factor for that process. A one-thread process is additionally `SINGLE_THREADED_EXCLUDED`.

## 3. Screening table

Malloc-family percentages below remain low-resolution observations. `N/A` means zero samples, so no malloc-family percentage exists. Estimated CPU is shown as idle/stimulus and uses the 2,970-sample denominator above.

| Process | Threads | VmRSS before→after | idle malloc share | stimulus malloc share | samples idle/stimulus | est_CPU% idle/stimulus | routing result |
|---|---:|---:|---:|---:|---:|---:|---|
| `dlog_logger` | 5 | 3432→3432 KiB | 0.00% (`LOW_SAMPLES`) | N/A (`LOW_SAMPLES`) | 2 / 0 | 0.067% / 0.000% | `OUT_IDLE` (both rounds) |
| `dbus-daemon --system` | 1 | 5804→5804 KiB | 0.00% (`LOW_SAMPLES`) | 4.76% (`LOW_SAMPLES`) | 1 / 21 | 0.034% / 0.707% | `OUT_IDLE` + `SINGLE_THREADED_EXCLUDED` (both rounds) |
| `enlightenment` | 15 | 17176→17176 KiB | 5.88% (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 17 / — | 0.572% / — | `OUT_IDLE` |
| `pulseaudio` | 5 | 5304→5304 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | 0.000% / — | `OUT_IDLE` |
| `resourced` | 12 | 7324→7324 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | 0.000% / — | `OUT_IDLE` |
| `SystemUI` | 13 | 19692→19692 KiB | N/A (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 0 / — | 0.000% / — | `OUT_IDLE` |
| homescreen `runner` | 21 | 45972→46304 KiB | 0.00% (`LOW_SAMPLES`) | `STIMULUS_UNAVAILABLE` | 42 / — | 1.414% / — | `OUT_IDLE` |

All nine measured rounds satisfy the frozen final rule: `LOW_SAMPLES` and estimated absolute CPU below 5%. They are therefore `OUT_IDLE`; the two D-Bus rounds carry the additional single-thread exclusion. In particular, enlightenment's low-resolution 5.88% malloc-family observation is not promoted to `SHOOTOUT`, because its process occupies only an estimated 0.572% CPU during the round.

## 4. libc control shares

| Process/round | samples | est_CPU% | malloc-family Self | libc Self | quality / routing |
|---|---:|---:|---:|---:|---|
| dlog idle | 2 | 0.067% | 0.00% | 50.00% | `LOW_SAMPLES / OUT_IDLE` |
| dlog stimulus | 0 | 0.000% | N/A | N/A | `LOW_SAMPLES / OUT_IDLE` |
| D-Bus idle | 1 | 0.034% | 0.00% | 0.00% | `LOW_SAMPLES / OUT_IDLE / SINGLE_THREADED_EXCLUDED` |
| D-Bus stimulus | 21 | 0.707% | 4.76% | 9.52% | `LOW_SAMPLES / OUT_IDLE / SINGLE_THREADED_EXCLUDED` |
| enlightenment idle | 17 | 0.572% | 5.88% | 5.88% | `LOW_SAMPLES / OUT_IDLE` |
| pulseaudio idle | 0 | 0.000% | N/A | N/A | `LOW_SAMPLES / OUT_IDLE` |
| resourced idle | 0 | 0.000% | N/A | N/A | `LOW_SAMPLES / OUT_IDLE` |
| SystemUI idle | 0 | 0.000% | N/A | N/A | `LOW_SAMPLES / OUT_IDLE` |
| homescreen idle | 42 | 1.414% | 0.00% | 4.76% | `LOW_SAMPLES / OUT_IDLE` |

The only retained malloc-family source rows were `_int_malloc` at 4.76% in the D-Bus stimulus round and `_int_free_merge_chunk` at 5.88% in the enlightenment idle round. Their full original lines are preserved in `results/logs/malloc-share-scan-analysis.log` and the per-round reports.

## 5. Final conclusion

RPI4 平台 daemon 层在系统级分配冷（9/9 `OUT_IDLE/EXCLUDED`），musl 缺省 mallocng 对该层零性能顾虑，allowlist 空清单为有证据状态；分配热画像的搜索转入第二批候选（AIFW/TFLite 岛及后续真实 App 层）。

P2: If review requires a precise malloc-share percentage, a follow-up may resample at `-F 999 × 120s` to improve resolution. It would not change the absolute-CPU disposition, so it is not run by default.

## 6. NOT_RUN list

- Chromium/WebEngine: `NOT_RUN`. `chromium-efl` was present. Owner execution was denied by the package security label; root execution created browser/zygote/renderer processes but reported a missing Wayland EGL dependency (`libGLESv2.so.2`), invalid window setup, and unavailable session D-Bus. Page loading could not be proven, so no empty-process sample was accepted. All spawned processes and temporary HOME/cache/config data were removed.
- No requested resident daemon was absent. All seven named process classes were located; homescreen was identified as `/usr/apps/org.tizen.homescreen/bin/runner`.

## 7. Evidence index

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

## 8. Cleanup and stop state

- Board `/tmp` exact-name remainder scan: empty.
- Task-launched WebEngine process scan: empty.
- Raw host data: pulled, hash-matched, and set read-only.
- Installed perf RPM and its three supplied dependencies: retained as authorized.
- Other persistent board changes: none.

FatTank's routing disposition is fully recorded. No daemon enters the allocator shootout from this batch; the evidenced allowlist is empty. Execution stops here.
