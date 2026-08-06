# Codex 授权 Prompt:补齐 Source6 packaging 副本后重跑

根因确认:spec 声明的 Source 文件必须位于 packaging/ 才会进入 gbs export
的 SOURCES;mimalloc-2.1.7.sha256 仅存在于 scripts/,遗漏了 musl Source3
当时的双副本动作。属实现遗漏,非新问题类型。

## 授权修改(单独 commit)

1. cp scripts/mimalloc-2.1.7.sha256 packaging/mimalloc-2.1.7.sha256
   复制后:
   a. diff scripts/mimalloc-2.1.7.sha256 packaging/mimalloc-2.1.7.sha256
   必须为空;
   b. 其内容哈希值必须与 results/logs/mimalloc-source-review.md 中
   FatTank 已审核勾选的值逐字符一致;
   两项自查输出贴入本轮日志。

2. 防复发检查加入 scripts/build_gbs.sh(GBS 调用之前,基础设施级前置):
   解析 spec 中全部 SourceN 声明,逐一断言 packaging/ 下存在同名文件,
   缺失即列出缺失清单并退非零(在进入 GBS 之前拦截,而不是等 %prep 报错)。
   对现有 Source0-Source6 全量跑一遍,结果贴日志。

3. commit message 引用 %prep 报错原文;事故归档
   incident-mimalloc-source6-export.md 补充修复与防复发措施。

## 重跑

scripts/build_gbs.sh
期望顺序:Source 前置检查 PASS → export → Source1/Source5 双哈希门禁 →
mimalloc 编译 → 第四变体链接 → 符号/ELF/softfp 门禁 → RPM(release 2)。
成功后继续既定序列:部署 → 一正三负横幅门禁 → 四变体板端同会话测量 →
数据填充版 report-mimalloc.md。前序 prompt 全部条款继续有效。
新的未预授权失败照旧停车。
