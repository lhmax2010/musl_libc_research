# Third-party notices

This reproduction package incorporates or builds the following third-party
components. The archived source tarballs are integrity-pinned under
`packaging/`; the corresponding license texts are distributed under
`LICENSES/`.

| Component | Version | Use in this package | License |
|---|---:|---|---|
| musl libc | 1.2.5 | Private static libc and private dynamic loader/libc for the comparison probes | MIT, with compatible third-party notices described in `LICENSES/musl-COPYRIGHT.txt` |
| mimalloc | 2.1.7 | Link-time allocator override in `micro.musl-mi` | MIT; see `LICENSES/mimalloc-LICENSE.txt` |

Tizen, GBS, clang, glibc, and the target operating-system components are build
or runtime prerequisites; their source is not redistributed by this package.
