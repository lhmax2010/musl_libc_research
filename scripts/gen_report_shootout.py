#!/usr/bin/env python3
"""Generate the allocator shootout exchange-rate report from immutable raw data."""

from __future__ import annotations

import hashlib
import math
import re
import statistics
import sys
from pathlib import Path


VARIANTS = ("S1", "S2", "S3", "S4", "S5", "S6")
MEASURED_VARIANTS = ("S1", "S2", "S3", "S4", "S6")
LABELS = {
    "S1": "glibc-dyn",
    "S2": "musl-static (mallocng)",
    "S3": "musl + mimalloc default",
    "S4": "musl + mimalloc tuned",
    "S5": "musl + rpmalloc",
    "S6": "musl + Scudo standalone",
}


def median(values: list[float]) -> float:
    return statistics.median(values) if values else math.nan


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fmt(value: float, digits: int = 1) -> str:
    return "NOT_RUN" if math.isnan(value) else f"{value:.{digits}f}"


def ratio(value: float, anchor: float) -> float:
    if math.isnan(value) or math.isnan(anchor) or anchor == 0:
        return math.nan
    return value / anchor


def parse_key_values(block: list[str], prefix: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in block:
        match = re.fullmatch(rf"{re.escape(prefix)}\.([A-Za-z0-9_]+)=(.+)", line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def parse_results(text: str) -> dict[str, object]:
    lines = text.splitlines()
    valid_startup = {
        int(attempt)
        for attempt in re.findall(
            r"^startup_round_valid,attempt=(\d+),valid_index=\d+$", text, re.MULTILINE
        )
    }
    valid_malloc = {
        (int(threads), int(attempt))
        for threads, attempt in re.findall(
            r"^malloc_round_valid,threads=(\d+),attempt=(\d+),valid_index=\d+$",
            text,
            re.MULTILINE,
        )
    }

    startup: dict[str, list[float]] = {variant: [] for variant in VARIANTS}
    for attempt, variant, ns in re.findall(
        r"^startup_sample,attempt=(\d+),variant=(S[1-6]),ns=(\d+),env=.*$",
        text,
        re.MULTILINE,
    ):
        if int(attempt) in valid_startup:
            startup[variant].append(float(ns))

    sizes: dict[str, float] = {}
    for variant, byte_count in re.findall(
        r"^size,variant=(S[1-6]),bytes=(\d+),path=.*$", text, re.MULTILINE
    ):
        sizes[variant] = float(byte_count)

    malloc: dict[tuple[str, int], list[float]] = {
        (variant, threads): [] for variant in VARIANTS for threads in (1, 4)
    }
    memory: dict[str, dict[str, list[float]]] = {
        variant: {key: [] for key in ("Rss", "Pss", "Private_Dirty")}
        for variant in VARIANTS
    }
    threads_metric: dict[str, list[float]] = {variant: [] for variant in VARIANTS}
    invalid_samples: list[str] = []

    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("malloccfg="):
            header = re.fullmatch(
                r"malloccfg=variant=(S[1-6]),threads=(1|4),attempt=(\d+),env=(.*)",
                line,
            )
            block: list[str] = []
            index += 1
            while index < len(lines) and not (
                lines[index].startswith("malloccfg=")
                or lines[index].startswith("sample_env,")
                or lines[index].startswith("frequency.")
                or lines[index].startswith("malloc_round_")
                or lines[index].startswith("### ")
            ):
                block.append(lines[index])
                index += 1
            if header:
                variant, thread_text, attempt_text, _ = header.groups()
                values = parse_key_values(block, "malloc")
                sentinel = block.count("sample_end=OK") == 1
                rc_ok = "probe_rc=0" in block
                complete = all(
                    key in values
                    for key in ("threads", "iters_per_thread", "ns_per_op_mean", "checksum")
                )
                key = (int(thread_text), int(attempt_text))
                if sentinel and rc_ok and complete and key in valid_malloc:
                    try:
                        malloc[(variant, int(thread_text))].append(
                            float(values["ns_per_op_mean"])
                        )
                    except ValueError:
                        invalid_samples.append(
                            f"malloc variant={variant} threads={thread_text} "
                            f"attempt={attempt_text} nonnumeric_ns"
                        )
                elif key in valid_malloc:
                    invalid_samples.append(
                        f"malloc variant={variant} threads={thread_text} attempt={attempt_text}"
                    )
            continue
        if line.startswith("memcfg="):
            header = re.fullmatch(
                r"memcfg=variant=(S[1-6]),rep=(\d+),env=(.*)", line
            )
            block = []
            index += 1
            while index < len(lines) and not (
                lines[index].startswith("memcfg=")
                or lines[index].startswith("sample_env,")
                or lines[index].startswith("### ")
            ):
                block.append(lines[index])
                index += 1
            if header:
                variant = header.group(1)
                sentinel = block.count("sample_end=OK") == 1
                rc_ok = "probe_rc=0" in block
                metrics: dict[str, float] = {}
                for item in block:
                    match = re.fullmatch(
                        r"(Rss|Pss|Private_Dirty):\s+(\d+)\s+kB", item
                    )
                    if match:
                        metrics[match.group(1)] = float(match.group(2))
                if sentinel and rc_ok and len(metrics) == 3:
                    for key, value in metrics.items():
                        memory[variant][key].append(value)
                else:
                    invalid_samples.append(f"mem variant={variant} rep={header.group(2)}")
            continue
        if line.startswith("threadscfg="):
            header = re.fullmatch(
                r"threadscfg=variant=(S[1-6]),rep=(\d+),env=(.*)", line
            )
            block = []
            index += 1
            while index < len(lines) and not (
                lines[index].startswith("threadscfg=")
                or lines[index].startswith("sample_env,")
                or lines[index].startswith("### ")
            ):
                block.append(lines[index])
                index += 1
            if header:
                variant = header.group(1)
                sentinel = block.count("sample_end=OK") == 1
                rc_ok = "probe_rc=0" in block
                vm_size = math.nan
                created = math.nan
                for item in block:
                    size_match = re.fullmatch(r"status\.VmSize:\s+(\d+)\s+kB", item)
                    created_match = re.fullmatch(r"threads\.created=(\d+)", item)
                    if size_match:
                        vm_size = float(size_match.group(1))
                    if created_match:
                        created = float(created_match.group(1))
                if sentinel and rc_ok and created == 200 and not math.isnan(vm_size):
                    threads_metric[variant].append(vm_size)
                else:
                    invalid_samples.append(f"threads variant={variant}")
            continue
        index += 1

    return {
        "startup": startup,
        "sizes": sizes,
        "malloc": malloc,
        "memory": memory,
        "threads": threads_metric,
        "valid_startup": valid_startup,
        "valid_malloc": valid_malloc,
        "invalid_samples": invalid_samples,
    }


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    results_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "results/results-shootout.txt"
    report_path = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "results/report-shootout.md"
    decision_path = root / "results/logs/compiler-decision-shootout.txt"
    s6_status_path = root / "results/logs/shootout-s6-status.txt"
    build_log = root / "results/logs/gbs-build-shootout.log"
    deploy_log = root / "results/logs/deploy-shootout.log"
    for path in (results_path, decision_path, s6_status_path, build_log, deploy_log):
        if not path.is_file():
            raise SystemExit(f"required evidence missing: {path}")

    parsed = parse_results(results_path.read_text(encoding="utf-8", errors="replace"))
    startup = parsed["startup"]
    sizes = parsed["sizes"]
    malloc = parsed["malloc"]
    memory = parsed["memory"]
    thread_values = parsed["threads"]

    completeness_errors: list[str] = []
    for variant in MEASURED_VARIANTS:
        for thread in (1, 4):
            count = len(malloc[(variant, thread)])
            if count < 5:
                completeness_errors.append(
                    f"malloc {variant} t{thread} requires n>=5, got {count}"
                )
        if len(memory[variant]["Pss"]) != 3:
            completeness_errors.append(
                f"memory {variant} requires n=3, got {len(memory[variant]['Pss'])}"
            )
        if len(startup[variant]) != 30:
            completeness_errors.append(
                f"startup {variant} requires n=30, got {len(startup[variant])}"
            )
        if len(thread_values[variant]) != 1:
            completeness_errors.append(
                f"threads {variant} requires n=1, got {len(thread_values[variant])}"
            )
        if variant not in sizes:
            completeness_errors.append(f"size {variant} missing")
    if parsed["invalid_samples"]:
        completeness_errors.append(
            f"INVALID samples present: {len(parsed['invalid_samples'])}"
        )
    if completeness_errors:
        raise SystemExit("sample completeness gate failed: " + "; ".join(completeness_errors))

    malloc_med = {
        (variant, thread): median(malloc[(variant, thread)])
        for variant in VARIANTS
        for thread in (1, 4)
    }
    startup_med = {variant: median(startup[variant]) / 1e6 for variant in VARIANTS}
    memory_med = {
        variant: {key: median(values) for key, values in memory[variant].items()}
        for variant in VARIANTS
    }
    threads_med = {variant: median(thread_values[variant]) for variant in VARIANTS}
    size_kib = {variant: sizes.get(variant, math.nan) / 1024 for variant in VARIANTS}

    output = [
        "# Allocator Shootout 汇率表（WS-A）",
        "",
        "## 状态",
        "",
        "- 结论：**PENDING — 等待 FatTank 数据核验与选型裁决**。",
        "- S1–S4 来自冻结的 `musl-libc-demo-1.0.0-2.armv7l.rpm`，未重编；S5/S6 来自 shootout 增量 RPM。",
        "- S3 与 S4 是同一个二进制；S4 每个样本仅注入 `MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0`。",
        "- S5 已裁决为 [`P1-DEFERRED`](logs/incident-shootout-rpmalloc-runtime-segv.md)，构建产物和诊断证据保留，但不进入测量。",
        "- S6 状态：`BUILT`；未搭建 libc++ 环境。",
        "",
        "## 核心汇率表",
        "",
        "| ID | 构成 | malloc t1 ns/op (×S1) | malloc t4 ns/op (×S1) | Pss kB (ΔS2) | Private_Dirty kB (ΔS2) | threads VmSize kB (×S2) | startup ms | stripped KiB (ΔS2) |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for variant in VARIANTS:
        if variant == "S5":
            output.append(
                "| S5 | musl + rpmalloc — [P1-DEFERRED](logs/incident-shootout-rpmalloc-runtime-segv.md) | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED |"
            )
            continue
        t1 = malloc_med[(variant, 1)]
        t4 = malloc_med[(variant, 4)]
        pss = memory_med[variant]["Pss"]
        dirty = memory_med[variant]["Private_Dirty"]
        vm = threads_med[variant]
        binary = size_kib[variant]
        output.append(
            f"| {variant} | {LABELS[variant]} | {fmt(t1)} ({fmt(ratio(t1, malloc_med[('S1', 1)]), 2)}×) | "
            f"{fmt(t4)} ({fmt(ratio(t4, malloc_med[('S1', 4)]), 2)}×) | "
            f"{fmt(pss, 0)} ({pss - memory_med['S2']['Pss']:+.0f}) | "
            f"{fmt(dirty, 0)} ({dirty - memory_med['S2']['Private_Dirty']:+.0f}) | "
            f"{fmt(vm, 0)} ({fmt(ratio(vm, threads_med['S2']), 2)}×) | "
            f"{fmt(startup_med[variant], 3)} | {fmt(binary, 1)} ({binary - size_kib['S2']:+.1f}) |"
        )

    output.extend(
        [
            "",
            "括号中的 Pss、Private_Dirty 和体积数字均为相对 S2 的有符号增量；表中未做加权评分。",
            "",
            "## 样本完整性",
            "",
            "| ID | malloc t1 n | malloc t4 n | mem n | startup n | threads n |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for variant in VARIANTS:
        if variant == "S5":
            output.append("| S5 | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED |")
            continue
        output.append(
            f"| {variant} | {len(malloc[(variant, 1)])} | {len(malloc[(variant, 4)])} | "
            f"{len(memory[variant]['Pss'])} | {len(startup[variant])} | {len(thread_values[variant])} |"
        )
    output.extend(
        [
            "",
            f"- startup 有效轮：{len(parsed['valid_startup'])}；malloc 有效轮：t1={sum(1 for t, _ in parsed['valid_malloc'] if t == 1)}，t4={sum(1 for t, _ in parsed['valid_malloc'] if t == 4)}。",
            f"- INVALID 样本：{len(parsed['invalid_samples'])}"
            + ("；" + "；".join(parsed["invalid_samples"]) if parsed["invalid_samples"] else "。"),
            "",
            "## 方法与裁决口径",
            "",
            "- malloc 使用 `{1,4}` 线程、每线程 2,000,000 次操作、轮内五方旋转交替；报告全部频率门禁有效样本的 median。",
            "- mem 为单实例 `smaps_rollup` 的 Pss、Private_Dirty、Rss，各 3 次；threads 为创建 200 线程后的 VmSize；startup 为五方交替 30 个有效轮。",
            "- 处方判据冻结为：在 t4 追回达到目标的候选中选择 Private_Dirty 增量最小者，体积仅作次级 tiebreak。目标值和最终候选裁决留给 FatTank。",
            "- 不做加权评分，也不宣布“冠军”。",
            "",
            "## 附加矩阵",
            "",
            "| ID | Rss median kB | Pss n | S4 相对 S3 t4 |",
            "|---|---:|---:|---:|",
        ]
    )
    s4_concession = ratio(malloc_med[("S4", 4)], malloc_med[("S3", 4)])
    for variant in VARIANTS:
        if variant == "S5":
            output.append("| S5 | P1-DEFERRED | P1-DEFERRED | — |")
            continue
        concession = f"{fmt(s4_concession, 2)}×" if variant == "S4" else "—"
        output.append(
            f"| {variant} | {fmt(memory_med[variant]['Rss'], 0)} | {len(memory[variant]['Pss'])} | {concession} |"
        )

    output.extend(
        [
            "",
            "## Caveats",
            "",
            "- micro 是固定大小类 churn 画像，不能外推为所有真实应用分配行为；汇率表用于处方筛选，不替代候选包真实负载验证。",
            f"- S4 调参相对 S3 的 t4 性能让渡倍率为 `{fmt(s4_concession, 3)}×`；其回收/提交策略差异也应结合 Private_Dirty 阅读。",
            "- S6 本轮没有触发 P1 降级；若后续平台复建触发摩擦预算，其列应标 `P1-DEFERRED` 并引用对应 incident，而不是用缺失样本参与排名。",
            "- S5 已按 FatTank 裁决降为 `P1-DEFERRED`；本报告不以缺失样本参与任何倍率或选型比较。复活条件见事故归档终章。",
            "- 单板、单会话和有限样本量会保留一定调度噪声；原始温度、频率、顺序、环境变量、哨兵与返回码均留在数据文件中。",
            "",
            "## Evidence",
            "",
            f"- `results/results-shootout.txt` SHA-256: `{sha256(results_path)}`",
            f"- `results/logs/gbs-build-shootout.log` SHA-256: `{sha256(build_log)}`",
            f"- `results/logs/deploy-shootout.log` SHA-256: `{sha256(deploy_log)}`",
            f"- `results/logs/compiler-decision-shootout.txt` SHA-256: `{sha256(decision_path)}`",
            f"- `results/logs/shootout-s6-status.txt` SHA-256: `{sha256(s6_status_path)}`",
        ]
    )
    report_path.write_text("\n".join(output) + "\n", encoding="utf-8")
    print(f"REPORT_SHOOTOUT_PASS report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
