# mimalloc 2.1.7 source review gate

- [x] FatTank verified the frozen mimalloc digest and archived corroborating records.

Formal GBS build is fail-closed until FatTank changes the checkbox above to
`[x]`. Automation must not check it on FatTank's behalf.

## Frozen artifact

- URL: `https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.7.tar.gz`
- SHA-256: `0eed39319f139afde8515010ff59baf24de9e47ea316a315398e8027d198202d`
- SHA-512: `4e30976758015c76a146acc1bfc8501e2e5c61b81db77d253de0d58a8edef987669243f232210667b32ef8da3a33286642acb56ba526fd24c4ba925b44403730`

## Independent records

- vcpkg commit `d8e2b83a6b6981e7e019b9b6ad8884be1765720a`, version
  `2.1.7`, publishes the same SHA-512 in `ports/mimalloc/portfile.cmake`.
- Conan Center Index commit
  `a8ab0ecbeaa1eeba447d8fccda1c43f110cdbdc3`, version `2.1.7`, publishes
  the same SHA-256 in `recipes/mimalloc/all/conandata.yml`.

Raw records and the mechanical verdict are archived in
`results/logs/mimalloc-hash-sources/` and `results/logs/fetch-mimalloc.log`.
