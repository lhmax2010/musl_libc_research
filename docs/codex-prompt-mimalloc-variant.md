# Codex 增量 Prompt:第四变体 musl-static+mimalloc——多线程分配器补救实测

背景:已交付的 demo 中 musl mallocng 在 4 线程 malloc churn 下慢于 glibc 5.05×。
本轮验证行业标准补救:静态链接期以 mimalloc 替换分配器,回答两个问题:
(1) 多线程性能能追回多少;(2) 为此付出的内存代价是多少。
两个方向的数据同权重,不许只交性能不交代价。

在现有仓库 execution 分支上增量实现。前序全部纪律(fail-closed、停车报告、
原始数据只读、证据归档)继续有效。

## 一、公平性铁律(违反即本轮全部作废)

1. `src/micro.c` 与 `src/timer.c` 逐字节不变(git diff 必须为空,验收项)。
2. 新变体与 musl-static 除"链接期额外加入 mimalloc.o"外,编译命令逐参数相同。
3. 四变体测量在同一会话内交替执行,不复用旧会话的 malloc 数据做跨会话对比。

## 二、mimalloc 获取(host 侧,scripts/fetch_mimalloc.sh)

- 版本冻结:mimalloc v2.1.7(v2 稳定线),GitHub release tarball
  `https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.7.tar.gz`
- sha256 处理:下载后计算并冻结入 `scripts/mimalloc-2.1.7.sha256`;
  佐证源:vcpkg ports 与 conan center 对同版本的哈希记录(能取到则比对归档,
  取不到记 UNAVAILABLE);FatTank 审核勾选后方可正式构建,脚本只校验。
- spec 以 `Source5: mimalloc-2.1.7.tar.gz.frozen` 引入(.frozen 后缀沿用,
  规避 gbs orig 启发式;%prep 规范化回本名)。

## 三、构建(build-demo.sh 增量;既有三变体构建与门禁零改动)

1. mimalloc 编译走单文件汇聚路径,不引入 cmake:
   `clang $OPTFLAGS -O2 -DNDEBUG -DMI_MALLOC_OVERRIDE -I mimalloc-2.1.7/include \
        -c mimalloc-2.1.7/src/static.c -o mimalloc.o`
   (同一 chroot clang;若个别 %optflags 与 mimalloc 冲突导致编译失败,
   停车报告冲突 flag 原文,不自行删减。)
2. 第四变体:
   `$MUSL_CC ${COMMON_FLAGS[@]} -static micro.c mimalloc.o -o micro.musl-mi \
        -Wl,-Map,micro.musl-mi.map`
   mimalloc.o 作为目标文件在 -lc 之前进入链接,malloc/free/calloc/realloc/
   posix_memalign/aligned_alloc/malloc_usable_size 全族由其定义;
   musl libc.a 内部成员的分配调用同样解析到 mimalloc(map 文件中留证)。
3. RPM 增装 `/opt/usr/musl-demo/bin/micro.musl-mi`;
   build-commands.txt / artifacts.sha256 / sizes-prestrip.txt 同步。

## 四、门禁扩展(新增,既有门禁不动)

1. 结构门禁:micro.musl-mi 按 musl-static 同一套检查
   (statically linked、无 INTERP、无 NEEDED、无 GLIBC_、ARM32 softfp)。
2. 符号门禁:map 文件中 malloc 的定义方必须为 mimalloc.o,不得为 libc.a 成员;
   `nm micro.musl-mi` 含 mi_ 前缀符号。判定行原文进日志。
3. 运行期接管门禁(板端 smoke 阶段,防"链接了但没生效"的假阳性):
   `MIMALLOC_VERBOSE=1 ./micro.musl-mi malloc 1 1000` stderr 必须含 mimalloc 横幅;
   负对照:同环境变量下 glibc-dyn / musl-static / musl-dyn 三变体 stderr
   必须无该横幅。四条输出全部归档,任一不符即停车。

## 五、测量(run_board.sh 扩展;门控与哨兵机制沿用)

| 项 | 内容 |
|---|---|
| malloc | {1,4} 线程 × 2,000,000 × 5 轮,**四变体**轮内交替(核心数据) |
| mem | micro.musl-mi mem 模式 smaps_rollup ×3(内存代价:Pss / Private_Dirty / Rss)|
| threads | micro.musl-mi threads 200(VmSize——mimalloc 段预留在 32 位下的地址空间代价)|
| startup | 四元组交替 ×30(mimalloc 初始化对启动的影响)|
| sizes | 四变体 + libc.so 板端 ls -l(体积增量)|
| 不复测 | dns / locale(与分配器无关,报告标注沿用前轮)|

结果落 `results/results-mimalloc.txt`(新文件,不动既有原始文件),
startup 行格式 `startup_quad,i,<glibc>,<musl_static>,<musl_dyn>,<musl_mi>`。

## 六、报告(gen_report.py 扩展,输出 results/report-mimalloc.md)

1. malloc 四方表:ns/op(逐格 n)+ 两个关键比值:
   `mi/glibc`(追回程度)与 `mi/musl-static`(改善倍数)。
2. 内存代价表:musl-mi 相对 musl-static 的 Pss / Private_Dirty / VmSize /
   二进制体积四项增量(绝对值 + 倍数)。
3. startup 四方中位数(mimalloc 初始化开销单列)。
4. 结论段模板(数据填空,不加修饰):
   "t4:mallocng 976 → mimalloc <X> ns/op,为 glibc 的 <Y> 倍;
    代价:Private_Dirty 8 KB → <Z> KB,VmSize +<W>,二进制 +<V> KB。"
5. Caveats 沿用 + 新增:mimalloc 为第三方组件,引入版本/CVE 跟踪义务;
   mallocng 的堆加固属性随替换失去。

## 七、验收

```text
[  ] git diff src/micro.c src/timer.c 为空
[  ] 四变体编译命令 diff 仅 mimalloc.o 一项
[  ] 符号门禁 + 运行期横幅门禁(含三个负对照)全部 PASS,原文在档
[  ] malloc 四方表数据齐(每格 n≥5),startup_quad 30 轮
[  ] 内存代价表四项齐
[  ] report-mimalloc.md 生成;既有 results.txt 未被触碰(sha256 复核)
[  ] 未执行项 NOT_RUN + 原因 + 补跑命令
```

交付后停止,等待 FatTank 数据核验;不自行下"已追平/未追平"结论。
新的未预授权失败照旧停车。
