# Codex 授权 Prompt:修复 ld.musl-clang 静态链接归档顺序后重跑

根因(写入事故归档):ld.musl-clang 将 -lc 追加在链接命令末尾,位于编译器
驱动传入的 libgcc.a 之后;armv7-a 基线无硬件除法保证,micro.o 与 libc.a
成员均含 __aeabi_*div* 调用;单遍归档扫描下 libgcc.a 先于 -lc 被扫过,
故 loaded 但未解析。libc.so 路径无此问题(musl 自身链接时已静态收入
builtins),仅 libc.a 静态路径暴露。

## 授权修复(单独 commit,仅限 build-demo.sh 内新增 wrapper 后处理步骤;
门禁、rtlib 选择、COMMON_FLAGS 零改动)

1. musl install 与现有 wrapper 检查之后,新增步骤:
   a. 打印 ld.musl-clang 全文进日志(修补前原文存档);
   b. 定位其末尾链接调用行,识别参数风格:
   - 若 exec 的是真实 ld(参数为纯链接器风格):
     将该行中的 ` -lc ` 替换为
     ` --start-group -lc <libgcc.a绝对路径>[ <libgcc_eh.a绝对路径>] --end-group `
   - 若 exec 的是 $cc 驱动(参数需 -Wl, 前缀):同语义改写,加 -Wl, 前缀;
   libgcc_eh.a 仅在与 libgcc.a 同目录存在时纳入 group;
   路径使用 build-demo.sh 中已探测的 $RTLIB_ARCHIVE 及其同目录展开,
   以具体绝对路径写入(wrapper 运行期无我方变量)。
   c. 打印修补后全文进日志;diff 原文/修补文存入
   results/logs/incident-musl-ldwrapper-group.md;
   d. 重跑既有 wrapper 门禁(cc="clang" 检查)确认仍 PASS;
   e. compiler-decision.txt 追加:
   ldwrapper_patch=start-group 与替换前后两行原文。

2. 禁止:--whole-archive 方案(污染大小测量)、改动 musl 源码、
   改动三条变体编译命令、放宽任何 ELF 门禁。

3. commit message 引用链接错误四行原文。

## 重跑

scripts/build_gbs.sh
期望:直达三变体构建 → ELF 门禁 → BUILD_GATE_PASS → RPM。
注意:musl-dyn 变体经同一 wrapper 链接,group 对动态路径无害
(libc.so 自含 builtins);若 musl-dyn 出现新的链接异常,停车报告。
成功后前序 prompt 全部条款继续有效(deploy → run_board → report)。
新的未预授权失败照旧停车。
