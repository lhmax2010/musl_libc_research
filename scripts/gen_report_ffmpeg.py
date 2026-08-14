#!/usr/bin/env python3
"""Generate the fail-closed, three-source FFmpeg island measurement report."""

from __future__ import annotations

import hashlib
import re
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
PRIMARY = RESULTS / "results-ffmpeg.txt"
SUPPLEMENT = RESULTS / "results-ffmpeg-supplement.txt"
SUPPLEMENT2 = RESULTS / "results-ffmpeg-supplement2.txt"
OUT = RESULTS / "report-ffmpeg.md"

EXPECTED_HASHES = {
    PRIMARY: "69784e43a288bdce04c6e9b5d2492f411cf9f2a5d0457fad63734923f85893ce",
    SUPPLEMENT: "c08c5896b7a85623bae89320f081128ebebfbe383b9110dd086f9d50ab665194",
    SUPPLEMENT2: "2871978ecbbe556498092a8c93555628d031a6ed942b2b99d2c1ec692c055e83",
}

VARIANTS = ("F1", "F2", "F3")
VARIANT_LABELS = {
    "F1": "glibc + ptmalloc, dynamic",
    "F2": "musl 1.2.5 + mallocng, static",
    "F3": "musl 1.2.5 + mimalloc 2.1.7, static",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def summary(values: list[float]) -> tuple[float, float, float, int]:
    if not values:
        raise ValueError("empty statistical cell")
    return statistics.median(values), percentile(values, 0.10), percentile(values, 0.95), len(values)


def paired_delta(candidate: list[float], reference: list[float]) -> float:
    if len(candidate) != len(reference) or not candidate:
        raise ValueError("paired series mismatch")
    return statistics.median([(c - r) / r * 100.0 for c, r in zip(candidate, reference)])


def band(delta: float) -> str:
    magnitude = abs(delta)
    if magnitude <= 2.0:
        return "EQUIVALENT"
    if magnitude <= 5.0:
        return "INCONCLUSIVE"
    return "REGRESSION" if delta > 0 else "IMPROVEMENT"


def fmt(value: float, digits: int = 3) -> str:
    return f"{value:.{digits}f}"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"REPORT_GATE_FAIL: {message}")


for path, expected in EXPECTED_HASHES.items():
    require(path.is_file(), f"missing source {path}")
    require(sha256(path) == expected, f"hash changed for {path.name}")

primary = PRIMARY.read_text(encoding="utf-8", errors="replace")
supplement = SUPPLEMENT.read_text(encoding="utf-8", errors="replace")
supplement2 = SUPPLEMENT2.read_text(encoding="utf-8", errors="replace")

valid_decode_rounds = {
    int(value) for value in re.findall(r"^decode_valid,(\d+),", primary, re.MULTILINE)
}
invalid_decode_rounds = {
    int(value) for value in re.findall(r"^decode_invalid,(\d+),", primary, re.MULTILINE)
}
decode: dict[int, dict[str, tuple[float, float, float, float]]] = {}
for match in re.finditer(
    r"^decode_metric,(\d+),(F[123]),([0-9.]+),([0-9.]+),([0-9.]+),(\d+)$",
    primary,
    re.MULTILINE,
):
    round_no = int(match.group(1))
    decode.setdefault(round_no, {})[match.group(2)] = tuple(float(v) for v in match.groups()[2:])

require(len(valid_decode_rounds) == 10, "decode valid round count is not 10")
require(not invalid_decode_rounds, "decode contains invalid rounds")
require(set(decode) == valid_decode_rounds, "decode round ownership mismatch")
require(all(set(row) == set(VARIANTS) for row in decode.values()), "decode variant cell missing")
require(primary.count("h264 (native) -> wrapped_avframe (native)") == 30, "native decoder evidence count")
require(len(re.findall(r"^sample_end=OK$", primary, re.MULTILINE)) == 30, "decode sentinel count")
require("MEASUREMENT_FAIL L3" not in primary, "L3 failure present")

valid_startup_rounds = {
    int(value) for value in re.findall(r"^startup_valid,(\d+)$", supplement, re.MULTILINE)
}
invalid_startup_rounds = {
    int(value) for value in re.findall(r"^startup_invalid,(\d+),", supplement, re.MULTILINE)
}
startup: dict[int, dict[str, float]] = {}
for match in re.finditer(r"^startup_triple,(\d+),(\d+),(\d+),(\d+)$", supplement, re.MULTILINE):
    startup[int(match.group(1))] = {
        "F1": float(match.group(2)),
        "F2": float(match.group(3)),
        "F3": float(match.group(4)),
    }
require(len(valid_startup_rounds) == 30, "startup valid round count is not 30")
require(not invalid_startup_rounds, "startup contains invalid rounds")
require(set(startup) == valid_startup_rounds, "startup round ownership mismatch")

memory: dict[str, dict[str, list[float]]] = {
    variant: {key: [] for key in ("Rss", "Pss", "Private_Clean", "Private_Dirty", "maxrss")}
    for variant in VARIANTS
}
for match in re.finditer(
    r"^memory_metric,(\d+),(F[123]),(\d+),(\d+),(\d+),(\d+),(\d+)$",
    supplement,
    re.MULTILINE,
):
    variant = match.group(2)
    for key, value in zip(memory[variant], match.groups()[2:]):
        memory[variant][key].append(float(value))
require(all(len(values) == 3 for cells in memory.values() for values in cells.values()), "memory cell n is not 3")
require(len(re.findall(r"^sample_end=OK$", supplement, re.MULTILINE)) == 9, "memory sentinel count")

sizes: dict[tuple[str, str, str], int] = {}
for match in re.finditer(
    r"^size_host,(F[123]),(baseline|gc),(unstripped|stripped),(\d+)$",
    supplement2,
    re.MULTILINE,
):
    sizes[(match.group(1), match.group(2), match.group(3))] = int(match.group(4))
board_sizes: dict[tuple[str, str, str], int] = {}
for match in re.finditer(
    r"^size_board,(F[123]),(baseline|gc),(stripped),(\d+)$",
    supplement2,
    re.MULTILINE,
):
    board_sizes[(match.group(1), match.group(2), match.group(3))] = int(match.group(4))
require(len(sizes) == 12, "host size matrix is not 12 cells")
require(len(board_sizes) == 6, "board size matrix is not 6 deployed cells")
require(all(sizes[key] == value for key, value in board_sizes.items()), "board size differs")
require("size_board_verification=PASS" in supplement2, "size verification did not pass")
require("function_surface_verification=PASS" in supplement2, "function verification did not pass")
require("MEASUREMENT_FFMPEG_SUPPLEMENT2_PASS" in supplement2, "supplement2 terminal marker")

function_states = {}
for key in ("strcoll", "iconv", "setlocale", "getaddrinfo"):
    match = re.search(rf"^{key}=(PRESENT|ABSENT)$", supplement2, re.MULTILINE)
    require(match is not None, f"missing function state {key}")
    function_states[key] = match.group(1)

decode_series = {
    variant: {
        metric: [decode[round_no][variant][index] for round_no in sorted(valid_decode_rounds)]
        for index, metric in enumerate(("utime", "stime", "rtime", "maxrss"))
    }
    for variant in VARIANTS
}
startup_series = {
    variant: [startup[round_no][variant] / 1_000_000.0 for round_no in sorted(valid_startup_rounds)]
    for variant in VARIANTS
}

minimum_l3_ratio = min(
    decode[round_no][variant][0] / statistics.median(decode[round_no][v][0] for v in VARIANTS)
    for round_no in valid_decode_rounds
    for variant in VARIANTS
)

lines: list[str] = []
lines += [
    "# FFmpeg 8.0.1 H.264 software-decode island — measurement report",
    "",
    "> Status: FatTank data verification passed; final disposition recorded below.",
    "",
    "## 1. Scope and non-goals",
    "",
    "The measured object is the Tizen official FFmpeg source tree built as a minimal private-prefix CLI island with only the native H.264 software decoder, MOV demuxer, file protocol, and null output path. F1 is glibc/ptmalloc dynamic, F2 is musl/mallocng static, and F3 is musl/mimalloc static.",
    "",
    "The result covers this isolated static-CLI form only. It does not extend to shared libavcodec, gst-libav, libmm-player, hardware decode, encoding, networking, or external libraries.",
    "",
    "## 2. Provenance and frozen inputs",
    "",
    "| Item | Frozen value | Evidence |",
    "|---|---|---|",
    "| Source | Tizen `platform/upstream/ffmpeg`, branch observed as `tizen` | `results/logs/ffmpeg-src-provenance.txt` |",
    "| Commit | `c15459c9fc8976827db7eaac643e84db2d1ea534` | same |",
    "| Version | FFmpeg 8.0.1; libavutil 60.8.100 | same |",
    "| Frozen archive | `f12101bcbec88f664bf50daf96bb4dbdd9326615ff11e1555f0eb3b1ff37f2f8` | `packaging/ffmpeg-tizen-src.sha256` |",
    "| Test material | `cabi.mp4`, 88,765,233 bytes, `f58743eaba12f47320c4d8ea0ea7f9418b91728335c74df0c352d9730f63dd48` | `packaging/ffmpeg-testclip.sha256` |",
    "| Compiler / ABI | clang 22.1.8; ARMv7 softfp | `results/logs/ffmpeg-build-evidence/compiler-decision-ffmpeg.txt` |",
    "| License | LGPL 2.1 or later | `results/logs/ffmpeg-build-evidence/configure-equivalence.txt` |",
    "",
    "Tizen platform modifications exist as git commits inside the frozen source tree. A spec patch count of zero is therefore the normal representation, not evidence that platform changes are absent. C8a uses the frozen Tizen tree itself as its accounting baseline. Differences between that platform tree and upstream FFmpeg 8.0.1 are outside this pilot's scope.",
    "",
    "## 3. Method and three-source merge",
    "",
    "The primary run completed decode before a startup parser stop. Following the approved malloc-truncation precedent, valid measurement phases are retained and missing/invalid reading phases are supplied by immutable supplements; no value is overwritten, selected, removed, or reweighted.",
    "",
    "| Measurement | Source file | SHA-256 |",
    "|---|---|---|",
    f"| Decode | `results/results-ffmpeg.txt` | `{EXPECTED_HASHES[PRIMARY]}` |",
    f"| Startup, memory | `results/results-ffmpeg-supplement.txt` | `{EXPECTED_HASHES[SUPPLEMENT]}` |",
    f"| Size, function surface | `results/results-ffmpeg-supplement2.txt` | `{EXPECTED_HASHES[SUPPLEMENT2]}` |",
    "",
    "Decode used ten within-round rotating triples. Every command used `-c:v h264 -i $CLIP -map 0:v:0 -an -t 30 -f null - -benchmark`; rounds cooled for 30 seconds, waited until temperature was at most 65°C whenever necessary, and recorded current/max frequency before and after. Startup used 30 rotating timer triples. Memory used three rotating repetitions per variant, `-re` only to keep the decoder alive for the fifth-second smaps_rollup snapshot, and recorded FFmpeg maxrss at completion. Percentiles use linear interpolation at `(n-1)×p`; paired deltas are the median of within-round `(candidate-reference)/reference` values.",
    "",
    "## 4. Software-decode gates",
    "",
    "| Layer | Result | Evidence |",
    "|---|---|---|",
    "| L1 build-time exclusion | PASS: hardware accelerators disabled; decoder set locked to H.264 | `results/logs/ffmpeg-build-evidence/ffmpeg-configure-commands.txt` |",
    "| L2 configure equivalence | PASS: decoder exactly `h264`, hwaccels empty, ARM/NEON summary byte-identical | `results/logs/ffmpeg-build-evidence/configure-equivalence.txt` |",
    f"| L3 runtime identity | PASS: 30/30 native H.264 mappings and benchmarks; minimum sample/round-median utime ratio `{minimum_l3_ratio:.3f}` (>0.5) | primary raw file |",
    "| F3 allocator identity | PASS: mimalloc banner positive for F3, negative for F1/F2 | `results/logs/deploy-ffmpeg-cabi.log` |",
    "| ELF / softfp / F3 symbol gates | PASS | `results/logs/gbs-build-ffmpeg.log`, compiler decision |",
    "| Frozen source review gate | PASS after a proven pre-signoff block | `results/logs/ffmpeg-source-review-gate.log`, `results/logs/ffmpeg-source-review.md` |",
    "| Patch consistency | PASS; declared/applied count 0/0 | `results/logs/ffmpeg-build-evidence/patch-consistency.txt` |",
    "",
    "## 5. Decode results",
    "",
    "All decode cells below come from `results/results-ffmpeg.txt`.",
    "",
    "| Variant | Metric | Median | p10 | p95 | n |",
    "|---|---:|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    for metric in ("utime", "stime", "rtime", "maxrss"):
        median, p10, p95, n = summary(decode_series[variant][metric])
        unit = " KiB" if metric == "maxrss" else " s"
        digits = 0 if metric == "maxrss" else 3
        lines.append(
            f"| {variant} ({VARIANT_LABELS[variant]}) | {metric} | {fmt(median, digits)}{unit} | {fmt(p10, digits)}{unit} | {fmt(p95, digits)}{unit} | {n} |"
        )

lines += [
    "",
    "### Paired utime deltas and frozen E-P mapping",
    "",
    "Positive delta means more CPU time than the reference. The status column is a mechanical application of the frozen ±2%/±5% bands, not the final FatTank conclusion.",
    "",
    "| Candidate vs reference | Paired relative-difference median | Frozen-band status | n pairs |",
    "|---|---:|---|---:|",
]
for candidate, reference in (("F2", "F1"), ("F3", "F2"), ("F3", "F1")):
    delta = paired_delta(decode_series[candidate]["utime"], decode_series[reference]["utime"])
    lines.append(f"| {candidate} vs {reference} | {delta:+.3f}% | {band(delta)} | 10 |")

lines += [
    "",
    "## 6. Startup results",
    "",
    "All startup cells come from `results/results-ffmpeg-supplement.txt`; units are milliseconds per `fork+exec+ffmpeg -version`.",
    "",
    "| Variant | Median (ms) | p10 | p95 | n |",
    "|---|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    median, p10, p95, n = summary(startup_series[variant])
    lines.append(f"| {variant} | {median:.3f} | {p10:.3f} | {p95:.3f} | {n} |")
lines += [
    "",
    "| Candidate vs reference | Paired median delta | n pairs |",
    "|---|---:|---:|",
]
for candidate, reference in (("F2", "F1"), ("F3", "F2"), ("F3", "F1")):
    delta = paired_delta(startup_series[candidate], startup_series[reference])
    lines.append(f"| {candidate} vs {reference} | {delta:+.3f}% | 30 |")

lines += [
    "",
    "## 7. Memory results",
    "",
    "All memory cells come from `results/results-ffmpeg-supplement.txt`; values are KiB at decode second 5 except maxrss, which is FFmpeg's completion value. Each cell has n=3.",
    "",
    "| Variant | Metric | Median | p10 | p95 | n |",
    "|---|---|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    for metric in ("Rss", "Pss", "Private_Clean", "Private_Dirty", "maxrss"):
        median, p10, p95, n = summary(memory[variant][metric])
        lines.append(f"| {variant} | {metric} | {median:.0f} | {p10:.0f} | {p95:.0f} | {n} |")
lines += [
    "",
    "### F3 versus F2 memory premium",
    "",
    "| Metric | F2 median (KiB) | F3 median (KiB) | Difference | Relative |",
    "|---|---:|---:|---:|---:|",
]
for metric in ("Pss", "Private_Dirty", "maxrss"):
    f2 = summary(memory["F2"][metric])[0]
    f3 = summary(memory["F3"][metric])[0]
    lines.append(f"| {metric} | {f2:.0f} | {f3:.0f} | {f3-f2:+.0f} KiB | {(f3-f2)/f2*100:+.3f}% |")

lines += [
    "",
    "## 8. Size matrix",
    "",
    "All 12 build cells and the six deployed stripped cross-checks come from `results/results-ffmpeg-supplement2.txt`. Board values matched exactly.",
    "",
    "| Variant | Mode | Unstripped bytes | Stripped bytes | Strip reduction | Board stripped |",
    "|---|---|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    for mode in ("baseline", "gc"):
        unstripped = sizes[(variant, mode, "unstripped")]
        stripped = sizes[(variant, mode, "stripped")]
        reduction = (unstripped - stripped) / unstripped * 100.0
        lines.append(f"| {variant} | {mode} | {unstripped} | {stripped} | {reduction:.3f}% | {board_sizes[(variant, mode, 'stripped')]} |")
lines += [
    "",
    "### gc-sections change versus each baseline",
    "",
    "| Variant | Unstripped delta | Unstripped relative | Stripped delta | Stripped relative |",
    "|---|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    base_u = sizes[(variant, "baseline", "unstripped")]
    gc_u = sizes[(variant, "gc", "unstripped")]
    base_s = sizes[(variant, "baseline", "stripped")]
    gc_s = sizes[(variant, "gc", "stripped")]
    lines.append(
        f"| {variant} | {gc_u-base_u:+d} | {(gc_u-base_u)/base_u*100:+.3f}% | {gc_s-base_s:+d} | {(gc_s-base_s)/base_s*100:+.3f}% |"
    )

lines += [
    "",
    "## 9. Function surface",
    "",
    "Source: `results/results-ffmpeg-supplement2.txt`, byte-matched to the packaged build evidence for F2.",
    "",
    "| Symbol | F2 state |",
    "|---|---|",
]
for key in ("strcoll", "iconv", "setlocale", "getaddrinfo"):
    lines.append(f"| `{key}` | {function_states[key]} |")

lines += [
    "",
    "`iconv` four-state classification: the symbol exists but the measured H.264 decode path does not reach it, so the current classification is **NOT_USED(runtime)**. If subtitle or character-set features are enabled later, it becomes **FALLBACK_REQUIRED** because of musl iconv's encoding-direction gap.",
]

lines += [
    "",
    "## 10. Modification accounting",
    "",
    "| Account | Recorded value | Evidence |",
    "|---|---|---|",
    "| C8a | FFmpeg source diff outside frozen Tizen tree = 0 | `c8a-source-diff.txt` |",
    "| C8a baseline | Frozen Tizen tree, including platform commits | `c8-ledger.txt` |",
    "| C8b.1 | New isolated RPM spec/private prefix | same |",
    "| C8b.2 | Frozen archive normalization during prep | same |",
    "| C8b.3 | Minimal software-decode configure set | same |",
    "| C8b.4 | Reused musl wrapper start-group integration | same |",
    "| C8b.5 | Added mimalloc object through extra-libs | same |",
    "| Semantic workaround | NONE | same |",
    "",
    "## 11. PerfHotSpotAnalyzer cross-validation",
    "",
    "The comparison strength is aligned on all available axes: the replacement `cabi.mp4` is a PerfHotSpotAnalyzer-source sample, FFmpeg is 8.0.1, decoding is explicitly native H.264, audio is disabled, and the command uses the same 30-second null-output benchmark window (`-an -t 30 -f null - -benchmark`). This removes the earlier full-file/window mismatch and makes utime directly comparable by magnitude.",
    "",
    "| Current island variant | utime median (s) | p10 | p95 | n |",
    "|---|---:|---:|---:|---:|",
]
for variant in VARIANTS:
    median, p10, p95, n = summary(decode_series[variant]["utime"])
    lines.append(f"| {variant} | {median:.3f} | {p10:.3f} | {p95:.3f} | {n} |")
lines += [
    "",
    "FatTank's verified disposition is **PASS at the magnitude level**: source material, FFmpeg version, decoder, audio policy, 30-second window, null output, and benchmark form are aligned. The historical numeric utime record is not present in this repository, so the exact numeric comparison will be added separately when FatTank supplies that record; no historical value is invented here.",
    "",
    "## 12. Tizen full build versus island configuration",
    "",
    "The archived Tizen spec describes a shared-library platform build with many audio/video parsers, demuxers, decoders (including HEVC/VP8/VP9), encoders, filters, bitstream filters, swscale/swresample, and profile-dependent options. The island instead uses `--disable-everything --disable-autodetect`, static linking for F2/F3, exactly H.264 decode, MOV demux, H.264 parser, file protocol, null muxer, wrapped_avframe, null filter, pthreads, and NEON. This is a deliberate capability contraction for controlled libc/allocator comparison, not a replacement platform packaging recipe.",
    "",
    "## 13. Invalid samples and incidents",
    "",
    "| Source/phase | INVALID | Disposition | Evidence |",
    "|---|---:|---|---|",
    "| Primary decode | 0 | 30/30 metrics retained | `results/results-ffmpeg.txt` |",
    "| Primary startup attempt | 1 reading attempt | Excluded; verbose-child timer parser incident | `incident-ffmpeg-startup-timer-output.md` |",
    "| Supplement startup | 0 | 30/30 triples retained | `results/results-ffmpeg-supplement.txt` |",
    "| Supplement memory | 0 | 9/9 retained | same |",
    "| Supplement size attempt | 1 reading attempt | Excluded; SDB stdin pollution | `incident-ffmpeg-size-matrix-sdb-stdin.md` |",
    "| Supplement2 size/function | 0 | six board cells and function scan retained | `results/results-ffmpeg-supplement2.txt` |",
    "",
    "## 14. Caveats",
    "",
    "- Single board, single H.264 material, and a 30-second window; no workload-general claim is made.",
    "- The island excludes the platform framework/shared-library integration and all hardware decode paths.",
    "- Memory smaps uses `-re` solely to guarantee a live fifth-second snapshot; decode performance does not use `-re`.",
    "- The first board file was misplaced HEVC and its digest remains explicitly revoked; `cabi.mp4` is the active frozen H.264 input.",
    "- RPM deployment skipped Tizen security plugins with `--noplugins`; host/board payload hashes matched, so this does not change measured binaries.",
    "- Two reading-layer incidents were handled with immutable supplements; their invalid attempts are listed rather than erased.",
    "- Historical logs retain operator paths under the approved evidence-integrity ruling.",
    "",
    "## 15. Final conclusions",
    "",
    "1. **Compute-intensive CLI libc substitution is performance-equivalent.** All three paired utime comparisons fall inside the frozen ±2% band: F2 vs F1 −1.102%, F3 vs F2 +1.551%, and F3 vs F1 −0.291%.",
    "2. **The startup reduction is reproduced.** F2 (musl/mallocng static) versus F1 (glibc/ptmalloc dynamic) has a paired startup median of −53.228% across 30 valid triples.",
    "3. **Allocator choice follows workload profile.** mallocng is the sweet spot for this compute-intensive profile. Mimalloc carries an approximately +17% Pss/private-dirty premium versus mallocng and is granted only to allocation-hot profiles where that trade is justified.",
    "",
    "## 16. Evidence index and review state",
    "",
    "- Build: `results/logs/gbs-build-ffmpeg.log`, `results/logs/ffmpeg-build-evidence/`",
    "- Deploy/smoke: `results/logs/deploy-ffmpeg-cabi.log`",
    "- Three source hashes: `results/logs/ffmpeg-three-source-sha256.log`",
    "- Timer parser regression: `results/logs/ffmpeg-timer-parser-selfcheck.log`",
    "- SDB stdin regression: `results/logs/sdb-stdin-isolation-selfcheck.log`",
    "- Raw measurements: the three files listed in section 3",
    "",
    "Final FatTank disposition: **DATA VERIFIED; conclusions recorded in section 15**.",
]

OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"REPORT_FFMPEG_PASS output={OUT}")
