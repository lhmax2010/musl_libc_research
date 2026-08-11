# FFmpeg 8.0.1 H.264 software-decode island — measurement report

> Status: data-filled review draft; awaiting FatTank data verification. This document does not make the final adoption conclusion.

## 1. Scope and non-goals

The measured object is the Tizen official FFmpeg source tree built as a minimal private-prefix CLI island with only the native H.264 software decoder, MOV demuxer, file protocol, and null output path. F1 is glibc/ptmalloc dynamic, F2 is musl/mallocng static, and F3 is musl/mimalloc static.

The result covers this isolated static-CLI form only. It does not extend to shared libavcodec, gst-libav, libmm-player, hardware decode, encoding, networking, or external libraries.

## 2. Provenance and frozen inputs

| Item | Frozen value | Evidence |
|---|---|---|
| Source | Tizen `platform/upstream/ffmpeg`, branch observed as `tizen` | `results/logs/ffmpeg-src-provenance.txt` |
| Commit | `c15459c9fc8976827db7eaac643e84db2d1ea534` | same |
| Version | FFmpeg 8.0.1; libavutil 60.8.100 | same |
| Frozen archive | `f12101bcbec88f664bf50daf96bb4dbdd9326615ff11e1555f0eb3b1ff37f2f8` | `packaging/ffmpeg-tizen-src.sha256` |
| Test material | `cabi.mp4`, 88,765,233 bytes, `f58743eaba12f47320c4d8ea0ea7f9418b91728335c74df0c352d9730f63dd48` | `packaging/ffmpeg-testclip.sha256` |
| Compiler / ABI | clang 22.1.8; ARMv7 softfp | `results/logs/ffmpeg-build-evidence/compiler-decision-ffmpeg.txt` |
| License | LGPL 2.1 or later | `results/logs/ffmpeg-build-evidence/configure-equivalence.txt` |

Tizen platform modifications exist as git commits inside the frozen source tree. A spec patch count of zero is therefore the normal representation, not evidence that platform changes are absent. C8a uses the frozen Tizen tree itself as its accounting baseline. Differences between that platform tree and upstream FFmpeg 8.0.1 are outside this pilot's scope.

## 3. Method and three-source merge

The primary run completed decode before a startup parser stop. Following the approved malloc-truncation precedent, valid measurement phases are retained and missing/invalid reading phases are supplied by immutable supplements; no value is overwritten, selected, removed, or reweighted.

| Measurement | Source file | SHA-256 |
|---|---|---|
| Decode | `results/results-ffmpeg.txt` | `e1c8378ed3639eb274fb2eefe25a791142ee2bf427b17565aa367a03e93451f6` |
| Startup, memory | `results/results-ffmpeg-supplement.txt` | `2fa4971036581f1b69412138949604755536ba161e371694737ccda46b4c006d` |
| Size, function surface | `results/results-ffmpeg-supplement2.txt` | `477149ad2c933a231448e5ad013759131fad4eeb54fb8bf6b5bc80b3b9e6ecb7` |

Decode used ten within-round rotating triples. Every command used `-c:v h264 -i $CLIP -map 0:v:0 -an -t 30 -f null - -benchmark`; rounds cooled for 30 seconds, waited until temperature was at most 65°C whenever necessary, and recorded current/max frequency before and after. Startup used 30 rotating timer triples. Memory used three rotating repetitions per variant, `-re` only to keep the decoder alive for the fifth-second smaps_rollup snapshot, and recorded FFmpeg maxrss at completion. Percentiles use linear interpolation at `(n-1)×p`; paired deltas are the median of within-round `(candidate-reference)/reference` values.

## 4. Software-decode gates

| Layer | Result | Evidence |
|---|---|---|
| L1 build-time exclusion | PASS: hardware accelerators disabled; decoder set locked to H.264 | `results/logs/ffmpeg-build-evidence/ffmpeg-configure-commands.txt` |
| L2 configure equivalence | PASS: decoder exactly `h264`, hwaccels empty, ARM/NEON summary byte-identical | `results/logs/ffmpeg-build-evidence/configure-equivalence.txt` |
| L3 runtime identity | PASS: 30/30 native H.264 mappings and benchmarks; minimum sample/round-median utime ratio `0.957` (>0.5) | primary raw file |
| F3 allocator identity | PASS: mimalloc banner positive for F3, negative for F1/F2 | `results/logs/deploy-ffmpeg-cabi.log` |
| ELF / softfp / F3 symbol gates | PASS | `results/logs/gbs-build-ffmpeg.log`, compiler decision |
| Frozen source review gate | PASS after a proven pre-signoff block | `results/logs/ffmpeg-source-review-gate.log`, `results/logs/ffmpeg-source-review.md` |
| Patch consistency | PASS; declared/applied count 0/0 | `results/logs/ffmpeg-build-evidence/patch-consistency.txt` |

## 5. Decode results

All decode cells below come from `results/results-ffmpeg.txt`.

| Variant | Metric | Median | p10 | p95 | n |
|---|---:|---:|---:|---:|---:|
| F1 (glibc + ptmalloc, dynamic) | utime | 6.877 s | 6.765 s | 6.999 s | 10 |
| F1 (glibc + ptmalloc, dynamic) | stime | 0.371 s | 0.322 s | 0.442 s | 10 |
| F1 (glibc + ptmalloc, dynamic) | rtime | 2.474 s | 2.421 s | 2.572 s | 10 |
| F1 (glibc + ptmalloc, dynamic) | maxrss | 26520 KiB | 25890 KiB | 26909 KiB | 10 |
| F2 (musl 1.2.5 + mallocng, static) | utime | 6.752 s | 6.699 s | 6.901 s | 10 |
| F2 (musl 1.2.5 + mallocng, static) | stime | 0.485 s | 0.439 s | 0.638 s | 10 |
| F2 (musl 1.2.5 + mallocng, static) | rtime | 2.450 s | 2.416 s | 2.555 s | 10 |
| F2 (musl 1.2.5 + mallocng, static) | maxrss | 25100 KiB | 23690 KiB | 25426 KiB | 10 |
| F3 (musl 1.2.5 + mimalloc 2.1.7, static) | utime | 6.857 s | 6.786 s | 6.935 s | 10 |
| F3 (musl 1.2.5 + mimalloc 2.1.7, static) | stime | 0.362 s | 0.313 s | 0.396 s | 10 |
| F3 (musl 1.2.5 + mimalloc 2.1.7, static) | rtime | 2.426 s | 2.389 s | 2.523 s | 10 |
| F3 (musl 1.2.5 + mimalloc 2.1.7, static) | maxrss | 28936 KiB | 28188 KiB | 29982 KiB | 10 |

### Paired utime deltas and frozen E-P mapping

Positive delta means more CPU time than the reference. The status column is a mechanical application of the frozen ±2%/±5% bands, not the final FatTank conclusion.

| Candidate vs reference | Paired relative-difference median | Frozen-band status | n pairs |
|---|---:|---|---:|
| F2 vs F1 | -1.102% | EQUIVALENT | 10 |
| F3 vs F2 | +1.551% | EQUIVALENT | 10 |
| F3 vs F1 | -0.291% | EQUIVALENT | 10 |

## 6. Startup results

All startup cells come from `results/results-ffmpeg-supplement.txt`; units are milliseconds per `fork+exec+ffmpeg -version`.

| Variant | Median (ms) | p10 | p95 | n |
|---|---:|---:|---:|---:|
| F1 | 4.052 | 3.846 | 4.822 | 30 |
| F2 | 1.891 | 1.601 | 2.391 | 30 |
| F3 | 2.195 | 1.953 | 2.438 | 30 |

| Candidate vs reference | Paired median delta | n pairs |
|---|---:|---:|
| F2 vs F1 | -53.228% | 30 |
| F3 vs F2 | +17.160% | 30 |
| F3 vs F1 | -48.149% | 30 |

## 7. Memory results

All memory cells come from `results/results-ffmpeg-supplement.txt`; values are KiB at decode second 5 except maxrss, which is FFmpeg's completion value. Each cell has n=3.

| Variant | Metric | Median | p10 | p95 | n |
|---|---|---:|---:|---:|---:|
| F1 | Rss | 22016 | 22016 | 22016 | 3 |
| F1 | Pss | 21284 | 21284 | 21284 | 3 |
| F1 | Private_Clean | 976 | 976 | 976 | 3 |
| F1 | Private_Dirty | 20276 | 20276 | 20276 | 3 |
| F1 | maxrss | 22180 | 22164 | 22180 | 3 |
| F2 | Rss | 20128 | 20125 | 20128 | 3 |
| F2 | Pss | 20120 | 20117 | 20120 | 3 |
| F2 | Private_Clean | 1100 | 1100 | 1100 | 3 |
| F2 | Private_Dirty | 19020 | 19017 | 19020 | 3 |
| F2 | maxrss | 20600 | 20530 | 20604 | 3 |
| F3 | Rss | 23604 | 23604 | 23604 | 3 |
| F3 | Pss | 23596 | 23596 | 23596 | 3 |
| F3 | Private_Clean | 1160 | 1160 | 1160 | 3 |
| F3 | Private_Dirty | 22436 | 22436 | 22436 | 3 |
| F3 | maxrss | 23632 | 23603 | 24572 | 3 |

### F3 versus F2 memory premium

| Metric | F2 median (KiB) | F3 median (KiB) | Difference | Relative |
|---|---:|---:|---:|---:|
| Pss | 20120 | 23596 | +3476 KiB | +17.276% |
| Private_Dirty | 19020 | 22436 | +3416 KiB | +17.960% |
| maxrss | 20600 | 23632 | +3032 KiB | +14.718% |

## 8. Size matrix

All 12 build cells and the six deployed stripped cross-checks come from `results/results-ffmpeg-supplement2.txt`. Board values matched exactly.

| Variant | Mode | Unstripped bytes | Stripped bytes | Strip reduction | Board stripped |
|---|---|---:|---:|---:|---:|
| F1 | baseline | 10874676 | 2353184 | 78.361% | 2353184 |
| F1 | gc | 10969056 | 2177984 | 80.144% | 2177984 |
| F2 | baseline | 11881532 | 2967556 | 75.024% | 2967556 |
| F2 | gc | 11953964 | 2782396 | 76.724% | 2782396 |
| F3 | baseline | 12493148 | 3071876 | 75.412% | 3071876 |
| F3 | gc | 12565496 | 2886716 | 77.027% | 2886716 |

### gc-sections change versus each baseline

| Variant | Unstripped delta | Unstripped relative | Stripped delta | Stripped relative |
|---|---:|---:|---:|---:|
| F1 | +94380 | +0.868% | -175200 | -7.445% |
| F2 | +72432 | +0.610% | -185160 | -6.239% |
| F3 | +72348 | +0.579% | -185160 | -6.028% |

## 9. Function surface

Source: `results/results-ffmpeg-supplement2.txt`, byte-matched to the packaged build evidence for F2.

| Symbol | F2 state |
|---|---|
| `strcoll` | ABSENT |
| `iconv` | PRESENT |
| `setlocale` | ABSENT |
| `getaddrinfo` | ABSENT |

## 10. Modification accounting

| Account | Recorded value | Evidence |
|---|---|---|
| C8a | FFmpeg source diff outside frozen Tizen tree = 0 | `c8a-source-diff.txt` |
| C8a baseline | Frozen Tizen tree, including platform commits | `c8-ledger.txt` |
| C8b.1 | New isolated RPM spec/private prefix | same |
| C8b.2 | Frozen archive normalization during prep | same |
| C8b.3 | Minimal software-decode configure set | same |
| C8b.4 | Reused musl wrapper start-group integration | same |
| C8b.5 | Added mimalloc object through extra-libs | same |
| Semantic workaround | NONE | same |

## 11. PerfHotSpotAnalyzer cross-validation

The comparison strength is aligned on all available axes: the replacement `cabi.mp4` is a PerfHotSpotAnalyzer-source sample, FFmpeg is 8.0.1, decoding is explicitly native H.264, audio is disabled, and the command uses the same 30-second null-output benchmark window (`-an -t 30 -f null - -benchmark`). This removes the earlier full-file/window mismatch and makes utime directly comparable by magnitude.

| Current island variant | utime median (s) | p10 | p95 | n |
|---|---:|---:|---:|---:|
| F1 | 6.877 | 6.765 | 6.999 | 10 |
| F2 | 6.752 | 6.699 | 6.901 | 10 |
| F3 | 6.857 | 6.786 | 6.935 | 10 |

The historical PerfHotSpotAnalyzer numeric utime record is not present in this repository or the supplied prompts. Consequently the aligned current values are reported at full precision for direct FatTank comparison, but no historical delta is invented here. Cross-validation numeric disposition remains `PENDING_FATTANK_DATA_VERIFICATION`.

## 12. Tizen full build versus island configuration

The archived Tizen spec describes a shared-library platform build with many audio/video parsers, demuxers, decoders (including HEVC/VP8/VP9), encoders, filters, bitstream filters, swscale/swresample, and profile-dependent options. The island instead uses `--disable-everything --disable-autodetect`, static linking for F2/F3, exactly H.264 decode, MOV demux, H.264 parser, file protocol, null muxer, wrapped_avframe, null filter, pthreads, and NEON. This is a deliberate capability contraction for controlled libc/allocator comparison, not a replacement platform packaging recipe.

## 13. Invalid samples and incidents

| Source/phase | INVALID | Disposition | Evidence |
|---|---:|---|---|
| Primary decode | 0 | 30/30 metrics retained | `results/results-ffmpeg.txt` |
| Primary startup attempt | 1 reading attempt | Excluded; verbose-child timer parser incident | `incident-ffmpeg-startup-timer-output.md` |
| Supplement startup | 0 | 30/30 triples retained | `results/results-ffmpeg-supplement.txt` |
| Supplement memory | 0 | 9/9 retained | same |
| Supplement size attempt | 1 reading attempt | Excluded; SDB stdin pollution | `incident-ffmpeg-size-matrix-sdb-stdin.md` |
| Supplement2 size/function | 0 | six board cells and function scan retained | `results/results-ffmpeg-supplement2.txt` |

## 14. Caveats

- Single board, single H.264 material, and a 30-second window; no workload-general claim is made.
- The island excludes the platform framework/shared-library integration and all hardware decode paths.
- Memory smaps uses `-re` solely to guarantee a live fifth-second snapshot; decode performance does not use `-re`.
- The first board file was misplaced HEVC and its digest remains explicitly revoked; `cabi.mp4` is the active frozen H.264 input.
- RPM deployment skipped Tizen security plugins with `--noplugins`; host/board payload hashes matched, so this does not change measured binaries.
- Two reading-layer incidents were handled with immutable supplements; their invalid attempts are listed rather than erased.
- Historical logs retain operator paths under the approved evidence-integrity ruling.

## 15. Evidence index and review state

- Build: `results/logs/gbs-build-ffmpeg.log`, `results/logs/ffmpeg-build-evidence/`
- Deploy/smoke: `results/logs/deploy-ffmpeg-cabi.log`
- Three source hashes: `results/logs/ffmpeg-three-source-sha256.log`
- Timer parser regression: `results/logs/ffmpeg-timer-parser-selfcheck.log`
- SDB stdin regression: `results/logs/sdb-stdin-isolation-selfcheck.log`
- Raw measurements: the three files listed in section 3

Final interpretation and adoption disposition: **PENDING FATTANK DATA VERIFICATION**.
