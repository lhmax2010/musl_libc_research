# Codex 实现 Prompt v3:GBS 构建的 musl vs glibc 快速 Demo(RPI4 / Tizen armv7l)

你是一名资深 Tizen/GBS/RPM/交叉编译工程师。请在当前仓库(`~/Toolchain/development/musl-libc-research`)实现一个完整、可复现的 musl libc 对比 demo:**所有对比二进制由 GBS 在 Tizen chroot 内构建并打成 RPM**,部署到 RPI4 板端运行测量,生成对比报告。

当前仓库实际内容(以此为准,不要假设其他文件存在):

```text
musl-quick-demo/          # 已有探针与脚本,作为基础复用
  micro.c                 # 探针:startup|mem|threads N|malloc T ITERS|dns NAME|locale
  timer.c                 # fork+exec 计时器(测量仪器)
  gen_report.py           # 报告生成器(需按 §2.4 改造)
  run_board.sh            # 板端测量流程(需按 §2.3 改造)
  build.sh micro_cpp.cpp  # 本任务不使用,不要删除
config/gbs_llvm.conf      # 用户的 GBS 配置(LLVM profile)
musl-quick-demo.zip tmp/  # 忽略
```

遇到与预期不符的情况:**停下、报告、等待指示,禁止自行绕过或修改判定逻辑**。

---

## 一、核心设计(最高优先级,不得偏离)

### 1.0 musl 源码获取与完整性验证(host 侧,GBS 之外,全自动)

实现 `scripts/fetch_musl.sh`,按以下协议建立信任根(多源交叉共识,无需人工核对):

```text
1. 幂等短路:packaging/musl-1.2.5.tar.gz 存在且与 scripts/musl-1.2.5.sha256
   冻结值一致 → 直接成功。
2. 从官方 https://musl.libc.org/releases/musl-1.2.5.tar.gz 下载,
   计算 sha256 / sha1 / sha512 三个摘要。
3. 独立佐证源(逐个获取,原文归档 results/logs/hash-sources/):
   S1 musl 作者仓库(权威度最高):
      https://raw.githubusercontent.com/richfelker/musl-cross-make/master/hashes/musl-1.2.5.tar.gz.sha1
      → 比对 sha1
   S2 Alpine aports(musl 的主用发行版):
      https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/main/musl/APKBUILD
      → 解析 sha512sums 中 musl-1.2.5.tar.gz 条目,比对 sha512
      (若 master 已升版无 1.2.5 条目,则在 aports git 历史中定位含 1.2.5 的
       APKBUILD 版本,记录所用 commit/URL)
   S3 Buildroot:package/musl/musl.hash 的 1.2.5 sha256 条目
      (master 无则同法查历史,记录 commit/URL)
   S4 官方 GPG 签名(尽力而为,非必需):
      下载 musl-1.2.5.tar.gz.asc,从 musl.libc.org 页面获取发布密钥指纹,
      gpg --verify;成功与否均记录。
4. 判定:官方下载物的摘要获得 ≥2 个独立佐证源确认 → 通过;
   将 sha256 冻结写入 scripts/musl-1.2.5.sha256(后续构建只对冻结值校验)。
   任一已获取佐证源不一致、或可获取佐证源 <2 → 删除下载物,
   打印全部 expected/actual,退非零,停下报告,禁止继续。
5. 参考值交叉:此前记录的参考哈希
   a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
   仅作 advisory 对照;与共识值不一致时同样停下报告(该信号本身值得调查)。
6. 全部证据(各源原文、URL、时间、判定结果)写入 results/logs/fetch-musl.log。
```

**信任根声明(写入 README)**:信任根 = 上述多源共识协议及其归档证据;FatTank 的审核动作从"人工核对哈希"简化为"查看 fetch-musl.log 确认 ≥2 源一致"。GBS `%build` 无网络,下载只发生在本脚本;spec 内对 Source1 以冻结值二次校验(双点校验)。

### 1.1 三变体,同一编译器

同一 spec 的 `%build` 内产出三个二进制,全部使用 **chroot 内同一个编译器**:

```text
micro.glibc-dyn    : 编译器 + glibc,动态(现状基线)
micro.musl-static  : musl wrapper(调同一编译器),-static
micro.musl-dyn     : musl wrapper,动态,--dynamic-linker 指向包内 loader
```

musl 工具链构建(唯一允许方式):`%build` 内解包 Source1,
`./configure --prefix=$PWD/musl-inst && make -j && make install`,得到 wrapper 与 `musl-inst/lib/libc.so`。

**编译器规则(本 demo 验证的是 LLVM 工具链下的 musl 替换,clang 是唯一合法编译器)**:
```text
三变体统一使用 chroot 内平台 clang(LLVM profile 默认编译器)。
musl 本体以 CC=clang 构建;CC 为 clang 时 musl configure 会安装
tools/musl-clang 与 ld.musl-clang wrapper(musl-inst/bin/ 下),
musl 两变体经该 wrapper 编译链接(两个 wrapper 脚本需同时在 PATH)。
若 wrapper 路线受阻,备选:clang 直连显式参数
(-nostdinc -isystem musl-inst/include、-nostdlib + musl crt1.o + -lc),
换路线前先停下报告现象。
禁止使用 gcc 构建任何对比变体;chroot 无可用 clang → 停下报告,
不得引入外部工具链。
runtime builtins 库(--rtlib=compiler-rt 或 libgcc.a)三变体必须一致,
实际选择与 clang -print-runtime-dir / -print-libgcc-file-name 输出
写入 results/logs/compiler-decision.txt(含 clang 版本原文)。
chroot clang 版本预期为 22.1.8(平台当前 LLVM 版本);
实际版本不一致 → 停下报告等待指示,不得静默继续,
因为"结论适用于平台 LLVM 语境"的声明依赖版本一致。
```

### 1.2 编译参数

三变体统一 `%optflags` 原文(展开值记录),仅链接参数按变体不同:musl-static 追加 `-static`;musl-dyn 追加 `-Wl,--dynamic-linker=/opt/usr/musl-demo/lib/ld-musl-armhf.so.1`,必要时 `-static-libgcc`。三条完整命令行原文进 `share/build-commands.txt`。

### 1.3 %build 内机械门禁(fail-closed,任一失败 rpmbuild 退非零)

```text
Source1 sha256 == 冻结值(spec 内二次校验)
micro.musl-static: file=statically linked;readelf -l 无 INTERP;-d 无 NEEDED;无 GLIBC_ 符号/字符串
micro.musl-dyn   : INTERP 精确 == /opt/usr/musl-demo/lib/ld-musl-armhf.so.1;NEEDED 仅 libc.so;无 libgcc_s.so.1
micro.glibc-dyn  : INTERP 为系统 loader;NEEDED 无意外条目
三变体           : readelf -h/-A 为 ARM 32-bit hard-float
```

### 1.4 RPM 布局(不碰系统路径)

```text
Name: musl-libc-demo
/opt/usr/musl-demo/bin/{micro.glibc-dyn,micro.musl-static,micro.musl-dyn,timer}
/opt/usr/musl-demo/lib/libc.so
/opt/usr/musl-demo/lib/ld-musl-armhf.so.1 -> libc.so
/opt/usr/musl-demo/share/{build-commands.txt,artifacts.sha256,sizes-prestrip.txt}
```

禁止:%post ldconfig、写 /lib /usr/lib /etc、任何系统 libc 相关 Provides/Conflicts。timer 以 glibc 动态构建(仪器,不进对比)。二进制 strip,strip 前大小记录。

---

## 二、实现步骤

### Phase 0: 取源
`scripts/fetch_musl.sh` 按 §1.0;失败即全停。

### Phase 1: spec 与 GBS 构建
`packaging/musl-libc-demo.spec` 按 §1 实现;构建命令(README 写清,profile 取自 config/gbs_llvm.conf):
```bash
gbs -c config/gbs_llvm.conf build -A armv7l --include-all
```
日志存 `results/logs/gbs-build.log`。chroot 内编 musl 约 10–25 分钟属正常,不得因慢换路线。

### Phase 2: 部署
`scripts/deploy.sh`:sdb connect(`SDB_TARGET` 默认 192.168.108.25)→ root on → push RPM → `rpm -Uvh --force` → 板端 `sha256sum /opt/usr/musl-demo/bin/*` 与 host 比对,不一致即停 → 三变体无参 smoke(musl-dyn 跑通即证明包内 loader 生效)。rpm 安装失败:原样报告错误输出(含 Smack/只读分区线索),等待指示,不自行改用其他安装方式。

### Phase 3: 测量(改造 musl-quick-demo/run_board.sh → scripts/run_board.sh)
门控:governor 全核 performance;测前测后记温度与 `scaling_cur_freq`,`cur_freq < max_freq` 的轮标 INVALID;全部绝对路径调用。

```text
sizes   : 板端 ls -l 三变体 + libc.so
startup : timer 交替三元组 x 30 轮,输出 startup_triple,i,<glibc>,<musl_static>,<musl_dyn>
mem     : 各变体 mem 模式 smaps_rollup(Rss/Pss/Private_*)x3
threads : 各变体 threads 200(VmSize/VmRSS/Threads)
malloc  : {1,4} 线程 x 2000000 x 5 轮,轮内按变体交替
dns     : 各变体 dns localhost / dns www.tizen.org;板端 resolv.conf 原文归档,不修改
locale  : 各变体 default 与 LC_ALL=ko_KR.UTF-8
```
结果落 `results/results.txt`(key=value 格式沿用)。

### Phase 4: 报告
改造 `gen_report.py`:startup 解析三元组,输出两组配对 delta——musl-static vs glibc-dyn(方案差异)、musl-static vs musl-dyn(链接方式贡献);malloc 表加 musl-dyn 列。报告固定 Caveats 章(不得删):单板/单日/样本量;同一编译器(平台 clang,与 Tizen LLVM 生产工具链一致)与同一 %optflags,编译器混淆已消除且结论直接适用于平台 LLVM 语境,剩余变量 = libc + 链接方式;builtins 运行库选择(compiler-rt 或 libgcc.a)三变体一致性声明;musl 结构性限制(ABI 孤岛、静态无 dlopen、忽略 nsswitch、locale 基本仅 C/C.UTF-8)。输出 `results/report.md`。

---

## 三、编码与工程红线

shell:`set -euo pipefail`、全引号、trap 清理、无 killall、失败必非零、不静默跳过。spec:门禁失败必须让 rpmbuild 退非零。不硬编码用户名/家目录;IP 与 profile 走变量/配置。python 仅标准库,不改原始 results.txt。环境缺失(网络、GBS、板):完成全部代码,给出精确待执行命令,对应步骤 NOT_RUN,禁止伪造成功。

## 四、验收(逐条自证)

```text
[  ] fetch_musl.sh:≥2 独立源共识达成,hash-sources/ 原文归档;篡改测试(改一字节)确认能拦截并退非零
[  ] gbs build 成功,三变体 + libc.so 进 RPM;compiler-decision.txt 存在且确认全程 clang、rtlib 三变体一致
[  ] %build 门禁全部实际执行(贴日志片段)
[  ] 板端 smoke:musl-dyn 经包内 loader 运行成功
[  ] startup_triple 30 轮完成(INVALID 轮列明原因)
[  ] malloc/threads/mem/dns/locale 数据齐
[  ] report.md 含两组配对 delta 与完整 Caveats
[  ] 未执行项 NOT_RUN + 原因 + 精确补跑命令
```

最后给出:实现摘要、新增/修改文件列表、已执行命令、结果摘要、已知限制、下一步建议。必须真正提交实现,不要只描述方案。
