# rpmalloc 1.4.5 source review gate

- [ ] FatTank verified the frozen rpmalloc digest and archived corroborating records.

Formal GBS build is fail-closed until FatTank changes the checkbox above to
`[x]`. Automation must not check it on FatTank's behalf.

## Frozen artifact

- URL: `https://github.com/mjansson/rpmalloc/archive/refs/tags/1.4.5.tar.gz`
- Release: `https://github.com/mjansson/rpmalloc/releases/tag/1.4.5`
- Git tag commit: `e4393ff85585d91400bcbad2e7266c011075b673`
- SHA-256: `2513626697ef72a60957acc8caed17c39931a55c1a49202707de195742683d69`

## Independent package-manager record

- xmake-repo commit `34812a68d605778d664af2b70e03d17de93d731c`
  records rpmalloc version `1.4.5` with the same SHA-256 in
  `packages/r/rpmalloc/xmake.lua`.

The raw GitHub release record, xmake-repo record, and mechanical verdict are
archived in `results/logs/rpmalloc-hash-sources/` and
`results/logs/fetch-rpmalloc.log`.
