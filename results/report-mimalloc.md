# musl-static + mimalloc 第四变体实测报告

> 状态：DATA_NOT_RUN / HOST_BUILD_PASS。release 2 RPM 及全部 host 机械门禁已通过；按本轮边界未部署、未运行板端、未填充性能数据。

## 当前证据

- 官方 v2.1.7 SHA-256：`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`
- vcpkg SHA-512：PASS
- Conan Center SHA-256：PASS
- 独立佐证数：2
- FatTank 来源审核：PASS
- Source0--Source6 前置检查：PASS
- Source1 / Source5 双哈希门禁：PASS
- musl wrapper / 原 `$OPTFLAGS` / clang resource fill：PASS
- `stdatomic.h` 前置断言：PASS（`/usr/lib/clang/22/include/stdatomic.h`）
- LFS64 整族未定义符号门禁：PASS（原始扫描为空）
- `__atomic_*` 未解析符号：0
- mimalloc 符号归属、ELF、softfp 门禁：PASS
- 正式 GBS：PASS（release 2）
- RPM SHA-256：`f55957aaca2968877e8cf4dc6bd017e7875a8ed7bd1783b067574fd2f4030ead`
- `packaging/micro.c` / `packaging/timer.c`：逐字节不变
- 原始 `results/results.txt`：逐字节不变

## 阶段状态

| 项目 | 状态 | 原因 | 补跑命令 |
|---|---|---|---|
| GBS 第四变体构建与机械门禁 | PASS | `BUILD_GATE_PASS`、`BUILD_GBS_PASS` | 已完成 |
| RPM 部署与四方横幅门禁 | NOT_RUN | 本轮仅授权 host，板端占用中 | 放行后 `scripts/deploy.sh` |
| 四变体同会话实测 | NOT_RUN | 尚未授权部署 | 放行后 `SDB_TARGET=192.168.108.25 scripts/run_board.sh` |
| malloc 四方表 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| startup_quad 30 轮 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| 内存代价四项 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |

DNS 与 locale 按设计不在本轮复测；数据生成后将明确标注沿用前轮。

当前不填充数据结论模板，不作“已追平/未追平”判断。

Source6 修复见 `results/logs/incident-mimalloc-source6-export.md`，mmap64 根因与修复见 `results/logs/incident-mimalloc-mmap64-link.md`，clang resource header 修复与验证见 `results/logs/incident-mimalloc-stdatomic-include.md`。
