# GBS musl vs glibc 快速 Demo

本项目在同一个 Tizen armv7l GBS chroot 内、使用平台 clang 构建三个可比探针，并将它们和 musl 动态加载器一起封装为一个不触碰系统 libc 路径的 RPM。目标设备为 RPI4 / Tizen armv7l。

## 对比设计

| 变体 | libc | 链接方式 | 编译器 |
|---|---|---|---|
| `micro.glibc-dyn` | 平台 glibc | 动态 | chroot 平台 clang |
| `micro.musl-static` | musl 1.2.5 | 静态 | 同一个 clang，经 `musl-clang` |
| `micro.musl-dyn` | musl 1.2.5 | 动态、包内 loader | 同一个 clang，经 `musl-clang` |

三条命令使用同一份展开后的 `%optflags` 和相同 builtins 运行库选择。构建脚本要求 clang 版本精确为 `22.1.8`；不一致时立即失败，不能静默放宽。`timer` 也由平台 clang 动态链接 glibc，但它只是测量仪器，不参与三变体结论。

RPM 只安装到：

```text
/opt/usr/musl-demo/bin/{micro.glibc-dyn,micro.musl-static,micro.musl-dyn,timer}
/opt/usr/musl-demo/lib/libc.so
/opt/usr/musl-demo/lib/ld-musl-armhf.so.1 -> libc.so
/opt/usr/musl-demo/share/{build-commands.txt,artifacts.sha256,sizes-prestrip.txt,compiler-decision.txt}
```

没有 `%post`、`ldconfig`、系统 libc `Provides/Conflicts`，也不会写入 `/lib`、`/usr/lib` 或 `/etc`。

## 信任根与取源

信任根不是一条人工抄录的哈希，而是 [scripts/fetch_musl.sh](scripts/fetch_musl.sh) 实现的多源共识协议：

1. 只从 `https://musl.libc.org/releases/musl-1.2.5.tar.gz` 下载发布包，同时计算 SHA-1、SHA-256、SHA-512。
2. 独立比对 Rich Felker 的 `musl-cross-make` 哈希、Alpine aports（需要时自动查历史）和 Buildroot `musl.hash`（需要时自动查历史）。任何已取得摘要不一致都会删除下载物并失败。
3. 至少两个独立摘要源一致才冻结 `scripts/musl-1.2.5.sha256`；参考 SHA-256 不一致也会失败。
4. 官方 GPG 签名与官方 HTTPS 发布 key 尽力验证，结果无论成功或失败均写入证据日志。
5. spec `%build` 再次用冻结值验证 `Source1`，形成 host/GBS 双点校验。

所有源原文归档在 `results/logs/hash-sources/`，判定过程在 `results/logs/fetch-musl.log`。审核者只需确认日志中 `independent_sources_confirmed>=2` 和 `consensus=PASS`。已存在的冻结 tarball 若被改动会立即删除并返回非零，不会用自动重下载掩盖本地篡改。

执行：

```bash
scripts/fetch_musl.sh
```

## 构建

前置条件是 host 已安装 GBS，配置文件中的仓库可达。规范要求的原始命令是：

```bash
gbs -c config/gbs_llvm.conf build -A armv7l --include-all
```

推荐使用等价包装脚本，它显式将 buildroot 放在当前项目下、保存完整日志、复制 RPM，并从 RPM 提取编译器决策和制品清单：

```bash
scripts/build_gbs.sh
```

可通过 `GBS_CONFIG` 与 `GBS_ROOT` 覆盖配置和 buildroot。构建 musl 约需 10–25 分钟。关键输出为：

```text
results/logs/gbs-build.log
results/logs/compiler-decision.txt
results/rpms/musl-libc-demo-*.armv7l.rpm
results/artifacts.sha256
```

`packaging/build-demo.sh` 在 `%build` 内执行所有 fail-closed 门禁：Source1 冻结哈希、三种 ELF 的链接/解释器/NEEDED、musl 静态文件中的 `GLIBC_`、ARM ELF32 hard-float，以及 clang 与 builtins 一致性。任何门禁失败都会使 rpmbuild 非零退出。

## 部署

设备地址默认是 `192.168.108.25`，可用 `SDB_TARGET` 覆盖；也可用 `RPM_PATH` 指定 RPM：

```bash
SDB_TARGET=192.168.108.25 scripts/deploy.sh
```

脚本严格执行 `sdb connect`、`sdb root on`、`sdb push`、`rpm -Uvh --force`。RPM 安装失败时原样保存输出并停止，不会改用手工复制。安装后先用包内 `artifacts.sha256` 校验整个 payload，再把板端 `/opt/usr/musl-demo/bin/*` 与 host 从 RPM 解出的文件逐字节哈希比较，最后对三个变体做无参 smoke；`micro.musl-dyn` 成功即证明包内 loader 可用。

日志位于 `results/logs/deploy.log`。

## 板端测量与报告

部署通过后执行：

```bash
SDB_TARGET=192.168.108.25 scripts/run_board.sh
```

脚本会把所有 CPU governor 设为 `performance`，记录测前/测后温度与频率，并在每个 startup 三元组前后检查 `scaling_cur_freq`。任一核低于 `scaling_max_freq` 的轮次会保留原值并写为 `startup_invalid`；报告统计会排除该轮。

测量矩阵包括：30 轮交替顺序 startup 三元组、三变体各 3 次 `smaps_rollup`、`threads 200`、1/4 线程各 5 轮 malloc、`localhost`/`www.tizen.org` DNS、默认/`ko_KR.UTF-8` locale。`/etc/resolv.conf` 只读取并原文归档，不做修改。

输出：

```text
results/results.txt
results/logs/resolv.conf.board
results/report.md
```

也可单独重新生成报告，不修改原始结果：

```bash
python3 scripts/gen_report.py results/results.txt > results/report.md
```

报告包含 `musl-static vs glibc-dyn`（方案差异）和 `musl-static vs musl-dyn`（链接方式贡献）两组配对 delta，以及带 `musl-dyn` 列的 malloc 表。固定 Caveats 说明单板/单日/样本量、同一 clang 与 `%optflags`、builtins 一致性及 musl ABI/`dlopen`/NSS/locale 限制。

## 失败策略

网络、摘要共识、clang 版本、ELF 门禁、RPM 安装、host/board 哈希或 governor 门控任一失败都返回非零。不要绕过门禁；保留对应日志并先调查。没有 GBS 或板端时只能把相应阶段标为 `NOT_RUN`，不能伪造 RPM、smoke、测量数据或报告。

## 当前执行状态

| 阶段 | 状态 | 证据/原因 |
|---|---|---|
| Phase 0 取源与共识 | PASS | `fetch-musl.log` 中 S1、S3 一致，官方 GPG PASS；Alpine 端点 403，记录为 UNAVAILABLE |
| 一字节篡改测试 | PASS | `results/logs/fetch-musl-tamper-test.log`，退出码 6，篡改 tarball 被删除后由可信备份恢复 |
| Phase 1 GBS 构建 | NOT_RERUN | 首次执行 `scripts/build_gbs.sh` 时尚无 `.git`，GBS 报错 `No source package found`；当前 workspace 已初始化并推送为有效 Git 仓库，可以重新执行。历史输出见 `results/logs/gbs-build.log` |
| Phase 2 板端部署/smoke | NOT_RUN | Phase 1 尚未产生 RPM；先补跑 `scripts/build_gbs.sh`，再运行 `SDB_TARGET=192.168.108.25 scripts/deploy.sh` |
| Phase 3 板端测量 | NOT_RUN | 依赖部署；精确补跑命令：`SDB_TARGET=192.168.108.25 scripts/run_board.sh` |
| Phase 4 实测报告 | NOT_RUN | 依赖板端 `results/results.txt`，`run_board.sh` 成功后自动生成；单独补跑命令：`python3 scripts/gen_report.py results/results.txt > results/report.md` |

`tests/fixtures/` 仅用于报告解析器的本地回归测试，不是板端数据，也不会写入 `results/report.md`。
