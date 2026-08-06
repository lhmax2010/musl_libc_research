#!/usr/bin/env python3
"""Generate results/report.md from the immutable board results.txt."""

from __future__ import annotations

import math
import re
import statistics
import sys
from pathlib import Path


VARIANTS = ("glibc-dyn", "musl-static", "musl-dyn")


def median(values: list[float]) -> float:
    return statistics.median(values) if values else math.nan


def fmt_number(value: float, digits: int = 1) -> str:
    return "NOT_RUN" if math.isnan(value) else f"{value:.{digits}f}"


def parse_decisions(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


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


def main(results_path: Path, decision_path: Path) -> int:
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

    malloc: dict[tuple[str, int], list[float]] = {}
    current_variant: str | None = None
    current_threads: int | None = None
    for line in lines:
        config = re.match(
            r"malloccfg=(glibc-dyn|musl-static|musl-dyn),rep=\d+,threads=(\d+)$",
            line,
        )
        if config:
            current_variant = config.group(1)
            current_threads = int(config.group(2))
            continue
        value = re.match(r"malloc\.ns_per_op_mean=([0-9.]+)$", line)
        if value and current_variant is not None and current_threads is not None:
            malloc.setdefault((current_variant, current_threads), []).append(
                float(value.group(1))
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
            "## 2. malloc churn（ns/op，各轮中位数）",
            "",
            "| 线程 | glibc-dyn | musl-static | musl-dyn | static/glibc | static/dyn |",
            "|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for threads in (1, 4):
        values = {variant: median(malloc.get((variant, threads), [])) for variant in VARIANTS}
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
            f"| {threads} | {fmt_number(values['glibc-dyn'])} | "
            f"{fmt_number(values['musl-static'])} | {fmt_number(values['musl-dyn'])} | "
            f"{fmt_number(static_glibc, 2)}x | {fmt_number(static_dynamic, 2)}x |"
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
            "",
            f"原始数据：`{results_path}`；编译器决策：`{decision_path}`。",
        ]
    )
    print("\n".join(output))
    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print("usage: gen_report.py RESULTS_TXT [COMPILER_DECISION]", file=sys.stderr)
        raise SystemExit(2)
    input_path = Path(sys.argv[1])
    default_decision = input_path.parent / "logs" / "compiler-decision.txt"
    raise SystemExit(main(input_path, Path(sys.argv[2]) if len(sys.argv) == 3 else default_decision))
