#!/usr/bin/env python3
"""Verify L1 evidence integrity and L2 directional reproduction criteria."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
from pathlib import Path
import re
import statistics
import sys

from gen_report import parse_malloc_samples, parse_metric_samples


VARIANTS = ("glibc-dyn", "musl-static", "musl-dyn", "musl-mi")
BASE_VARIANTS = VARIANTS[:3]
THREADS = (1, 4)


@dataclass
class Outcome:
    layer: str
    name: str
    status: str
    detail: str


class Verification:
    def __init__(self) -> None:
        self.outcomes: list[Outcome] = []

    def add(self, layer: str, name: str, status: str, detail: str) -> None:
        self.outcomes.append(Outcome(layer, name, status, detail))
        print(f"{layer} {name}: {status} — {detail}")

    def boolean(self, layer: str, name: str, condition: bool, detail: str) -> None:
        self.add(layer, name, "PASS" if condition else "FAIL", detail)

    def inconclusive(self, layer: str, name: str, detail: str) -> None:
        self.add(layer, name, "INCONCLUSIVE", detail)

    def exit_code(self) -> int:
        if any(item.status == "FAIL" for item in self.outcomes):
            return 1
        if any(item.status == "INCONCLUSIVE" for item in self.outcomes):
            return 2
        return 0


def read_text(path: Path, verification: Verification, layer: str, name: str) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        verification.inconclusive(layer, name, f"cannot read {path}: {error}")
        return None


def check_markers(
    verification: Verification,
    layer: str,
    name: str,
    path: Path,
    markers: tuple[str, ...],
) -> None:
    text = read_text(path, verification, layer, name)
    if text is None:
        return
    missing = [marker for marker in markers if marker not in text]
    verification.boolean(
        layer,
        name,
        not missing,
        f"path={path}; missing={missing or 'NONE'}",
    )


def valid_startup_quads(text: str) -> list[tuple[int, int, int, int, int]]:
    invalid = {
        int(value)
        for value in re.findall(r"^startup_invalid,(\d+),", text, re.MULTILINE)
    }
    return [
        tuple(map(int, values))
        for values in re.findall(
            r"^startup_quad,(\d+),(\d+),(\d+),(\d+),(\d+)$",
            text,
            re.MULTILINE,
        )
        if int(values[0]) not in invalid
    ]


def valid_startup_triples(text: str) -> list[tuple[int, int, int, int]]:
    invalid = {
        int(value)
        for value in re.findall(r"^startup_invalid,(\d+),", text, re.MULTILINE)
    }
    return [
        tuple(map(int, values))
        for values in re.findall(
            r"^startup_triple,(\d+),(\d+),(\d+),(\d+)$",
            text,
            re.MULTILINE,
        )
        if int(values[0]) not in invalid
    ]


def malloc_cells(samples: list[object]) -> dict[tuple[str, int], list[float]]:
    cells: dict[tuple[str, int], list[float]] = {}
    for sample in samples:
        if not sample.valid:
            continue
        cells.setdefault((sample.variant, sample.threads), []).append(
            float(sample.values["ns_per_op_mean"])
        )
    return cells


def median_metric(samples: list[object], variant: str, key: str) -> float | None:
    values = [
        float(sample.values[key])
        for sample in samples
        if sample.valid and sample.variant == variant and key in sample.values
    ]
    return statistics.median(values) if values else None


def load_reference(path: Path, verification: Verification) -> dict[str, object] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        verification.inconclusive("L2", "reference_json", f"cannot load {path}: {error}")
        return None
    if data.get("schema_version") != 1 or not isinstance(data.get("metrics"), dict):
        verification.add("L2", "reference_json", "FAIL", "unsupported schema or missing metrics")
        return None
    verification.add("L2", "reference_json", "PASS", f"path={path}; schema_version=1")
    return data


def reference_metric(reference: dict[str, object], key: str) -> dict[str, object] | None:
    metrics = reference.get("metrics")
    if not isinstance(metrics, dict):
        return None
    value = metrics.get(key)
    return value if isinstance(value, dict) else None


def add_l2_numeric(
    verification: Verification,
    name: str,
    reproduced: float | None,
    reference: dict[str, object],
    reference_key: str,
    operator: str,
    threshold: float,
    unit: str,
) -> None:
    record = reference_metric(reference, reference_key)
    if reproduced is None or not math.isfinite(reproduced):
        verification.inconclusive("L2", name, "reproduced value is unavailable")
        return
    if record is None or not isinstance(record.get("value"), (int, float)):
        verification.inconclusive("L2", name, f"reference metric missing: {reference_key}")
        return
    reference_value = float(record["value"])
    if operator == "<=":
        passed = reproduced <= threshold
    elif operator == ">=":
        passed = reproduced >= threshold
    else:
        raise ValueError(f"unsupported operator: {operator}")
    verification.boolean(
        "L2",
        name,
        passed,
        (
            f"reproduced={reproduced:.6g}{unit}; reference={reference_value:.6g}{unit}; "
            f"criterion={operator}{threshold:g}{unit}; source={record.get('source', 'UNKNOWN')}"
        ),
    )


def parse_args(repo_root: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, default=repo_root / "results/results.txt")
    parser.add_argument(
        "--supplement",
        type=Path,
        default=repo_root / "results/results-supplement.txt",
    )
    parser.add_argument(
        "--mimalloc-results",
        type=Path,
        default=repo_root / "results/results-mimalloc.txt",
    )
    parser.add_argument(
        "--evidence-root", type=Path, default=repo_root / "results"
    )
    parser.add_argument("--build-log", type=Path)
    parser.add_argument("--deploy-log", type=Path)
    parser.add_argument(
        "--reference",
        type=Path,
        default=repo_root / "docs/reference-results.json",
    )
    return parser.parse_args()


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    args = parse_args(repo_root)
    verification = Verification()
    build_log = args.build_log or args.evidence_root / "logs/gbs-build-mimalloc.log"
    deploy_log = args.deploy_log or args.evidence_root / "logs/deploy-mimalloc.log"
    decision_log = args.evidence_root / "logs/compiler-decision-mimalloc.txt"

    check_markers(
        verification,
        "L1",
        "build_source_and_hash_gates",
        build_log,
        (
            "SOURCE_PREFLIGHT_PASS count=7",
            "gate.source1_sha256=PASS",
            "gate.source5_sha256=PASS",
        ),
    )
    check_markers(
        verification,
        "L1",
        "build_mimalloc_gates",
        build_log,
        (
            "gate.mimalloc_stdatomic_header=PASS",
            "gate.mimalloc_lfs64_symbols=PASS",
            "gate.musl_mi_command_delta=PASS",
            "gate.mimalloc_symbol.malloc=PASS",
            "gate.mimalloc_symbol.free=PASS",
            "gate.mimalloc_symbol.calloc=PASS",
            "gate.mimalloc_symbol.realloc=PASS",
            "gate.mimalloc_symbol.posix_memalign=PASS",
            "gate.mimalloc_symbol.aligned_alloc=PASS",
            "gate.mimalloc_symbol.malloc_usable_size=PASS",
        ),
    )
    check_markers(
        verification,
        "L1",
        "build_elf_abi_and_final_gates",
        build_log,
        (
            "gate.micro.musl-static=PASS",
            "gate.micro.musl-mi.structure=PASS",
            "gate.micro.musl-dyn=PASS interpreter=/opt/usr/musl-demo/lib/ld-musl-arm.so.1 needed=libc.so",
            "gate.micro.glibc-dyn=PASS",
            "gate.arm32_softfp_abi_consistency=PASS",
            "BUILD_GATE_PASS: all comparison artifacts passed",
            "BUILD_GBS_PASS",
        ),
    )
    check_markers(
        verification,
        "L1",
        "compiler_runtime_decision",
        decision_log,
        (
            "expected_clang_version=22.1.8",
            "selected_rtlib=libgcc.a",
            "rtlib_consistency=PASS",
            "mimalloc_command_delta=PASS",
            "mimalloc_symbol_owner=mimalloc.o",
            "mimalloc_symbol_gate=PASS",
            "platform_float_abi=softfp",
            "abi_consistency=PASS",
            "mimalloc_abi_consistency=PASS",
            "mechanical_gates=PASS",
        ),
    )
    check_markers(
        verification,
        "L1",
        "deployment_and_runtime_controls",
        deploy_log,
        (
            "binary_hash_comparison=PASS",
            "smoke.variant=micro.glibc-dyn",
            "smoke.variant=micro.musl-static",
            "smoke.variant=micro.musl-dyn",
            "smoke.variant=micro.musl-mi",
            "gate.runtime_mimalloc_banner.micro.musl-mi=PASS expected=present",
            "gate.runtime_mimalloc_banner.micro.glibc-dyn=PASS expected=absent",
            "gate.runtime_mimalloc_banner.micro.musl-static=PASS expected=absent",
            "gate.runtime_mimalloc_banner.micro.musl-dyn=PASS expected=absent",
            "gate.runtime_mimalloc_override=PASS positive=1 negative_controls=3",
            "DEPLOY_PASS",
        ),
    )

    baseline_text = read_text(args.results, verification, "L1", "baseline_results")
    supplement_text = read_text(
        args.supplement, verification, "L1", "baseline_supplement"
    )
    mimalloc_text = read_text(
        args.mimalloc_results, verification, "L1", "mimalloc_results"
    )

    if baseline_text is not None:
        triples = valid_startup_triples(baseline_text)
        verification.boolean(
            "L1",
            "baseline_startup_samples",
            len(triples) >= 30,
            f"valid={len(triples)}; required>=30",
        )
        dns_headers = re.findall(r"^dnscfg=", baseline_text, re.MULTILINE)
        locale_headers = re.findall(r"^localecfg=", baseline_text, re.MULTILINE)
        verification.boolean(
            "L1",
            "baseline_dns_locale_coverage",
            len(dns_headers) >= 6 and len(locale_headers) >= 6,
            f"dns_headers={len(dns_headers)}; locale_headers={len(locale_headers)}; required>=6 each",
        )

    if baseline_text is not None and supplement_text is not None:
        base_malloc = parse_malloc_samples(baseline_text, args.results.name)
        supplement_malloc = parse_malloc_samples(supplement_text, args.supplement.name)
        combined = base_malloc + supplement_malloc
        cells = malloc_cells(combined)
        counts = {
            f"{variant}/t{threads}": len(cells.get((variant, threads), []))
            for variant in BASE_VARIANTS
            for threads in THREADS
        }
        malformed = [sample.label for sample in combined if sample.variant == "UNKNOWN"]
        verification.boolean(
            "L1",
            "baseline_malloc_integrity",
            all(value >= 5 for value in counts.values()) and not malformed,
            (
                f"valid_cells={counts}; invalid_base={sum(not sample.valid for sample in base_malloc)}; "
                f"invalid_supplement={sum(not sample.valid for sample in supplement_malloc)}; malformed={malformed or 'NONE'}"
            ),
        )

    quads: list[tuple[int, int, int, int, int]] = []
    mi_malloc_cells: dict[tuple[str, int], list[float]] = {}
    mi_mem: list[object] = []
    mi_threads: list[object] = []
    if mimalloc_text is not None:
        quads = valid_startup_quads(mimalloc_text)
        declared_valid = len(
            re.findall(r"^startup_valid,\d+$", mimalloc_text, re.MULTILINE)
        )
        declared_invalid = len(
            re.findall(r"^startup_invalid,", mimalloc_text, re.MULTILINE)
        )
        verification.boolean(
            "L1",
            "mimalloc_startup_samples",
            len(quads) >= 30 and declared_valid >= 30 and declared_invalid == 0,
            f"valid_quads={len(quads)}; declared_valid={declared_valid}; invalid={declared_invalid}",
        )

        governor_values = re.findall(
            r"^governor\.cpu\d+=(.+)$", mimalloc_text, re.MULTILINE
        )
        controls_pass = (
            bool(governor_values)
            and all(value == "performance" for value in governor_values)
            and "residual.before=NONE" in mimalloc_text
            and "residual.after=NONE" in mimalloc_text
            and "frequency.before.invalid=0" in mimalloc_text
            and "frequency.after.invalid=0" in mimalloc_text
            and "measurement.finish_utc=" in mimalloc_text
        )
        verification.boolean(
            "L1",
            "board_measurement_controls",
            controls_pass,
            f"governors={governor_values}; residual/frequency/finish markers required",
        )

        mi_malloc = parse_malloc_samples(mimalloc_text, args.mimalloc_results.name)
        mi_malloc_cells = malloc_cells(mi_malloc)
        cell_counts = {
            f"{variant}/t{threads}": len(mi_malloc_cells.get((variant, threads), []))
            for variant in VARIANTS
            for threads in THREADS
        }
        invalid_malloc = [sample.label for sample in mi_malloc if not sample.valid]
        verification.boolean(
            "L1",
            "mimalloc_malloc_integrity",
            all(value >= 5 for value in cell_counts.values()) and not invalid_malloc,
            f"valid_cells={cell_counts}; invalid={invalid_malloc or 'NONE'}",
        )

        mi_mem = parse_metric_samples(mimalloc_text, "mem")
        mi_threads = parse_metric_samples(mimalloc_text, "threads")
        mem_counts = {
            variant: sum(sample.valid and sample.variant == variant for sample in mi_mem)
            for variant in VARIANTS
        }
        thread_counts = {
            variant: sum(
                sample.valid and sample.variant == variant for sample in mi_threads
            )
            for variant in VARIANTS
        }
        invalid_metrics = [
            f"{sample.kind}:{sample.variant}:rep={sample.rep}"
            for sample in (*mi_mem, *mi_threads)
            if not sample.valid
        ]
        verification.boolean(
            "L1",
            "mimalloc_mem_threads_integrity",
            (
                all(value >= 3 for value in mem_counts.values())
                and all(value >= 1 for value in thread_counts.values())
                and not invalid_metrics
            ),
            f"mem={mem_counts}; threads={thread_counts}; invalid={invalid_metrics or 'NONE'}",
        )

    reference = load_reference(args.reference, verification)
    if reference is not None:
        startup_delta = (
            statistics.median((row[2] - row[1]) / row[1] * 100 for row in quads)
            if quads
            else None
        )
        add_l2_numeric(
            verification,
            "startup_static_vs_glibc",
            startup_delta,
            reference,
            "startup_static_vs_glibc_delta_pct",
            "<=",
            -30.0,
            "%",
        )

        glibc_vmsize = median_metric(mi_threads, "glibc-dyn", "VmSize")
        static_vmsize = median_metric(mi_threads, "musl-static", "VmSize")
        thread_ratio = (
            glibc_vmsize / static_vmsize
            if glibc_vmsize is not None and static_vmsize not in (None, 0)
            else None
        )
        add_l2_numeric(
            verification,
            "threads_vmsize_glibc_over_musl_static",
            thread_ratio,
            reference,
            "threads_vmsize_glibc_over_musl_static",
            ">=",
            20.0,
            "x",
        )

        glibc_t4 = mi_malloc_cells.get(("glibc-dyn", 4), [])
        static_t4 = mi_malloc_cells.get(("musl-static", 4), [])
        mi_t4 = mi_malloc_cells.get(("musl-mi", 4), [])
        glibc_t4_median = statistics.median(glibc_t4) if glibc_t4 else None
        static_t4_median = statistics.median(static_t4) if static_t4 else None
        mi_t4_median = statistics.median(mi_t4) if mi_t4 else None
        mallocng_glibc = (
            static_t4_median / glibc_t4_median
            if static_t4_median is not None and glibc_t4_median not in (None, 0)
            else None
        )
        mimalloc_mallocng = (
            mi_t4_median / static_t4_median
            if mi_t4_median is not None and static_t4_median not in (None, 0)
            else None
        )
        add_l2_numeric(
            verification,
            "malloc_t4_mallocng_over_glibc",
            mallocng_glibc,
            reference,
            "malloc_t4_mallocng_over_glibc",
            ">=",
            2.0,
            "x",
        )
        add_l2_numeric(
            verification,
            "malloc_t4_mimalloc_over_mallocng",
            mimalloc_mallocng,
            reference,
            "malloc_t4_mimalloc_over_mallocng",
            "<=",
            0.5,
            "x",
        )

        glibc_dirty = median_metric(mi_mem, "glibc-dyn", "Private_Dirty")
        static_dirty = median_metric(mi_mem, "musl-static", "Private_Dirty")
        dirty_record = reference_metric(
            reference, "private_dirty_musl_static_less_than_glibc"
        )
        if glibc_dirty is None or static_dirty is None:
            verification.inconclusive(
                "L2", "private_dirty_musl_static_less_than_glibc", "memory values unavailable"
            )
        elif dirty_record is None:
            verification.inconclusive(
                "L2", "private_dirty_musl_static_less_than_glibc", "reference metric missing"
            )
        else:
            verification.boolean(
                "L2",
                "private_dirty_musl_static_less_than_glibc",
                static_dirty < glibc_dirty,
                (
                    f"reproduced={static_dirty:g}kB<{glibc_dirty:g}kB; "
                    f"reference={dirty_record.get('musl_static_kb')}kB<"
                    f"{dirty_record.get('glibc_kb')}kB; source={dirty_record.get('source', 'UNKNOWN')}"
                ),
            )

    counts = {status: 0 for status in ("PASS", "FAIL", "INCONCLUSIVE")}
    for outcome in verification.outcomes:
        counts[outcome.status] += 1
    code = verification.exit_code()
    overall = "PASS" if code == 0 else "FAIL" if code == 1 else "INCONCLUSIVE"
    print(
        f"SUMMARY overall={overall} pass={counts['PASS']} fail={counts['FAIL']} "
        f"inconclusive={counts['INCONCLUSIVE']} exit_code={code}"
    )
    return code


if __name__ == "__main__":
    raise SystemExit(main())
