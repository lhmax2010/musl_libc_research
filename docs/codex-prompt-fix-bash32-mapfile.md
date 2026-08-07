# Codex 授权 Prompt:build-demo.sh Bash 3.2 兼容修复后重跑

根因确认:chroot Bash 为 3.2.57,mapfile 为 Bash 4.0+ 内建。停车正确。

## 授权修复(单独 commit,仅限 build-demo.sh——它是唯一在 chroot 内执行的脚本;
host 侧脚本运行于现代 bash,不改)

1. mapfile 一处改写为 3.2 兼容等价实现(数组 += 追加,Bash 3.1+ 支持):

   compiler_rt_candidates=()
   while IFS= read -r line; do
       compiler_rt_candidates+=("$line")
   done < <(
       find "$runtime_dir" -maxdepth 1 -type f \
           \( -name 'libclang_rt.builtins-arm*.a' -o -name 'libclang_rt.builtins.a' \) \
           -print | sort
   )

   语义与原实现逐项等价:空结果 → 空数组;顺序保持 sort 输出。

2. 全量 Bash 3.2 兼容自查(输出贴入本轮日志):
   grep -nE 'mapfile|readarray|declare -A|coproc|&>>|\$\{[A-Za-z_]+(\^\^?|,,?)[}]?' \
   packaging/build-demo.sh
   预授权:若自查再发现 Bash 4+ 语法,按下表就地转换,同一 commit 内完成:
   declare -A        → 改用平行普通数组或 case 分发
   ${var,,} ${var^^} → tr '[:upper:]' '[:lower:]' / 反向
   readarray         → 同第 1 条 while-read 模式
   &>>               → >>file 2>&1
   注意:< <(进程替换)、[[ =~ ]]、read -r -a、数组 += 在 3.2 均可用,
   不要过度改写;门禁判定逻辑与阈值零改动。

3. commit message 引用 gbs-build.log 中 "mapfile: command not found" 原文;
   事故归档 results/logs/incident-bash32-mapfile.md(现象/根因/修复/教训:
   chroot 目标 shell 版本应作为脚本语法基线)。

## 重跑

scripts/build_gbs.sh
期望顺序:export 无顶替 → Source1 门禁 PASS → clang 版本门禁 PASS →
rtlib 探测 → musl 编译(10–25 分钟正常)→ 三变体 → ELF 门禁 →
BUILD_GATE_PASS → RPM。
成功后前序 prompt 全部条款继续有效(deploy → run_board → report)。
新的未预授权失败照旧停车。
