# Codex 授权 Prompt:mimalloc.o 改用 musl 头文件环境编译后重跑

根因定性(写入事故归档):上游 prompt 指定裸 clang 编译 mimalloc.o,
使用了 chroot glibc 头文件;glibc 头在 LFS 语境将 mmap 重定向至 mmap64
符号,而 musl 1.2.5 已从 ABI 移除 LFS64 别名,libc.a 仅有 mmap。
责任在 prompt 设计,不在实现。目标文件属于 musl 链接域,必须以 musl
头文件环境编译——这既修 mmap64,也从机制上消除 open64/pread64 等
同族 LFS64 符号的潜在同类问题。

## 授权修改(单独 commit;仅改 mimalloc.o 的编译器调用,其余零改动)

1. 编译命令由裸 clang 改为 musl wrapper:
   musl-inst/bin/musl-clang $OPTFLAGS -O2 -DNDEBUG -DMI_MALLOC_OVERRIDE \
   -I mimalloc-2.1.7/include -c mimalloc-2.1.7/src/static.c -o mimalloc.o
   底层仍是同一 chroot clang 22.1.8、同一 $OPTFLAGS;仅头文件环境
   切换为 musl(这是正确性要求,非变量引入)。
2. 新增链接前机械门禁(防整族问题,不只 mmap64):
   nm -u mimalloc.o 中不得出现
   mmap64|munmap64|open64|openat64|pread64|pwrite64|lseek64|ftruncate64|
   fstat64|stat64|mmap2
   任一出现即退非零并列出;检查输出原文贴日志。
3. compiler-decision.txt 追加:
   mimalloc_compile_env=musl-clang(headers=musl, backend=clang 22.1.8)
4. commit message 引用 mmap64 链接错误原文;事故归档补充根因与修复。

## 重跑

scripts/build_gbs.sh
期望:Source 前置检查 → 双哈希门禁 → mimalloc 编译(musl 头)→
LFS64 符号门禁 → 第四变体链接 → 符号门禁(map 中 malloc 定义方 =
mimalloc.o)→ ELF/softfp 门禁 → RPM release 2。
成功后继续既定序列:部署 → 一正三负横幅门禁 → 四变体板端同会话测量 →
数据填充版 report-mimalloc.md。前序 prompt 全部条款继续有效。
新的未预授权失败照旧停车。
