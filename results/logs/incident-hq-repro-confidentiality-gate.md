# Incident: HQ reproduction package confidentiality gate

## Status

`PARKED` during Phase 1. No release preparation was attempted after the gate failed.

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
- `192.168.108.25` occurs in logs/evidence. This is not a blocker because the
  authorization explicitly permits private board addresses in evidence. No new
  guide or configuration template was created.

## Disposition

The confidentiality result is `FAIL`. Git history was not rewritten and no
existing evidence was edited or removed. The following work is `NOT_RUN`:

- merge of `execution/continue-20260806` into `main`;
- annotated tag `demo-v1.0-repro`;
- licenses, notices, example configuration, package-entry README, test plan,
  reproduction guide, acceptance document, and reference JSON;
- reproduction verifier, host dry run, board-command validation, and self-test;
- offline `git archive`, archive checksum, and release-tag push.

These phases can resume only after an explicit policy decision resolves whether
the historical personal paths and host name may remain in the HQ deliverable or
authorizes a specific sanitization strategy. After that decision, rerun the
complete Phase 1 scan using the rules and command forms recorded in
`repro-confidentiality-scan.log`; proceed to Phase 2 only if the result passes.
