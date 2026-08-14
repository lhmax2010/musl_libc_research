# musl-static + mimalloc 第四变体实测报告

## 1. startup 四元组

- 有效轮次：**30**；INVALID：**0**。
- glibc-dyn median：**2.507 ms**
- musl-static median：**1.060 ms**
- musl-dyn median：**1.576 ms**
- musl-mi median：**1.262 ms**

## 2. malloc 四方表（ns/op，全部 VALID 样本中位数）

| 线程 | glibc-dyn | musl-static | musl-dyn | musl-mi | mi/glibc | mi/musl-static |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 171.9 (n=5) | 320.4 (n=5) | 324.9 (n=5) | 89.7 (n=5) | 0.52x (n=5/5) | 0.28x (n=5/5) |
| 4 | 212.1 (n=5) | 1016.3 (n=5) | 1007.1 (n=5) | 196.3 (n=5) | 0.93x (n=5/5) | 0.19x (n=5/5) |

- malloc VALID：**40**；INVALID：**0**。

## 3. 内存与体积代价

| 指标 | musl-static | musl-mi | 绝对增量 | 倍数 |
|---|---:|---:|---:|---:|
| Pss | 52 kB | 112 kB | 60 kB | 2.15x |
| Private_Dirty | 8 kB | 24 kB | 16 kB | 3.00x |
| VmSize (threads 200) | 28372 kB | 159552 kB | 131180 kB | 5.62x |
| 二进制体积 | 439932 B | 552536 B | 112604 B | 1.26x |

- 补充采集 Rss：musl-static 52 kB (n=3)，musl-mi 120 kB (n=3)。
- Pss 样本数：musl-static n=3，musl-mi n=3。
- Private_Dirty 样本数：musl-static n=3，musl-mi n=3。
- VmSize 样本数：musl-static n=1，musl-mi n=1。
- mem/threads INVALID：**0**。

## 4. 数据填空

t4:mallocng 1016 → mimalloc 196.3 ns/op,为 glibc 的 0.93 倍; 代价:Private_Dirty 8 KB → 24 KB,VmSize +131180 KB,二进制 +110.0 KB。

## 5. 未复测项

- DNS：NOT_RUN；分配器无关，沿用前轮 `results/results.txt`。
- locale：NOT_RUN；分配器无关，沿用前轮 `results/results.txt`。
- 补跑命令：`SDB_TARGET=BOARD_RPI4 scripts/run_board.sh`（该命令会完整重跑本轮四方会话，不会只补 DNS/locale）。

## 6. Caveats

- 本报告来自单板、单日测量；四变体在同一会话内交替执行，频率、温度和 INVALID 原文保存在结果文件中。
- 平台 clang 版本：`22.1.8`；builtins 一致性：`PASS`。
- 板端安装采用方案 A `rpm --noplugins`，仅跳过安全插件钩子；RPM 数据库、payload 哈希和执行语义均已验证，不影响测量有效性。
- mimalloc 是第三方组件，引入后必须承担版本与 CVE 持续跟踪义务。
- 替换 musl mallocng 后，不再具备 mallocng 原有的堆加固属性。
- DNS 与 locale 未在本轮复测，相关原始观察仅沿用前轮，不参与分配器比较。

测量数据：`/home/linhao/Toolchain/development/musl-libc-research/results/results-mimalloc.txt`；编译器决策：`/home/linhao/Toolchain/development/musl-libc-research/results/logs/compiler-decision-mimalloc.txt`。
