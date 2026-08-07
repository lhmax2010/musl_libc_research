# Codex 授权 Prompt:补 clang 资源头目录后重跑

根因定性(写入事故归档):musl-clang 的 -nostdinc 同时屏蔽了 clang
compiler-resource 头目录;stdatomic.h 属编译器资源头(musl 不提供,
其余如 stddef/stdarg musl 自带,故此前未暴露),mimalloc 使用 C11
atomics 触发。属 musl-clang wrapper 已知局限,非实现错误。

## 授权修改(单独 commit;不打 wrapper 补丁,只改 mimalloc.o 编译调用)

1. 编译命令追加一个显式 -isystem(显式路径不受 -nostdinc 影响):
   RESDIR="$(clang -print-resource-dir)"
   test -f "$RESDIR/include/stdatomic.h" || { echo "GATE: stdatomic.h \
   not in $RESDIR/include"; exit 1; }
   musl-inst/bin/musl-clang $OPTFLAGS -O2 -DNDEBUG -DMI_MALLOC_OVERRIDE \
   -I mimalloc-2.1.7/include \
   -isystem "$RESDIR/include" \
   -c mimalloc-2.1.7/src/static.c -o mimalloc.o
   顺序要求:该 -isystem 位于用户参数段(wrapper 自身的
   -isystem musl_inc 在前)——musl 头对重叠头文件保持优先,
   资源目录仅补齐 musl 缺失的编译器头。禁止改动 wrapper 文件本身,
   禁止去掉 -nostdinc,禁止把资源目录放到 musl 头之前。
2. 前置断言(上述 test 行)输出与 RESDIR 实际路径贴日志;
   compiler-decision.txt 追加:
   mimalloc_isystem_resource=$RESDIR/include
   mimalloc_include_order=musl_first_resource_fill
3. commit message 引用 stdatomic.h 报错原文;事故归档补充根因与修复。

## 重跑(维持上轮边界:仅 host 侧,板端占用中)

scripts/build_gbs.sh
期望:… → mimalloc 编译 PASS → LFS64 符号门禁 → 第四变体链接 →
符号/ELF/softfp 门禁 → RPM release 2 + sha256 登记。到 RPM 为止停止,
板端阶段继续 NOT_RUN(等待放行信号)。

预告一个可能的下一站(不预授权):32 位 ARM 上 mimalloc 的 64 位原子
操作若未被 clang 内联(armv7-a 具备 ldrexd/strexd,通常会内联),
链接期会报 __atomic_* undefined——出现即停车,附未解析符号全表,
libatomic 的引入来源需要单独决策,不得自行链接任意 libatomic。
