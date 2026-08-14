# Incident: HQ reproduction package confidentiality gate

## Status

`RESOLVED-BY-RULING`. Phase 1 originally parked before release preparation; the
FatTank ruling below authorizes Phase 2–6 to continue without sanitizing existing
history or evidence.

## Scope and method

The scan covered the current worktree, including untracked text files, and every
commit reachable through `git rev-list --all`. Binary files, `tmp/**`, and
`musl-quick-demo.zip` were excluded as required. `gitleaks` was unavailable, so
the fallback used `rg` for the worktree and `git grep` for every revision. The
rules, commands, counts, complete matches, classification, and a corrected URL
rescan are preserved in `results/logs/repro-confidentiality-scan.log`.

## Findings

- No precise credential indicator was detected in the worktree or history. The
  checks covered private-key headers, common GitHub/AWS/Slack token forms, and
  credentials embedded in URLs.
- Generic credential-term matches were inspected as parser/source identifiers,
  documentation wording, or scan-rule text; no credential value was confirmed.
- Personal host paths are present in the current tracked evidence and in Git
  history. In particular, paths rooted at
  `/home/linhao/Toolchain/development/musl-libc-research` expose a personal host
  account name. The scan recorded 4,022 worktree matches and 16,652
  history-revision matches for `/home/<user>` paths. `/home/abuild` chroot paths
  are also matched, but the independently confirmed `/home/linhao` paths are
  sufficient to fail the gate.
- The host name `linhao-linux` occurs in tracked GBS logs and in Git history and
  is treated as a non-public host identifier.
- The observed URLs were classified as public upstream or project endpoints;
  no private URL was confirmed. The first URL expression was rejected by
  ripgrep, so the log records that error and contains a complete rescan with a
  corrected expression.
- `BOARD_RPI4` occurs in logs/evidence. This is not a blocker because the
  authorization explicitly permits private board addresses in evidence. No new
  guide or configuration template was created.

## Disposition

The original scan artifact has SHA-256
`12dcb7eef85e604338c7a3ebbdb5f2f1af12b26c41c0ce332636dc253dd19d9d`.
It confirmed zero findings in the sensitive categories that the gate was meant
to prevent: credentials, private keys, tokens, and private URLs. The remaining
personal-path and host-name findings are accepted by the following ruling.

### FatTank ruling (verbatim)

> 保密门禁裁决——保留个人路径与主机名，继续 Phase 2–6
>
> 个人路径 `/home/linhao` 与主机名 `linhao-linux` 保留，不做任何历史或
> 工作树脱敏。依据三条：
>
> 1. 仓库本就挂在公开个人账号下，路径/主机名零新增暴露；真正敏感类别
>    （凭据/私钥/Token/私有 URL）扫描零命中，门禁拦截目标已确认干净。
> 2. 历史重写将使全部 commit SHA 失效，摧毁 incident 归档、审计日志与
>    报告 evidence 指针构成的证据链——该证据链是复现包核心资产。
> 3. 仓库已公开，重写不构成事实撤回。
>
> 面向未来的 `TEST_PLAN_EN.md`、`REPRODUCTION_EN.md`、
> `ACCEPTANCE_EN.md` 与一切配置模板中，路径一律参数化为 `$HOME`、
> `$REPO_ROOT`、`$SDB_TARGET`，不出现具体个人路径。参数化只约束新文档，
> 不回改任何既有日志与证据。
>
> `REPRODUCTION_EN.md` 必须说明：Historical logs and evidence intentionally
> retain the original operator environment paths; sanitizing them would rewrite
> commit history and invalidate the SHA-anchored evidence chain.
>
> 禁止任何形式的历史改写（包括 filter-repo、BFG 与 force-push）。按原
> prompt 顺序继续执行 Phase 2–6；新的未预授权失败照旧停车。

### Resolution

Status is `RESOLVED-BY-RULING`. Existing logs, evidence, and Git history remain
byte-for-byte unchanged. Future-facing reproduction documents and configuration
templates must parameterize operator paths and the board target. History rewrite
and force-push are prohibited. Phase 2–6 may proceed under this ruling.
