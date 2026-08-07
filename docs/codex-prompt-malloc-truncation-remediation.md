# Codex 授权 Prompt:malloc 样本截断处置——解析加固 + 哨兵机制 + 补测

根因定性(写入事故归档):板端单样本输出中途截断(sdb shell 输出未排干,
无对应进程异常事件),原始数据无尾换行,后续 header 拼接;解析器缺少
样本完整性校验,将后续数值错归。原始 results.txt 保持只读,不修改。

## 授权修改(每项单独 commit)

1. gen_report.py 解析加固(防御性解析,判定逻辑不变):
   a. header(malloccfg=/dnscfg=/localecfg= 等)出现在行中部时,
   在该处切分重同步,其前的当前样本标 INVALID;
   b. 每个 malloc 样本必须集齐 4 个期望键(threads/iters_per_thread/
   ns_per_op_mean/checksum)才计 VALID,缺任一即 INVALID,值不得跨
   header 归属;
   c. 输出每单元格 VALID 样本数 n,进最终表格。
   用现有 results.txt 回归:必须恰好识别出该 1 个 INVALID 样本,
   其余 29 个 VALID 归属不变;回归输出贴日志。

2. run_board.sh 哨兵机制(用于补测与今后所有运行):
   每次 probe 调用后追加输出 sample_end=OK 独立行;
   解析器将无哨兵的样本判 INVALID。截断由此从静默错误变为机械可检。

3. 补测(不动原始文件,新建 results/results-supplement.txt):
   完整跑一轮 t=4 三变体交替(标 rep=6),门控照旧
   (governor/cur_freq/温度,板端无残留进程先确认);
   t=1 不补(30/30 完整)。

4. 合并规则(写入报告方法节):
   每单元格取全部 VALID 样本的 median,逐格标注 n
   (预期:musl-dyn t4 n=5,其余 t4 n=6,t1 全部 n=5);
   不剔除、不挑选、不加权。

## 收尾

重新生成 report.md:malloc 表含逐格 n;Caveats 增加截断事故一行并引用
incident 归档;确认 startup/mem/threads/dns/locale 各节完整后,交付:
- report.md 全文
- compiler-decision.txt
- startup 三元组两组配对 delta 数值
- malloc 全表(含 n)
- INVALID 清单(startup 0 + malloc 1 + 补测中新增若有)
交付后停止,等待 FatTank 数据核验,不自行下结论。
