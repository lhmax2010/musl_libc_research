# Scudo standalone source freeze

- LLVM tag: `llvmorg-22.1.8`
- LLVM commit: `ca7933e47d3a3451d81e72ac174dcb5aa28b59d1`
- Source subtree: `compiler-rt/lib/scudo/standalone`
- Frozen archive: `packaging/scudo-standalone-22.1.8.tar.gz.frozen`
- SHA-256: `1364a53c57a0829cfcdd5596ae9c8aef173e32959c731b54116f41ac184788c0`

The archive contains only the standalone Scudo subtree, its LLVM license, and
files recording the exact tag and commit. It was made from a sparse checkout
of the official `https://github.com/llvm/llvm-project.git` repository.

This source is attempted as the optional S6 variant. Any C++ runtime friction
is recorded verbatim and downgrades S6 to P1 without expanding the task into a
libc++ environment build.
