# musl-static + mimalloc 第四变体实测报告

> 状态：NOT_RUN。mimalloc 来源摘要机械校验通过，但 FatTank 人工审核框尚未勾选；正式 GBS 构建按授权停在 fail-closed 闸门之前。

## 当前证据

- 官方 v2.1.7 SHA-256：`0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`
- vcpkg SHA-512：PASS
- Conan Center SHA-256：PASS
- 独立佐证数：2
- `packaging/micro.c` / `packaging/timer.c`：逐字节不变
- 原始 `results/results.txt`：逐字节不变

## 未执行项

| 项目 | 状态 | 原因 | 补跑命令 |
|---|---|---|---|
| GBS 第四变体构建与机械门禁 | NOT_RUN | FatTank 来源审核未勾选 | `scripts/build_gbs.sh` |
| RPM 部署与四方横幅门禁 | NOT_RUN | 尚无审核后 RPM | `scripts/deploy.sh` |
| 四变体同会话实测 | NOT_RUN | 尚无审核后部署 | `SDB_TARGET=192.168.108.25 scripts/run_board.sh` |
| malloc 四方表 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| startup_quad 30 轮 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |
| 内存代价四项 | NOT_RUN | 尚无 `results/results-mimalloc.txt` | 同上 |

DNS 与 locale 按设计不在本轮复测；数据生成后将明确标注沿用前轮。

当前不填充数据结论模板，不作“已追平/未追平”判断。
