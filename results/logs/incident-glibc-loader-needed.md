# Incident: platform loader in glibc probe `DT_NEEDED`

Date: 2026-08-06

## Trigger evidence

The first softfp-aligned rerun passed both musl variant gates, then the glibc
whitelist rejected `ld-linux.so.3`. Read-only inspection reported the complete
original `readelf -dW` lines:

```text
0x00000001 (NEEDED)                     Shared library: [libpthread.so.0]
0x00000001 (NEEDED)                     Shared library: [libc.so.6]
0x00000001 (NEEDED)                     Shared library: [ld-linux.so.3]
```

## Pre-authorized disposition

`docs/codex-prompt-continue-execution.md` explicitly pre-authorized adding an
observed platform-loader entry to the glibc-dynamic NEEDED whitelist, in its
own commit, followed by one build retry. Commit `676f0e3` added only
`ld-linux.so.3` to that case arm; no other gate or link command changed.

The retry passed:

```text
gate.micro.glibc-dyn=PASS interpreter=/lib/ld-linux.so.3
gate.arm32_softfp_abi_consistency=PASS
BUILD_GATE_PASS: all comparison artifacts passed
```
