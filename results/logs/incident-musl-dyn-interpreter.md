# Incident: musl-dynamic interpreter mismatch

Date: 2026-08-06

## Failure

After the wrapper group patch and musl-static ELF gate passed, the first new
unpreauthorized failure was:

```text
BUILD_GATE_FAIL: musl-dyn interpreter expected=/opt/usr/musl-demo/lib/ld-musl-armhf.so.1 actual=/opt/usr/musl-demo/lib/ld-musl-arm.so.1
```

`readelf -lW payload/bin/micro.musl-dyn` independently confirmed:

```text
[Requesting program interpreter: /opt/usr/musl-demo/lib/ld-musl-arm.so.1]
```

The binary is ARM EABI5 with `Tag_CPU_arch: v7` and `Tag_FP_arch: VFPv3`, but
its attributes do not contain `Tag_ABI_VFP_args`.

## Read-only evidence

The GBS profile expanded `%optflags` with:

```text
-march=armv7-a -mfpu=neon -mfloat-abi=softfp -Wp,-D__SOFTFP__
```

musl configure consequently logged:

```text
checking preprocessor condition __ARM_PCS_VFP... false
```

and generated its wrapper with:

```text
@LDSO@ -> /opt/usr/musl-demo/lib/ld-musl-arm.so.1
```

The unchanged musl-dynamic variant command did request:

```text
-Wl,--dynamic-linker=/opt/usr/musl-demo/lib/ld-musl-armhf.so.1
```

but `ld.musl-clang` appends its generated
`-dynamic-linker "$ldso"` later on the final real-linker invocation. The later
`ld-musl-arm.so.1` argument therefore determines the emitted `PT_INTERP`.

## Disposition

No interpreter, ABI flags, wrapper behavior, packaging path, or ELF gate was
changed because none was authorized by the current prompt. The GBS run was not
retried. It did not reach `BUILD_GATE_PASS` or RPM packaging; deploy,
`run_board`, and report generation remain `NOT_RUN` pending direction.
