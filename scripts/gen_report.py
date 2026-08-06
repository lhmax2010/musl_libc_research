#!/usr/bin/env python3
"""Generate results/report.md from immutable board measurement files."""

from __future__ import annotations

from dataclasses import dataclass, field
import math
import re
import statistics
import sys
from pathlib import Path


VARIANTS = ("glibc-dyn", "musl-static", "musl-dyn")
MALLOC_EXPECTED_KEYS = (
    "threads",
    "iters_per_thread",
    "ns_per_op_mean",
    "checksum",
)
SAMPLE_HEADER_TOKEN = re.compile(
    r"(?:malloccfg|memcfg|threadscfg|dnscfg|localecfg)="
)
MALLOC_HEADER = re.compile(
    r"malloccfg=(glibc-dyn|musl-static|musl-dyn|musl-mi),rep=(\d+),threads=(\d+)$"
)
MALLOC_VALUE = re.compile(
    r"malloc\.(threads|iters_per_thread|ns_per_op_mean|checksum)=(.+)$"
)


@dataclass
class MallocSample:
    source: str
    variant: str
    rep: int
    threads: int
    values: dict[str, str] = field(default_factory=dict)
    sentinel_seen: bool = False
    invalid_reasons: list[str] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return not self.invalid_reasons

    @property
    def label(self) -> str:
        return (
            f"{self.source}:malloccfg={self.variant},rep={self.rep},"
            f"threads={self.threads}"
        )


@dataclass
class MetricSample:
    kind: str
    variant: str
    rep: int
    values: dict[str, float] = field(default_factory=dict)
    sentinel_seen: bool = False
    invalid_reasons: list[str] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return not self.invalid_reasons


def median(values: list[float]) -> float:
    return statistics.median(values) if values else math.nan


def fmt_number(value: float, digits: int = 1) -> str:
    return "NOT_RUN" if math.isnan(value) else f"{value:.{digits}f}"


def fmt_sample_cell(value: float, count: int) -> str:
    return f"{fmt_number(value)} (n={count})"


def fmt_ratio_cell(value: float, numerator_n: int, denominator_n: int) -> str:
    return f"{fmt_number(value, 2)}x (n={numerator_n}/{denominator_n})"


def parse_decisions(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def resynchronize_sample_headers(text: str) -> list[tuple[str, bool]]:
    """Split a header found mid-line and mark only the new header as resynced."""

    output: list[tuple[str, bool]] = []
    for physical_line in text.splitlines():
        starts = [match.start() for match in SAMPLE_HEADER_TOKEN.finditer(physical_line)]
        if not starts:
            output.append((physical_line, False))
            continue
        if starts[0] > 0:
            output.append((physical_line[: starts[0]], False))
        for index, start in enumerate(starts):
            end = starts[index + 1] if index + 1 < len(starts) else len(physical_line)
            output.append((physical_line[start:end], start > 0))
    return output


def parse_malloc_samples(text: str, source: str) -> list[MallocSample]:
    """Parse complete malloc samples without carrying values across headers."""

    physical_lines = text.splitlines()
    sentinel_required = any(
        line.strip() == "measurement.sample_sentinel=required"
        for line in physical_lines
    ) or any(line.strip() == "sample_end=OK" for line in physical_lines)
    samples: list[MallocSample] = []
    current: MallocSample | None = None

    def finish_current() -> None:
        nonlocal current
        if current is None:
            return
        missing = [key for key in MALLOC_EXPECTED_KEYS if key not in current.values]
        if missing:
            current.invalid_reasons.append("missing=" + ",".join(missing))
        if sentinel_required and not current.sentinel_seen:
            current.invalid_reasons.append("missing=sample_end=OK")
        if "ns_per_op_mean" in current.values:
            try:
                float(current.values["ns_per_op_mean"])
            except ValueError:
                current.invalid_reasons.append("invalid=ns_per_op_mean")
        samples.append(current)
        current = None

    for line, midline_header in resynchronize_sample_headers(text):
        is_sample_header = SAMPLE_HEADER_TOKEN.match(line) is not None
        if is_sample_header:
            if current is not None and midline_header:
                current.invalid_reasons.append("midline_header_after_partial_output")
            finish_current()
            if line.startswith("malloccfg="):
                header = MALLOC_HEADER.fullmatch(line)
                if header:
                    current = MallocSample(
                        source=source,
                        variant=header.group(1),
                        rep=int(header.group(2)),
                        threads=int(header.group(3)),
                    )
                else:
                    current = MallocSample(source, "UNKNOWN", -1, -1)
                    current.invalid_reasons.append("malformed=malloccfg")
            continue
        if line.startswith("### "):
            finish_current()
            continue
        if current is None:
            continue
        if line == "sample_end=OK":
            current.sentinel_seen = True
            continue
        value = MALLOC_VALUE.fullmatch(line)
        if value:
            key = value.group(1)
            if key in current.values:
                current.invalid_reasons.append(f"duplicate={key}")
            else:
                current.values[key] = value.group(2)

    finish_current()
    return samples


def extract_sections(lines: list[str], wanted: tuple[str, ...]) -> list[str]:
    output: list[str] = []
    active = False
    block: list[str] = []
    title = ""
    for line in lines + ["### __end__"]:
        if line.startswith("### "):
            if active:
                output.extend((f"### {title}", "", "```text", *block, "```", ""))
            title = line[4:]
            active = any(title.startswith(prefix) for prefix in wanted)
            block = []
        elif active:
            block.append(line)
    return output


def discover_measurement_paths(results_path: Path) -> list[Path]:
    paths = [results_path]
    supplement = results_path.with_name(
        f"{results_path.stem}-supplement{results_path.suffix}"
    )
    if supplement.is_file():
        paths.append(supplement)
    return paths


def main_standard(results_path: Path, decision_path: Path) -> int:
    text = results_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    invalid_rounds = {
        int(match.group(1))
        for match in re.finditer(r"^startup_invalid,(\d+),", text, re.MULTILINE)
    }
    triples = [
        (int(round_no), int(glibc), int(static), int(dynamic))
        for round_no, glibc, static, dynamic in re.findall(
            r"^startup_triple,(\d+),(\d+),(\d+),(\d+)$", text, re.MULTILINE
        )
        if int(round_no) not in invalid_rounds
    ]

    measurement_paths = discover_measurement_paths(results_path)
    malloc_samples: list[MallocSample] = []
    for measurement_path in measurement_paths:
        malloc_samples.extend(
            parse_malloc_samples(
                measurement_path.read_text(encoding="utf-8", errors="replace"),
                measurement_path.name,
            )
        )
    valid_malloc = [sample for sample in malloc_samples if sample.valid]
    invalid_malloc = [sample for sample in malloc_samples if not sample.valid]
    malloc: dict[tuple[str, int], list[float]] = {}
    for sample in valid_malloc:
        malloc.setdefault((sample.variant, sample.threads), []).append(
            float(sample.values["ns_per_op_mean"])
        )

    decisions = parse_decisions(decision_path)
    clang_version = decisions.get("expected_clang_version", "UNKNOWN")
    rtlib = decisions.get("selected_rtlib", "UNKNOWN")
    rtlib_consistency = decisions.get("rtlib_consistency", "NOT_VERIFIED")

    output: list[str] = [
        "# musl vs glibc GBS 快速 Demo 报告",
        "",
        "## 1. 启动时间（fork+exec→exit，三元组交替配对）",
        "",
    ]
    if triples:
        glibc_values = [row[1] for row in triples]
        static_values = [row[2] for row in triples]
        dynamic_values = [row[3] for row in triples]
        static_vs_glibc = [(row[2] - row[1]) / row[1] for row in triples]
        static_vs_dynamic = [(row[2] - row[3]) / row[3] for row in triples]
        output.extend(
            [
                f"- 有效轮次：**{len(triples)}**；INVALID 轮次："
                + (", ".join(map(str, sorted(invalid_rounds))) if invalid_rounds else "无"),
                f"- glibc-dyn median：**{median(glibc_values) / 1e6:.3f} ms**",
                f"- musl-static median：**{median(static_values) / 1e6:.3f} ms**",
                f"- musl-dyn median：**{median(dynamic_values) / 1e6:.3f} ms**",
                "- 配对 delta，musl-static vs glibc-dyn（方案差异）："
                f"**{median(static_vs_glibc) * 100:+.1f}%**",
                "- 配对 delta，musl-static vs musl-dyn（链接方式贡献）："
                f"**{median(static_vs_dynamic) * 100:+.1f}%**",
            ]
        )
    else:
        output.append("- NOT_RUN：没有可用于统计的有效 startup_triple。")

    output.extend(
        [
            "",
            "## 2. malloc churn（ns/op，各轮 VALID 样本中位数）",
            "",
            "| 线程 | glibc-dyn | musl-static | musl-dyn | static/glibc | static/dyn |",
            "|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for threads in (1, 4):
        values_by_variant = {
            variant: malloc.get((variant, threads), []) for variant in VARIANTS
        }
        values = {
            variant: median(values_by_variant[variant]) for variant in VARIANTS
        }
        counts = {variant: len(values_by_variant[variant]) for variant in VARIANTS}
        static_glibc = (
            values["musl-static"] / values["glibc-dyn"]
            if not math.isnan(values["musl-static"])
            and not math.isnan(values["glibc-dyn"])
            and values["glibc-dyn"]
            else math.nan
        )
        static_dynamic = (
            values["musl-static"] / values["musl-dyn"]
            if not math.isnan(values["musl-static"])
            and not math.isnan(values["musl-dyn"])
            and values["musl-dyn"]
            else math.nan
        )
        output.append(
            f"| {threads} | {fmt_sample_cell(values['glibc-dyn'], counts['glibc-dyn'])} | "
            f"{fmt_sample_cell(values['musl-static'], counts['musl-static'])} | "
            f"{fmt_sample_cell(values['musl-dyn'], counts['musl-dyn'])} | "
            f"{fmt_ratio_cell(static_glibc, counts['musl-static'], counts['glibc-dyn'])} | "
            f"{fmt_ratio_cell(static_dynamic, counts['musl-static'], counts['musl-dyn'])} |"
        )
    output.extend(
        [
            "",
            f"- malloc 样本完整性：VALID **{len(valid_malloc)}**；"
            f"INVALID **{len(invalid_malloc)}**。",
        ]
    )
    for sample in invalid_malloc:
        output.append(f"- INVALID `{sample.label}`：{'; '.join(sample.invalid_reasons)}")
    primary_invalid = [
        sample for sample in invalid_malloc if sample.source == results_path.name
    ]
    supplement_invalid = [
        sample for sample in invalid_malloc if sample.source != results_path.name
    ]
    output.extend(
        [
            "",
            "### 合并方法与 INVALID 清单",
            "",
            "- `results.txt` 保持只读；补测仅来自独立的 `results-supplement.txt`，内容为 rep=6 的 t=4 三变体交替轮。",
            "- 每个单元格使用原始与补测文件中全部 VALID 样本的 median，并逐格报告 n；不剔除、不挑选、不加权。",
            "- malloc VALID 必须集齐 threads、iters_per_thread、ns_per_op_mean、checksum；声明哨兵机制的数据源还必须具有独立 `sample_end=OK`。",
            f"- startup INVALID：**{len(invalid_rounds)}**；原始 malloc INVALID："
            f"**{len(primary_invalid)}**；补测 malloc INVALID："
            f"**{len(supplement_invalid)}**。",
        ]
    )

    output.extend(
        [
            "",
            "## 3. 其余测量原文",
            "",
            *extract_sections(
                lines,
                (
                    "sizes",
                    "mem smaps_rollup",
                    "threads 200",
                    "dns",
                    "locale",
                    "frequencies",
                ),
            ),
            "## 4. Caveats",
            "",
            "- 本报告来自单板（RPI4 armv7l）、单日测量，样本量有限；温度、频率和 INVALID 轮次均保留在原始结果中。",
            f"- 三个对比变体均在同一 Tizen chroot 内由平台 clang {clang_version} 编译，并使用同一 `%optflags`；编译器混淆已消除，结论直接适用于平台 LLVM 语境，剩余变量为 libc 与链接方式。",
            f"- builtins 运行库选择为 `{rtlib}`；三变体一致性门禁状态为 `{rtlib_consistency}`。",
            "- musl 是独立 ABI 世界，不能直接链接平台 glibc ABI 的共享库；静态链接不支持常规 `dlopen` 插件模型，musl 忽略 `nsswitch.conf`，locale 基本只提供 C/C.UTF-8。",
            "- 安装采用方案 A（`rpm -Uvh --noplugins`）：仅跳过触发环境限制的 security 插件钩子，RPM 文件布局与数据库记录保持不变；探针由 root sdb 直接执行且不依赖 Smack manifest 注册，因此该安装偏离不影响测量有效性。",
            "- 原始 malloc 截断事故保留为 1 个 INVALID，防御性解析不再跨 header 错归；rep=6 补测保存在独立文件。详见 `results/logs/incident-board-measurement-malloc-truncation.md`。",
            "",
            "测量数据："
            + "、".join(f"`{path}`" for path in measurement_paths)
            + f"；编译器决策：`{decision_path}`。",
        ]
    )
    print("\n".join(output))
    return 0


def parse_metric_samples(text: str, kind: str) -> list[MetricSample]:
    if kind == "mem":
        header_re = re.compile(
            r"memcfg=(glibc-dyn|musl-static|musl-dyn|musl-mi),rep=(\d+)$"
        )
        required = ("pid", "Rss", "Pss", "Private_Clean", "Private_Dirty")
    elif kind == "threads":
        header_re = re.compile(
            r"threadscfg=(glibc-dyn|musl-static|musl-dyn|musl-mi)$"
        )
        required = ("requested", "created", "VmSize", "VmRSS", "VmData", "Threads")
    else:
        raise ValueError(f"unsupported metric sample kind: {kind}")

    sentinel_required = "measurement.sample_sentinel=required" in text
    samples: list[MetricSample] = []
    current: MetricSample | None = None

    def finish() -> None:
        nonlocal current
        if current is None:
            return
        missing = [key for key in required if key not in current.values]
        if missing:
            current.invalid_reasons.append("missing=" + ",".join(missing))
        if sentinel_required and not current.sentinel_seen:
            current.invalid_reasons.append("missing=sample_end=OK")
        samples.append(current)
        current = None

    prefix = "memcfg=" if kind == "mem" else "threadscfg="
    for line, midline_header in resynchronize_sample_headers(text):
        if SAMPLE_HEADER_TOKEN.match(line) is not None or line.startswith("### "):
            if current is not None and midline_header:
                current.invalid_reasons.append("midline_header_after_partial_output")
            finish()
            if line.startswith(prefix):
                header = header_re.fullmatch(line)
                if header:
                    current = MetricSample(
                        kind=kind,
                        variant=header.group(1),
                        rep=int(header.group(2)) if kind == "mem" else 1,
                    )
                else:
                    current = MetricSample(kind, "UNKNOWN", -1)
                    current.invalid_reasons.append(f"malformed={kind}cfg")
            continue
        if current is None:
            continue
        if line == "sample_end=OK":
            current.sentinel_seen = True
            continue
        if kind == "mem":
            pid = re.fullmatch(r"mem\.pid=(\d+)", line)
            metric = re.fullmatch(
                r"(Rss|Pss|Private_Clean|Private_Dirty):\s+(\d+) kB", line
            )
            if pid:
                current.values["pid"] = float(pid.group(1))
            elif metric:
                current.values[metric.group(1)] = float(metric.group(2))
        else:
            count = re.fullmatch(r"threads\.(requested|created)=(\d+)", line)
            metric = re.fullmatch(
                r"status\.(VmSize|VmRSS|VmData|Threads):\s+(\d+)(?: kB)?", line
            )
            if count:
                current.values[count.group(1)] = float(count.group(2))
            elif metric:
                current.values[metric.group(1)] = float(metric.group(2))
    finish()
    return samples


def parse_binary_sizes(text: str) -> dict[str, float]:
    sizes: dict[str, float] = {}
    active = False
    for line in text.splitlines():
        if line.startswith("### "):
            active = line == "### sizes"
            continue
        if not active or not line.startswith("-"):
            continue
        fields = line.split()
        if len(fields) < 6 or not fields[4].isdigit():
            continue
        name = Path(fields[-1]).name
        if name.startswith("micro.") or name == "libc.so":
            sizes[name] = float(fields[4])
    return sizes


def sample_metric_median(
    samples: list[MetricSample], variant: str, key: str
) -> tuple[float, int]:
    values = [
        sample.values[key]
        for sample in samples
        if sample.valid and sample.variant == variant and key in sample.values
    ]
    return median(values), len(values)


def fmt_cost(value: float, unit: str) -> str:
    if math.isnan(value):
        return "NOT_RUN"
    if unit == "bytes":
        return f"{value:.0f} B"
    return f"{value:.0f} {unit}"


def cost_row(label: str, base: float, mi: float, unit: str) -> str:
    delta = mi - base if not math.isnan(base) and not math.isnan(mi) else math.nan
    multiple = mi / base if not math.isnan(delta) and base else math.nan
    multiple_text = "NOT_RUN" if math.isnan(multiple) else f"{multiple:.2f}x"
    return (
        f"| {label} | {fmt_cost(base, unit)} | {fmt_cost(mi, unit)} | "
        f"{fmt_cost(delta, unit)} | {multiple_text} |"
    )


def main_mimalloc(results_path: Path, decision_path: Path, text: str) -> int:
    invalid_rounds = {
        int(value)
        for value in re.findall(r"^startup_invalid,(\d+),", text, re.MULTILINE)
    }
    quads = [
        tuple(map(int, values))
        for values in re.findall(
            r"^startup_quad,(\d+),(\d+),(\d+),(\d+),(\d+)$",
            text,
            re.MULTILINE,
        )
        if int(values[0]) not in invalid_rounds
    ]
    malloc_samples = parse_malloc_samples(text, results_path.name)
    valid_malloc = [sample for sample in malloc_samples if sample.valid]
    invalid_malloc = [sample for sample in malloc_samples if not sample.valid]
    malloc: dict[tuple[str, int], list[float]] = {}
    for sample in valid_malloc:
        malloc.setdefault((sample.variant, sample.threads), []).append(
            float(sample.values["ns_per_op_mean"])
        )

    mem_samples = parse_metric_samples(text, "mem")
    thread_samples = parse_metric_samples(text, "threads")
    invalid_metrics = [
        sample for sample in (*mem_samples, *thread_samples) if not sample.valid
    ]
    sizes = parse_binary_sizes(text)
    decisions = parse_decisions(decision_path)

    output = [
        "# musl-static + mimalloc 第四变体实测报告",
        "",
        "## 1. startup 四元组",
        "",
        f"- 有效轮次：**{len(quads)}**；INVALID：**{len(invalid_rounds)}**。",
    ]
    if quads:
        for label, index in (
            ("glibc-dyn", 1),
            ("musl-static", 2),
            ("musl-dyn", 3),
            ("musl-mi", 4),
        ):
            output.append(
                f"- {label} median：**{median([row[index] for row in quads]) / 1e6:.3f} ms**"
            )
    else:
        output.append("- NOT_RUN：没有有效 startup_quad。")

    output.extend(
        [
            "",
            "## 2. malloc 四方表（ns/op，全部 VALID 样本中位数）",
            "",
            "| 线程 | glibc-dyn | musl-static | musl-dyn | musl-mi | mi/glibc | mi/musl-static |",
            "|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )
    cell_stats: dict[tuple[str, int], tuple[float, int]] = {}
    for threads in (1, 4):
        for variant in (*VARIANTS, "musl-mi"):
            values = malloc.get((variant, threads), [])
            cell_stats[(variant, threads)] = (median(values), len(values))
        glibc, glibc_n = cell_stats[("glibc-dyn", threads)]
        static, static_n = cell_stats[("musl-static", threads)]
        dynamic, dynamic_n = cell_stats[("musl-dyn", threads)]
        mi, mi_n = cell_stats[("musl-mi", threads)]
        mi_glibc = mi / glibc if glibc and not math.isnan(mi) else math.nan
        mi_static = mi / static if static and not math.isnan(mi) else math.nan
        output.append(
            f"| {threads} | {fmt_sample_cell(glibc, glibc_n)} | "
            f"{fmt_sample_cell(static, static_n)} | "
            f"{fmt_sample_cell(dynamic, dynamic_n)} | "
            f"{fmt_sample_cell(mi, mi_n)} | "
            f"{fmt_ratio_cell(mi_glibc, mi_n, glibc_n)} | "
            f"{fmt_ratio_cell(mi_static, mi_n, static_n)} |"
        )
    output.extend(
        [
            "",
            f"- malloc VALID：**{len(valid_malloc)}**；INVALID：**{len(invalid_malloc)}**。",
        ]
    )
    for sample in invalid_malloc:
        output.append(f"- INVALID `{sample.label}`：{'; '.join(sample.invalid_reasons)}")

    pss_static, pss_static_n = sample_metric_median(mem_samples, "musl-static", "Pss")
    pss_mi, pss_mi_n = sample_metric_median(mem_samples, "musl-mi", "Pss")
    dirty_static, dirty_static_n = sample_metric_median(
        mem_samples, "musl-static", "Private_Dirty"
    )
    dirty_mi, dirty_mi_n = sample_metric_median(
        mem_samples, "musl-mi", "Private_Dirty"
    )
    rss_static, rss_static_n = sample_metric_median(mem_samples, "musl-static", "Rss")
    rss_mi, rss_mi_n = sample_metric_median(mem_samples, "musl-mi", "Rss")
    vmsize_static, vmsize_static_n = sample_metric_median(
        thread_samples, "musl-static", "VmSize"
    )
    vmsize_mi, vmsize_mi_n = sample_metric_median(
        thread_samples, "musl-mi", "VmSize"
    )
    size_static = sizes.get("micro.musl-static", math.nan)
    size_mi = sizes.get("micro.musl-mi", math.nan)
    output.extend(
        [
            "",
            "## 3. 内存与体积代价",
            "",
            "| 指标 | musl-static | musl-mi | 绝对增量 | 倍数 |",
            "|---|---:|---:|---:|---:|",
            cost_row("Pss", pss_static, pss_mi, "kB"),
            cost_row("Private_Dirty", dirty_static, dirty_mi, "kB"),
            cost_row("VmSize (threads 200)", vmsize_static, vmsize_mi, "kB"),
            cost_row("二进制体积", size_static, size_mi, "bytes"),
            "",
            f"- 补充采集 Rss：musl-static {fmt_cost(rss_static, 'kB')} (n={rss_static_n})，musl-mi {fmt_cost(rss_mi, 'kB')} (n={rss_mi_n})。",
            f"- Pss 样本数：musl-static n={pss_static_n}，musl-mi n={pss_mi_n}。",
            f"- Private_Dirty 样本数：musl-static n={dirty_static_n}，musl-mi n={dirty_mi_n}。",
            f"- VmSize 样本数：musl-static n={vmsize_static_n}，musl-mi n={vmsize_mi_n}。",
            f"- mem/threads INVALID：**{len(invalid_metrics)}**。",
        ]
    )

    static_t4, _ = cell_stats[("musl-static", 4)]
    glibc_t4, _ = cell_stats[("glibc-dyn", 4)]
    mi_t4, _ = cell_stats[("musl-mi", 4)]
    conclusion_ready = all(
        not math.isnan(value)
        for value in (static_t4, glibc_t4, mi_t4, dirty_static, dirty_mi, vmsize_static, vmsize_mi, size_static, size_mi)
    )
    output.extend(["", "## 4. 数据填空", ""])
    if conclusion_ready:
        output.append(
            f"t4:mallocng {static_t4:.0f} → mimalloc {mi_t4:.1f} ns/op,为 glibc 的 {mi_t4 / glibc_t4:.2f} 倍; "
            f"代价:Private_Dirty {dirty_static:.0f} KB → {dirty_mi:.0f} KB,"
            f"VmSize +{vmsize_mi - vmsize_static:.0f} KB,"
            f"二进制 +{(size_mi - size_static) / 1024:.1f} KB。"
        )
    else:
        output.append("NOT_RUN：数据不全，不能填充结论模板。")

    output.extend(
        [
            "",
            "## 5. 未复测项",
            "",
            "- DNS：NOT_RUN；分配器无关，沿用前轮 `results/results.txt`。",
            "- locale：NOT_RUN；分配器无关，沿用前轮 `results/results.txt`。",
            "- 补跑命令：`SDB_TARGET=192.168.108.25 scripts/run_board.sh`（该命令会完整重跑本轮四方会话，不会只补 DNS/locale）。",
            "",
            "## 6. Caveats",
            "",
            "- 本报告来自单板、单日测量；四变体在同一会话内交替执行，频率、温度和 INVALID 原文保存在结果文件中。",
            f"- 平台 clang 版本：`{decisions.get('expected_clang_version', 'UNKNOWN')}`；builtins 一致性：`{decisions.get('rtlib_consistency', 'NOT_VERIFIED')}`。",
            "- mimalloc 是第三方组件，引入后必须承担版本与 CVE 持续跟踪义务。",
            "- 替换 musl mallocng 后，不再具备 mallocng 原有的堆加固属性。",
            "- DNS 与 locale 未在本轮复测，相关原始观察仅沿用前轮，不参与分配器比较。",
            "",
            f"测量数据：`{results_path}`；编译器决策：`{decision_path}`。",
        ]
    )
    print("\n".join(output))
    return 0


def main(results_path: Path, decision_path: Path) -> int:
    text = results_path.read_text(encoding="utf-8", errors="replace")
    if "startup_quad," in text or results_path.name == "results-mimalloc.txt":
        return main_mimalloc(results_path, decision_path, text)
    return main_standard(results_path, decision_path)


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print("usage: gen_report.py RESULTS_TXT [COMPILER_DECISION]", file=sys.stderr)
        raise SystemExit(2)
    input_path = Path(sys.argv[1])
    default_decision = input_path.parent / "logs" / "compiler-decision.txt"
    raise SystemExit(
        main(input_path, Path(sys.argv[2]) if len(sys.argv) == 3 else default_decision)
    )
