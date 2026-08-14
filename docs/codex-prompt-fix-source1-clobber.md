# Codex 授权 Prompt:处理 GBS Source1 同名归档冲突后重跑

你的停车正确,门禁按设计工作。根因已定位:`gbs export` 的 gbp orig 归档启发式会把 spec 中第一个归档样式的 Source(带版本号的 `*.tar.gz`)当作 native 包 upstream orig,用 git 树重新生成同名文件,在导出目录顶掉了真实的官方 tarball。%build 内的 Source1 二次哈希校验(双点校验第二点)正是为此类场景设计,本次实证有效。

## 一、授权的修复方案(唯一方案,不要尝试其他绕法)

让 Source1 从扩展名上脱离 gbp 的归档识别:

1. `git mv packaging/musl-1.2.5.tar.gz packaging/musl-1.2.5.tar.gz.frozen`
   文件内容零改动;改名前后各算一次 sha256,两值必须都等于冻结值
   `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4`,写入本轮日志。
2. spec 修改仅一行 + 注释:
   `Source1: musl-1.2.5.tar.gz.frozen`
   注释写明:".frozen 后缀用于避开 gbs export 的 gbp orig 归档启发式,
   防止 git 树生成的同名归档顶掉官方源码包;%prep 中规范化回本名。"
   `%prep` 中对应改为 `cp -p %{SOURCE1} musl-1.2.5.tar.gz`(目标名不变,
   build-demo.sh 与全部门禁逻辑**零改动**)。
3. `scripts/fetch_musl.sh`:落位路径与幂等检查改为新文件名;
   冻结哈希值不变,涉及文件名字段的地方同步。
4. `packaging/musl-1.2.5.sha256` 与 `scripts/musl-1.2.5.sha256`:
   哈希值不变;若文件名字段被脚本解析则同步为新名,否则保持。

以上为**单独一个 commit**,message 引用本次事故证据(gbs-build.log 中
expected/actual 两行原文)。禁止改动 build-demo.sh 的任何门禁逻辑;
禁止使用 gbs/gbp 的导出选项类绕法(版本行为不可控)。

## 二、重跑与验证

1. 重跑 `scripts/build_gbs.sh`。构建开始后,在日志中定位 export 阶段,
   确认本次没有再出现对 Source1 的重新生成;若 gbs 仍生成
   `musl-libc-demo-1.0.0.tar.gz` 一类与 spec 无关的归档,无害,忽略即可。
2. 期望顺序到达:Source1 哈希门禁 PASS → musl 编译(10–25 分钟正常)→
   三变体构建 → ELF 门禁 → `BUILD_GATE_PASS` → RPM 产出。
3. 若 Source1 门禁再次失败:停车,附 export 阶段日志与导出目录
   `ls -l` + `sha256sum`,不要重试第三次。

## 三、后续

构建成功后,**上一轮"继续执行 Prompt"的全部条款继续有效**,依序:
`SDB_TARGET=<BOARD_IP> scripts/deploy.sh` → `scripts/run_board.sh` →
`gen_report.py`,交付清单、预授权边界(NEEDED 白名单一项)、测量纪律、
"数据如实呈现不自行判读"均不变。

额外一条:将本次事故(现象、根因、修复、门禁拦截证据)整理为
`results/logs/incident-gbs-orig-clobber.md` 归档;最终 report.md 的
evidence 章可引用它作为完整性链有效性的实证。
