# musl-static + mimalloc 第四变体实测报告

> 状态：NOT_RUN。mimalloc 来源摘要及 FatTank 审核、Source6 修复与前置检查均通过；`mimalloc.o` 已按授权切换至 musl wrapper，但正式 GBS 构建因找不到 clang 的 `stdatomic.h` 而停车，尚未生成 release 2 RPM。

## 当前证据

- 官方 v2.1.7 SHA-256：`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`
- vcpkg SHA-512：PASS
- Conan Center SHA-256：PASS
- 独立佐证数：2
- FatTank 来源审核：PASS
- Source0--Source6 前置检查：PASS
- Source1 / Source5 双哈希门禁：PASS
- musl wrapper / 原 `$OPTFLAGS`：已进入实际编译命令
- mimalloc 对象编译：BLOCKED（`stdatomic.h` 未找到）
- LFS64 / 第四变体链接及后续门禁：NOT_REACHED
- 正式 GBS：BLOCKED
- `packaging/micro.c` / `packaging/timer.c`：逐字节不变
- 原始 `results/results.txt`：逐字节不变

## 未执行项

| 项目 | 状态 | 原因 | 补跑命令 |
|---|---|---|---|
| GBS 第四变体构建与机械门禁 | NOT_RUN | mimalloc 对象未编译完成；等待 clang 资源头文件兼容授权 | 授权修复后 `scripts/build_gbs.sh` |
| RPM 部署与四方横幅门禁 | NOT_RUN | 尚无 release 2 RPM | `scripts/deploy.sh` |
| 四变体同会话实测 | NOT_RUN | 尚无审核后部署 | `SDB_TARGET=192.168.108.25 scripts/run_board.sh` |
| malloc 四方表 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| startup_quad 30 轮 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| 内存代价四项 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |

DNS 与 locale 按设计不在本轮复测；数据生成后将明确标注沿用前轮。

当前不填充数据结论模板，不作“已追平/未追平”判断。

Source6 修复见 `results/logs/incident-mimalloc-source6-export.md`，mmap64 根因与已授权修复见 `results/logs/incident-mimalloc-mmap64-link.md`；当前停车事故原文及只读诊断见 `results/logs/incident-mimalloc-stdatomic-include.md`。
