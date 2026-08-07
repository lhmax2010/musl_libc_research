# Codex 实现 Prompt:总部复现包(Reproduction Package)封装

背景:总部需要完整测试方案与代码以独立复现本 demo 的全部结论。仓库
`lhmax2010/musl_libc_research`(分支 execution/continue-20260806)已含全部
代码、spec、脚本、原始数据与事故归档;你的任务不是新增测试,而是把它封装成
**外部复现者可独立执行的交付包**。全部新增文档使用**英文**(总部受众);
本 prompt 及你的过程报告仍用中文。前序纪律(fail-closed、停车报告、
原始数据只读)继续有效。

## Phase 1:保密与卫生扫描(第一步,发现问题即停车)

1. 全仓库(含 git 全历史)扫描:凭据模式(passwd/password/token/api_key/
   ssh key 头)、内部主机名/非公网 URL(download.tizen.org 与 github.com
   属公开,已确认白名单)、个人路径(/home/<user>)。
   工具自选(如 gitleaks 可用则用),规则与全量输出归档
   `results/logs/repro-confidentiality-scan.log`。
2. 板端 IP(192.168.x.x 私网段)允许保留在日志/证据中,但**指南与配置模板
   中一律参数化**(SDB_TARGET 占位)。
3. 历史中若发现真实凭据:立即停车报告,不得自行改写 git 历史。

## Phase 2:发布整理

1. 将 execution/continue-20260806 **merge(非 squash)**入 main——事故链的
   commit 粒度本身是证据;打注解 tag `demo-v1.0-repro`,tag message 含
   RPM sha256 与两份原始数据 sha256。
2. 新增 `LICENSES/` :musl(MIT)、mimalloc(MIT)原文 + `NOTICE.md`
   说明第三方组件与版本。
3. `config/gbs_llvm.conf` 保留原文(已确认无敏感项),另生成
   `config/gbs_llvm.conf.example`,把两个 snapshot URL 标注为
   "PINNED — do not change for byte-comparable chroot" 并注明日期戳
   20260722.045200 / 20260725.003315 是复现同一 chroot 的关键。
4. 根 README 重写为包入口:一段概述 + 指向 TEST_PLAN / REPRODUCTION /
   报告 / 证据的目录表。

## Phase 3:`docs/TEST_PLAN_EN.md`(测试方案,英文)

结构固定如下,内容从既有设计文档、report.md、report-mimalloc.md 与
compiler-decision 提炼,**不得引入仓库中不存在的声明**:
1. Objective & scope(方案级对比;non-goals 照抄)
2. Variants & attribution design(四变体表;同编译器同 %optflags;
   musl-dyn 的归因角色;mimalloc 链接期插桩与公平性铁律)
3. Metrics & instruments(七维度 + 分配器补救;每项:测什么/用什么探针/
   为什么这样测)
4. Measurement controls(governor、cur_freq 门控、轮内交替、哨兵机制、
   VALID/INVALID 定义、样本数)
5. Build & integrity gates(多源哈希共识、双点校验、ELF 门禁、clang 版本
   门禁、rtlib 一致性、ABI 四方一致、横幅一正三负)
6. Statistics(配对相对差中位数、逐格 n)
7. Known limitations & caveats(单板单日、micro 探针、DNS 深测未做、
   报告 Caveats 全量收录)

## Phase 4:`docs/REPRODUCTION_EN.md`(复现指南,英文)

1. Prerequisites 表:x86_64 Linux host、GBS 版本、sdb、python3、
   目标板要求(**Tizen armv7l softfp**;RPI4 为参考板;其他 armv7l softfp
   板可用,ABI 一致性门禁会自动校验)、网络可达清单(musl.libc.org、
   github.com、download.tizen.org)。
2. Step-by-step:fetch_musl → fetch_mimalloc → 审核勾选(见下)→
   build_gbs → deploy → run_board → gen_report,每步:精确命令、预期
   PASS 输出样例(从既有日志摘录)、预期耗时。
3. **审核闸门的外部化**:FatTank 勾选框机制对总部复现者改为
   "Reviewer sign-off":指南说明哈希应对照文档中列出的共识来源
   (musl 官方 GPG、richfelker 仓库、Conan/vcpkg 钉定 commit,URL 全列)
   独立核对后自行勾选——把我们的信任根建立过程交给对方重演,而非要求
   对方信任我们的值。
4. Troubleshooting 表:把 8 份 incident 归档逐条转写为
   "症状 → 根因 → 处置"(gbs orig 顶替 / spec 注释宏 / Bash 3.2 /
   aeabi 链接序 / softfp loader 名 / Smack 插件 / 输出截断 / mmap64 /
   stdatomic)——这是复现包里最省对方时间的一节。

## Phase 5:复现成功判定(`docs/ACCEPTANCE_EN.md` + `scripts/verify_reproduction.py`)

两层判定,写死并脚本化:
- **L1 门禁层(必须全 PASS,硬判)**:全部构建/部署门禁 + 测量完整性
  (INVALID 处理正确、样本数达标)。
- **L2 方向层(容差判,硬件不同数值必不同)**:脚本读取复现方
  results*.txt,与参考值(本仓库数据)比对方向与量级:
  startup delta(musl-static vs glibc)≤ −30%;threads VmSize 比 ≥ 20×;
  malloc t4 mallocng/glibc ≥ 2×;mimalloc t4 / mallocng t4 ≤ 0.5;
  Private_Dirty musl-static < glibc;每项输出 PASS/FAIL/INCONCLUSIVE 与
  双方数值。明确声明:L2 验证的是**结论方向可复现**,不是数值相等。
- 参考值以 JSON 固化(`docs/reference-results.json`),字段带来源指针。

## Phase 6:自验与打包

1. 指南 dry-run:host 侧步骤按文档逐条实际执行一遍(fetch 幂等短路即可);
   板端步骤标注 "requires board" 并核对命令与现行脚本签名一致。
2. verify_reproduction.py 用本仓库自身数据自检:必须全 PASS(自己复现
   自己是判定脚本的回归基线)。
3. `git archive demo-v1.0-repro` 生成 tar.gz + sha256,作为不依赖 GitHub
   访问权限的离线交付形态。
4. 推送 tag 与全部变更。

## 验收清单

```text
[ ] 保密扫描全历史零发现(或已停车上报)
[ ] main 已 merge,tag demo-v1.0-repro 含产物哈希
[ ] LICENSES/NOTICE 齐;conf.example 快照钉定注记在
[ ] TEST_PLAN_EN / REPRODUCTION_EN / ACCEPTANCE_EN 三文档完整,
    无仓库不存在的声明
[ ] Troubleshooting 覆盖全部 8 个 incident
[ ] verify_reproduction.py 自检全 PASS,exit code 记录
[ ] host 侧 dry-run 逐条通过;板端步骤标注清晰
[ ] 离线 tar.gz + sha256 产出
[ ] 未执行项 NOT_RUN + 原因 + 补跑命令
```

停车规则照旧:任何未预授权失败、任何保密疑点、任何文档声明找不到仓库
依据,停下报告。完成后给出实现摘要、文件清单、tag 与归档哈希。
