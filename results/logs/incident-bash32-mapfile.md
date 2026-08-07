# Incident: Bash 3.2 lacks mapfile

Date: 2026-08-06

## Symptom

After GBS export and the frozen Source1 gate passed, the chroot build stopped
before runtime-library selection:

```text
./build-demo.sh: line 54: mapfile: command not found
```

The Tizen chroot installs Bash 3.2.57. The `mapfile` builtin was added in Bash
4.0, so the original candidate-collection syntax was outside the target shell
baseline.

## Authorized fix

Commit `1f99c6d` replaced the single `mapfile` call with a Bash 3.2-compatible
indexed array and while-read loop. Empty output still produces an empty array,
and candidate ordering still follows `sort`. No gate condition, threshold, or
runtime-library policy changed.

The required compatibility scan produced:

```text
self_check.command=grep -nE 'mapfile|readarray|declare -A|coproc|&>>|\$\{[A-Za-z_]+(\^\^?|,,?)[}]?' packaging/build-demo.sh
self_check.exit_code=1
self_check.output=<no matches>
```

Lesson: the shell version inside the target chroot, not the host shell version,
must define the syntax baseline for scripts executed during RPM builds.

## Rerun evidence

The next GBS run passed the former failure point and recorded:

```text
expected_clang_version=22.1.8
selected_rtlib=libgcc.a
glibc_dyn_rtlib=libgcc.a
musl_static_rtlib=libgcc.a
musl_dyn_rtlib=libgcc.a
rtlib_consistency=PASS
```

musl then built and installed successfully. The build later stopped while
linking `micro.musl-static` because ARM EABI division builtins remained
undefined. That new failure was not pre-authorized and is recorded separately.
