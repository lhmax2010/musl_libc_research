# Codex 继续执行 Prompt:GBS 构建 → 部署 → 测量 → 报告

上一轮你在仓库缺少 `.git` 元数据处 fail-closed 停车,处理正确。仓库现已初始化并推送(`lhmax2010/musl_libc_research`,main,`b5f7f62`),阻塞解除。你的 Phase 0 产出与全部脚本已通过独立 review(多源共识、%build 门禁、wrapper 检查、板端脚本均确认无误),**现授权继续执行**。

## 一、执行序列

```bash
scripts/build_gbs.sh
SDB_TARGET=<BOARD_IP> scripts/deploy.sh
SDB_TARGET=<BOARD_IP> scripts/run_board.sh
python3 scripts/gen_report.py results/results.txt > results/report.md
```

每一步完成后先自检该步产物完整再进下一步;任一步失败,停下报告,不跳步、不并行抢跑。

## 二、预期与预授权处置(仅限以下三种情况,其余一律停车报告)

1. **musl 在 qemu chroot 内编译耗时 10–25 分钟属正常**。不要因慢而中断、更换构建方式或调小范围;超过 40 分钟无输出才视为异常停车,附 chroot 内进程状态。

2. **clang 版本闸门**:若 chroot clang 非 22.1.8,按设计 `BUILD_GATE_FAIL` 停车。此时报告:`clang --version` 原文、chroot 所用 repo baseurl、`compiler-decision.txt`(若已生成)。**不得**放宽版本正则或改用其他编译器,等待 FatTank 决策。

3. **glibc-dyn NEEDED 白名单触发**:当前白名单为 `libc.so.6|libpthread.so.0`。若门禁报出其他条目(如 `ld-linux-armhf.so.3` 一类工具链行为),这是白名单收紧而非真实问题——**预授权处置**:将实际 NEEDED 全量列表报告出来,同时把该条目加入白名单重跑一次构建;白名单变更必须单独 commit,message 注明触发证据(readelf 原文行)。除此之外的任何门禁失败(GLIBC_ 符号、INTERP 不符、静态判定失败等)一律停车,不得修改门禁逻辑。

板端 `rpm -Uvh` 失败(Smack/只读分区/依赖):原样报告完整错误输出与 `ls -Z /opt/usr`、`mount | grep -E 'opt|rootfs'`,停车等待指示,不自行改用其他安装方式。

## 三、测量执行纪律

- run_board 全程使用绝对路径;governor 门控与逐轮 `cur_freq` 检查按脚本既有逻辑执行,INVALID 轮保留在 results.txt 中不删除。
- startup_triple 30 轮中 INVALID ≥ 5 轮时:完成全部测量后报告 INVALID 分布与温度曲线,等待指示是否补测,不自行加轮。
- 板端 resolv.conf 只读取归档,不修改;测量期间不重启板子。
- results.txt 为原始数据,只追加不编辑;报告由 gen_report.py 生成,不手工改数字。

## 四、完成后交付

```text
[  ] gbs-build.log(含 BUILD_GATE_PASS 行)与 RPM 路径、RPM sha256
[  ] compiler-decision.txt 原文(确认 clang 22.1.8、rtlib 三变体一致)
[  ] build-commands.txt 原文(三条编译命令)
[  ] 板端 smoke 输出(musl-dyn 经包内 loader 运行成功的证据行)
[  ] results/results.txt 完整,INVALID 轮及原因列表
[  ] results/report.md:两组配对 delta(musl-static vs glibc-dyn;musl-static vs musl-dyn)、
     malloc 三变体表、完整 Caveats 章
[  ] 实现摘要:本轮执行的命令清单、耗时、异常与处置、未执行项(NOT_RUN+原因+补跑命令)
```

报告生成后**不要自行解读结论倾向**——数据如实呈现,favorable/unfavorable 的判读由 FatTank 对照 Caveats 完成。musl 在某些维度(4 线程 malloc、locale/ko_KR)表现差是预期内的有效结果,原样保留,不做任何弱化或解释性修饰。
