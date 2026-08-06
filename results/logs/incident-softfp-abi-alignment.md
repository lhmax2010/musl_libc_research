# Incident: demo ABI assumption did not match Tizen armv7l

Date: 2026-08-06

## Phenomenon

The previous rerun built all three variants and passed the musl-static gate,
then stopped at the musl-dynamic interpreter gate:

```text
BUILD_GATE_FAIL: musl-dyn interpreter expected=/opt/usr/musl-demo/lib/ld-musl-armhf.so.1 actual=/opt/usr/musl-demo/lib/ld-musl-arm.so.1
```

## Root cause

The upstream design assumed a hard-float ABI and encoded an `armhf` loader name
plus a `VFP registers` ELF-attribute gate. The actual Tizen armv7l platform ABI
in this GBS profile is softfp: `%optflags` includes `-mfloat-abi=softfp` and
`-D__SOFTFP__`, and musl correctly reports `__ARM_PCS_VFP=false` and generates
`ld-musl-arm.so.1`. This was a design-assumption error, not an implementation
error.

## Authorized disposition

The demo is aligned to the platform softfp ABI. The private loader name is
`ld-musl-arm.so.1` throughout active packaging and deployment code. The former
hard-float tag gate is replaced by a fail-closed consistency gate that:

1. preserves the ELF32 and ARM assertions for all three variants;
2. records each variant's exact `Tag_ABI_VFP_args` line, or `ABSENT`;
3. rejects `VFP registers` on any variant;
4. records and compares the chroot `/bin/sh` tag with every variant; and
5. writes `platform_float_abi`, `variant_vfp_args`, `binsh_vfp_args`, and
   `abi_consistency` to `compiler-decision.txt` before failing on a mismatch.

The compiler flags are not changed to hard-float because that would break
comparability with platform glibc and detach the experiment from the board ABI.
Runtime-library selection, `COMMON_FLAGS`, the three variant build structures,
and all other ELF gates remain unchanged.

## Lesson

ABI assertions must be derived from measured platform artifacts and active
toolchain flags, not from the design author's memory. The rerun result will be
appended after the authorized fix is committed and executed.
