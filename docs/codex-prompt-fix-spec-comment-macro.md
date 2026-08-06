# Codex 授权 Prompt:修复 spec 注释宏解析问题后重跑

根因确认:RPM spec 的注释行同样经过宏解析,上一轮授权注释文本中的字面
%prep 被解析为第二个 section 声明。该注释文案由上游 prompt 口述,
责任不在你的实现;你的停车纪律正确。

## 授权修复(单独 commit)

1. 改写 spec 中该注释,移除一切 % 宏记号,不使用 %% 转义
   (转义仍依赖解析器行为,直接避开最稳):
   ".frozen 后缀用于避开 gbs export 的 gbp orig 归档启发式,
   防止 git 树生成的同名归档顶掉官方源码包;prep 阶段规范化回本名。"
2. 全量自查:grep -n '^#.*%' packaging/musl-libc-demo.spec
   注释行中不得残留任何 % 记号;自查输出贴入本轮日志。
3. commit message 引用 gbs-build.log 中 "second %prep" 错误行原文。

## 重跑

scripts/build_gbs.sh
期望顺序:export 无 Source1 顶替 → Source1 哈希门禁 PASS →
musl 编译(10–25 分钟正常)→ 三变体 → ELF 门禁 → BUILD_GATE_PASS → RPM。
成功后,前两轮 prompt 的全部条款继续有效(deploy → run_board → report,
预授权边界、测量纪律、交付清单不变)。
任何新的未预授权失败:照旧停车报告。

## 附带

将本次事故追加进 incident 归档(或新建
results/logs/incident-spec-comment-macro.md):现象、根因
(spec 注释过宏解析)、修复、教训(注释文案避开 % 记号)。
