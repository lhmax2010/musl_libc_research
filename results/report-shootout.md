# Allocator Shootout 汇率表（WS-A）

## 状态

- FatTank 数据核验通过；本报告结论已冻结。
- **缺省分配器维持 S2 musl mallocng。**
- **allowlist 处方定为 S3 mimalloc 默认配置。** S3 是 t4 性能追回达标者中的唯一候选；相对 S2 的 Private_Dirty `+16 kB` 与 stripped 体积 `+110.0 KiB` 为已接受代价。
- **S4 从处方矩阵除名。** 它没有达到 t4 追回目标，且在本画像中相对 S3 未换得 Pss、Private_Dirty 或体积收益；该结论只约束本次固定大小类 churn 画像，不否认 purge/eager-commit 调参在长驻、回收敏感真实负载中重新验证的可能性。
- S1–S4 来自冻结的 `musl-libc-demo-1.0.0-2.armv7l.rpm`，未重编；S5/S6 来自 shootout 增量 RPM。
- S3 与 S4 是同一个二进制；S4 每个样本仅注入 `MIMALLOC_PURGE_DELAY=0 MIMALLOC_ARENA_EAGER_COMMIT=0`。
- S5 已裁决为 [`P1-DEFERRED`](logs/incident-shootout-rpmalloc-runtime-segv.md)，构建产物和诊断证据保留，但不进入测量。
- S6 状态：`BUILT`；未搭建 libc++ 环境；[构建配置审计](logs/scudo-build-config-audit.md)确认有效 `-O2` release-style 构建，无需补测。

## 核心汇率表

| ID | 构成 | malloc t1 ns/op (×S1) | malloc t4 ns/op (×S1) | Pss kB (ΔS2) | Private_Dirty kB (ΔS2) | threads VmSize kB (×S2) | startup ms | stripped KiB (ΔS2) |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| S1 | glibc-dyn | 166.7 (1.00×) | 194.2 (1.00×) | 101 (+49) | 76 (+68) | 1641112 (57.84×) | 2.350 | 16.0 (-413.6) |
| S2 | musl-static (mallocng) | 306.7 (1.84×) | 995.1 (5.12×) | 52 (+0) | 8 (+0) | 28372 (1.00×) | 0.972 | 429.6 (+0.0) |
| S3 | musl + mimalloc default | 80.7 (0.48×) | 157.7 (0.81×) | 112 (+60) | 24 (+16) | 159552 (5.62×) | 1.216 | 539.6 (+110.0) |
| S4 | musl + mimalloc tuned | 199.4 (1.20×) | 331.6 (1.71×) | 112 (+60) | 24 (+16) | 159552 (5.62×) | 1.209 | 539.6 (+110.0) |
| S5 | musl + rpmalloc — [P1-DEFERRED](logs/incident-shootout-rpmalloc-runtime-segv.md) | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED |
| S6 | musl + Scudo standalone — 实测即此；armv7/musl 组合下不适用于热路径，保留为安全敏感低分配组件的加固选项（[审计](logs/scudo-build-config-audit.md)） | 1733.9 (10.40×) | 4380.4 (22.56×) | 72 (+20) | 28 (+20) | 30768 (1.08×) | 1.066 | 501.6 (+72.0) |

括号中的 Pss、Private_Dirty 和体积数字均为相对 S2 的有符号增量；表中未做加权评分。

## 样本完整性

| ID | malloc t1 n | malloc t4 n | mem n | startup n | threads n |
|---|---:|---:|---:|---:|---:|
| S1 | 5 | 5 | 3 | 30 | 1 |
| S2 | 5 | 5 | 3 | 30 | 1 |
| S3 | 5 | 5 | 3 | 30 | 1 |
| S4 | 5 | 5 | 3 | 30 | 1 |
| S5 | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED | P1-DEFERRED |
| S6 | 5 | 5 | 3 | 30 | 1 |

- startup 有效轮：30；malloc 有效轮：t1=5，t4=5。
- INVALID 样本：0。

## 方法与裁决口径

- malloc 使用 `{1,4}` 线程、每线程 2,000,000 次操作、轮内五方旋转交替；报告全部频率门禁有效样本的 median。
- mem 为单实例 `smaps_rollup` 的 Pss、Private_Dirty、Rss，各 3 次；threads 为创建 200 线程后的 VmSize；startup 为五方交替 30 个有效轮。
- 处方判据冻结为：在 t4 追回达到目标的候选中选择 Private_Dirty 增量最小者，体积仅作次级 tiebreak；FatTank 已完成目标判定与最终裁决。
- FatTank 依冻结判据裁决：S2 为缺省；S3 是 t4 追回达标的唯一候选，进入 allowlist；不做加权评分。

## 附加矩阵

| ID | Rss median kB | Pss n | S4 相对 S3 t4 |
|---|---:|---:|---:|
| S1 | 532 | 3 | — |
| S2 | 52 | 3 | — |
| S3 | 120 | 3 | — |
| S4 | 120 | 3 | 2.10× |
| S5 | P1-DEFERRED | P1-DEFERRED | — |
| S6 | 72 | 3 | — |

## Caveats

- micro 是固定大小类 churn 画像，不能外推为所有真实应用分配行为；汇率表用于处方筛选，不替代候选包真实负载验证。
- S4 调参相对 S3 的 t4 性能让渡倍率为 `2.103×`；其回收/提交策略差异也应结合 Private_Dirty 阅读。
- S4 已从处方矩阵除名：它在本画像中未达到 t4 追回目标，也未比同二进制的 S3 降低 Pss、Private_Dirty 或体积。此除名仅适用于当前画像；真实长驻且回收敏感负载可另案复验运行期调参。
- S6 本轮没有触发 P1 降级；若后续平台复建触发摩擦预算，其列应标 `P1-DEFERRED` 并引用对应 incident，而不是用缺失样本参与排名。
- S5 已按 FatTank 裁决降为 `P1-DEFERRED`；本报告不以缺失样本参与任何倍率或选型比较。复活条件见事故归档终章。
- 单板、单会话和有限样本量会保留一定调度噪声；原始温度、频率、顺序、环境变量、哨兵与返回码均留在数据文件中。

## Evidence

- `results/results-shootout.txt` SHA-256: `d89fd6146b15b5e0e7d2ea5a1e90cff89ff880d40cb2debec50df4426755d343`
- `results/logs/gbs-build-shootout.log` SHA-256: `bc5e20a1e05db7e0e224c7cdf5c50182079501b2fc1e871aa012d0c84e7a2bb1`
- `results/logs/deploy-shootout.log` SHA-256: `4ce8f07d5570e70e168248b8c601c31dccf5ae521fad3f2715a29675a0020271`
- `results/logs/sdb-remote-rc-selftest.log` SHA-256: `f18e540fad9d64b88d963e3661c4249510b61e2e135c0ba162ef21046c1fff37`
- `results/logs/compiler-decision-shootout.txt` SHA-256: `5615491449f553738851efecf3a01b19e0edece872b81917bb3e0df9e4789b8c`
- `results/logs/shootout-s6-status.txt` SHA-256: `297b6a201e13574a1e26b93704a40b53eb9f62f88d4447225f3a9b35a113d202`
- `results/artifacts-shootout.sha256` SHA-256: `f49cc489a4d3c63d12e96c45376e12f3015dacb5f81f02f200958c5d9669ff0f`
- `results/logs/scudo-build-config-audit.md` SHA-256: `fc74bf0fa29a72a643bb3b9f408256a8ae75297be3348ee227a993b40c6e8126`
