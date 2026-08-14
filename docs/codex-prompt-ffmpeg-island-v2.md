# Codex 实现 Prompt v2:ffmpeg 软解岛式试点(Tizen 官方源码版)

背景:musl demo(tag `demo-v1.0-repro`)已完成探针级验证;本任务把同一套
构建与测量体系应用到第一个**平台正式模块**:Tizen 官方 ffmpeg 源码树的
h264 **纯软件解码** CLI。在仓库 main 上开分支 `execution/ffmpeg-island`。
前序全部纪律继续有效:fail-closed、未预授权失败停车、原始数据只读、
证据归档、FatTank 审核勾选物理闸门。

## 一、范围与 Non-goals(报告固定章节)

- 被测对象:**Tizen 官方 ffmpeg 源码树(含平台补丁系列)**,以最小化软解
  configure 构建的 CLI(仅 h264 原生软解 + mov demuxer + file protocol)。
- 结论边界:仅覆盖岛式静态 CLI 形态;不外推至 libavcodec 动态库路径、
  gst-libav / libmm-player 等框架(前期分诊已排除)。
- 非目标:硬解(§五三层排除)、编码、网络协议、外部库。

## 二、源码获取、溯源与钉定(本版核心变更)

1. **获取由你执行**,实现 `scripts/fetch_tizen_ffmpeg.sh`:
   ```bash
   git clone "git://review.tizen.org/git/platform/upstream/ffmpeg" -b tizen
   ```
   克隆后立即登记 `HEAD` commit。**钉定机制**:首次克隆的 commit 写入
   `packaging/ffmpeg-tizen.commit`(冻结文件,提交入 git);此后一切构建
   前置校验 checkout == 冻结 commit——branch `tizen` 是移动指针,
   复现锚定在 commit 不在分支名。脚本幂等:本地已有且 commit 匹配则短路。
2. **溯源登记**(`results/logs/ffmpeg-src-provenance.txt`,入 git):
   remote URL、冻结 commit、`git log -1` 原文、树内 RELEASE /
   libavutil/version.h 提取的实际版本号(不假设版本)、Tizen packaging
   目录 spec 与补丁清单原文归档、工作区 `git status --porcelain` 必须干净。
3. **打包**:钉定 commit 的树经 `git archive` 产出
   `packaging/ffmpeg-tizen-src.tar.gz.frozen`(.frozen 机制沿用),
   sha256 冻结进 `packaging/ffmpeg-tizen-src.sha256`。
4. **公开性**:该源码为公开开源(FatTank 已确认),tarball 与冻结文件
   正常提交并推送;NOTICE.md 增补 ffmpeg 许可证(LGPL/GPL 按实际
   configure 结果记录——本岛最小配置不启用 GPL 组件,预期 LGPL,
   以 configure 输出的 License 行为准入册)。
5. **审核勾选闸门**:对象为"冻结 commit 确认"——Codex 克隆并生成
   provenance 后,FatTank 核对 commit 与来源后勾选;勾选前构建入口
   退非零(物理挡板沿用)。

## 三、Tizen spec 与平台补丁处理

1. 定位树内 Tizen 原 spec(通常 `packaging/ffmpeg.spec`),**原文归档**为
   `share/tizen-ffmpeg-spec.orig`,任何修改前先留底。
2. **平台补丁一致性(门禁)**:从 Tizen spec 的 %prep 提取补丁应用序列,
   三变体(F1/F2/F3)构建**必须应用完全相同的补丁序列**;实际应用清单与
   Tizen spec 声明清单 diff 为空,任一补丁 apply 失败即停车(可能是
   musl 相关冲突——那本身是 C8a 级发现,报告而非绕过)。
3. **configure 策略**:对比变体一律使用本 prompt §五冻结的最小软解
   configure(三变体等价,公平性要求);Tizen spec 自身的 configure 行
   归档为参考,与我方最小集的差异逐项列表进报告附录
   (说明"平台完整构建 vs 岛式最小构建"的能力差异,防止误读)。
4. **spec 修改授权与记账**:构建用 spec 为新建
   `packaging/ffmpeg-musl-demo.spec`(消费 §二 tarball,复用 demo 的
   musl/mimalloc 构建基础设施);如需修改 Tizen 原 spec 内容(如补丁路径、
   %prep 细节)以适配,**允许直接改,但每处修改单独记入 C8b 账本**
   (修改点、原文、新文、理由),不允许无记账的顺手修改。

## 四、变体矩阵(沿用)

| ID | libc | 分配器 | 链接 |
|---|---|---|---|
| F1 | glibc(chroot) | ptmalloc | 动态(基线) |
| F2 | musl 1.2.5 | mallocng | 静态 |
| F3 | musl 1.2.5 | mimalloc 2.1.7 | 静态 |

同一 chroot clang 22.1.8(版本闸门)、同一归一化 %optflags;musl 侧经
既有 musl-clang wrapper(start-group 补丁与门禁沿用);F3 的 mimalloc.o
以 musl 头环境编译(既有规则),`--extra-libs="<绝对路径>/mimalloc.o"`
入链。canonical 规则沿用:性能与内存测 baseline+stripped;
gc-sections(三变体对称)仅入体积矩阵。musl/mimalloc tarball 复用
packaging/ 现有 .frozen 与冻结哈希。

## 五、软解锁死:三层物理排除(最高优先级约束)

**L1 构建期物理排除**(三变体同一份参数,全文进
`share/ffmpeg-configure-commands.txt`):
```text
--disable-everything --disable-autodetect --disable-doc --disable-network
--disable-hwaccels --disable-v4l2-m2m --disable-mmal --disable-omx
--disable-vaapi --disable-vdpau
--enable-decoder=h264            # 仅原生软解;严禁 h264_v4l2m2m / h264_mmal
--enable-demuxer=mov --enable-parser=h264 --enable-protocol=file
--enable-ffmpeg --disable-ffprobe --disable-ffplay --disable-avdevice
（-f null 输出所需的最小 avfilter/swscale 依赖按 configure 实测确定,
 三变体必须一致;确定过程记录进日志）
```
**L2 configure 等价性门禁(任一不符退非零)**:
1) `Enabled hwaccels:` 段为空;2) `Enabled decoders:` 精确 = `h264`;
3) 三变体 configure 输出的 decoders/demuxers/parsers/protocols/hwaccels
与 **ARM 架构优化段(NEON/VFP 全表)** 逐字节 diff 为空——asm 静默关闭
即作废;4) 产物 `-decoders` 输出 h264 行仅原生项(host 不可执行则移板端
smoke,标注位置)。
**L3 运行期证据**:benchmark 显式 `-c:v h264`;每轮归档解码器名与
[bench] 原文;任一轮 utime 低于三变体中位数 50% → INVALID 并停车
(硬解泄漏/短路信号,不得静默剔除)。

## 六、构建门禁(沿用 + 扩展)

新 spec 安装至 `/opt/usr/ffmpeg-demo/`,不碰系统路径。ELF 门禁:
F2/F3 静态、无 INTERP/NEEDED/GLIBC_;F1 系统 loader + NEEDED 白名单
(ffmpeg 预期 libm/libpthread,据 readelf 实况扩展并记录依据)。
F3 三件套沿用:LFS64 扫描、map 中 malloc 定义方=mimalloc.o 且 musl
分配器成员零抽取、板端横幅一正二负。SourceN 前置存在性检查沿用。
体积矩阵 {F1,F2,F3}×{baseline,gc-sections}×{unstripped,stripped} 十二格。

## 七、测量(run_board_ffmpeg.sh;门控、哨兵沿用)

素材:**已由 FatTank 预置于板端 `/root/` 目录**。处理规则:
`ls /root` 定位媒体文件(mp4/h264/mkv 后缀);恰好一个 → 采用,
复制到 `/opt/usr/ffmpeg-demo/data/` 并在**首次使用时**计算 sha256 冻结进
`packaging/ffmpeg-testclip.sha256`(此后每轮校验该值);零个或多个候选 →
停车报告文件清单,不得自行猜测。素材属 PerfHotSpotAnalyzer 同源 h264
样本,交叉验证段以其为锚。

| 项 | 内容 | 样本 |
|---|---|---|
| decode | `-benchmark -c:v h264 -i $CLIP -f null -`;utime/stime/rtime/maxrss | ≥10 轮/变体,轮内交替,配对中位数 |
| 启动 | timer 交替三元组 `ffmpeg -version` | 30 轮 |
| 内存 | 解码中(第 5 秒)smaps_rollup ×3 + maxrss | 3 次/变体 |
| 功能面 | F2 符号表对 strcoll/iconv/setlocale/getaddrinfo 引用扫描 | 一次 |

温控加严:轮间 30s 冷却;轮前温度 >65°C 等待;逐轮 cur_freq 检查,
降频样本 INVALID。结果落 `results/results-ffmpeg.txt`(新文件)。`SDB_TARGET` 默认 <BOARD_IP>(参数化,可覆盖)。

## 八、判据预冻结(FatTank 签字后执行)

G 层:全部构建门禁 + configure 等价性 + 软解 L1–L3 + 补丁一致性 +
样本完整性(G4 语义沿用)。
E 层:
```text
E-P 性能(等价性判定,核心):delta = 配对相对差中位数(utime)
  |delta| ≤ 2% → EQUIVALENT(与"提升"同等有效,报告明写)
  2–5% → INCONCLUSIVE;>5% → 按方向 REGRESSION/IMPROVEMENT
E-M 内存:PD/Pss/maxrss 逐项;F3 vs F2 溢价单列(micro 外推验证点)
E-S 体积:双口径 + gc-sections 收益单列(demo 欠账落地)
E-C 修改量:C8a = Tizen 补丁系列之外的 ffmpeg 源码 diff,= 0 → favorable,
  非零逐行列出;C8b = spec/构建集成修改,逐项记账(这就是迁移成本数据,
  预期非零,不判优劣只判"有无语义性 workaround")
E-F 功能面:四态出口
```

## 九、报告与交付

`results/report-ffmpeg.md`:溯源摘要(版本/commit/补丁数)/方法/软解
三层证据/E 表(绝对值、差值、n、median、p10/p95)/与 PerfHotSpotAnalyzer
基线交叉验证段/Tizen 完整构建 vs 岛式最小构建能力差异附录/Caveats
(岛式边界、单素材、单板、源码保密形态)。
验收:溯源勾选闸门实际拦截过(勾选前退非零证据)、补丁一致性 diff 空、
configure 等价 diff 空、三层软解证据齐、横幅一正二负、C8a/C8b 账本完整、
每格 evidence 指针、NOT_RUN+补跑命令。完成后停止等待数据核验。

## 十、FatTank 前置准备

- [ ] 冻结 commit 审核勾选(Codex 克隆并生成 provenance 后)
- [x] 板端目标已确认:<BOARD_IP> = 原 .25 的 RPI4(仅 IP 变更),部署与 Smack 预期照旧
- [x] E-P 等价带 2%/5% 已确认
- [x] 板端当前空闲,可全程执行
