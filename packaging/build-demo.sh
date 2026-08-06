#!/usr/bin/env bash
# Runs inside the GBS chroot from the spec's %build section.
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
    echo "usage: build-demo.sh MUSL_TARBALL FROZEN_SHA256 MICRO_C TIMER_C" >&2
    exit 2
fi

MUSL_TARBALL="$1"
FROZEN_SHA256_FILE="$2"
MICRO_SOURCE="$3"
TIMER_SOURCE="$4"
EXPECTED_CLANG_VERSION="22.1.8"
PRIVATE_ROOT="/opt/usr/musl-demo"
PRIVATE_LOADER="$PRIVATE_ROOT/lib/ld-musl-armhf.so.1"
BUILD_ROOT="$PWD"
MUSL_SOURCE_DIR="$BUILD_ROOT/musl-1.2.5"
MUSL_PREFIX="$BUILD_ROOT/musl-inst"
PAYLOAD="$BUILD_ROOT/payload"
COMMANDS="$PAYLOAD/share/build-commands.txt"
DECISION="$PAYLOAD/share/compiler-decision.txt"
PRESTRIP="$PAYLOAD/share/sizes-prestrip.txt"

fail() {
    echo "BUILD_GATE_FAIL: $*" >&2
    exit 1
}

for tool in bash clang file find getconf make readelf sha256sum strings tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "required chroot tool missing: $tool"
done

mkdir -p "$PAYLOAD/bin" "$PAYLOAD/lib" "$PAYLOAD/share"
: > "$COMMANDS"
: > "$DECISION"

expected_sha256="$(awk 'NF { print tolower($1); exit }' "$FROZEN_SHA256_FILE")"
actual_sha256="$(sha256sum "$MUSL_TARBALL" | awk '{print tolower($1)}')"
[[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid frozen Source1 sha256"
[[ "$actual_sha256" == "$expected_sha256" ]] || \
    fail "Source1 sha256 mismatch expected=$expected_sha256 actual=$actual_sha256"
echo "gate.source1_sha256=PASS value=$actual_sha256"

clang_path="$(command -v clang)"
clang_version_text="$(clang --version)"
if ! grep -Eq 'clang version 22\.1\.8([^0-9]|$)' <<< "$clang_version_text"; then
    printf '%s\n' "$clang_version_text" >&2
    fail "clang version mismatch: expected $EXPECTED_CLANG_VERSION"
fi

runtime_dir="$(clang -print-runtime-dir)"
libgcc_file="$(clang -print-libgcc-file-name)"
mapfile -t compiler_rt_candidates < <(
    find "$runtime_dir" -maxdepth 1 -type f \
        \( -name 'libclang_rt.builtins-arm*.a' -o -name 'libclang_rt.builtins.a' \) \
        -print | sort
)
if (( ${#compiler_rt_candidates[@]} > 0 )); then
    RTLIB_NAME="compiler-rt"
    RTLIB_FLAG="--rtlib=compiler-rt"
    RTLIB_ARCHIVE="${compiler_rt_candidates[0]}"
elif [[ -f "$libgcc_file" && "$(basename "$libgcc_file")" == "libgcc.a" ]]; then
    RTLIB_NAME="libgcc.a"
    RTLIB_FLAG="--rtlib=libgcc"
    RTLIB_ARCHIVE="$libgcc_file"
else
    fail "neither compiler-rt builtins nor static libgcc.a is available"
fi

{
    echo "expected_clang_version=$EXPECTED_CLANG_VERSION"
    echo "clang_path=$clang_path"
    echo "clang_dumpmachine=$(clang -dumpmachine)"
    echo "clang_runtime_dir=$runtime_dir"
    echo "clang_print_libgcc_file_name=$libgcc_file"
    echo "selected_rtlib=$RTLIB_NAME"
    echo "selected_rtlib_flag=$RTLIB_FLAG"
    echo "selected_rtlib_archive=$RTLIB_ARCHIVE"
    echo "musl_configure_CC=clang"
    echo "glibc_dyn_rtlib=$RTLIB_NAME"
    echo "musl_static_rtlib=$RTLIB_NAME"
    echo "musl_dyn_rtlib=$RTLIB_NAME"
    echo "rtlib_consistency=PASS"
    echo "clang_version_begin"
    printf '%s\n' "$clang_version_text"
    echo "clang_version_end"
} | tee "$DECISION"

rm -rf -- "$MUSL_SOURCE_DIR" "$MUSL_PREFIX"
tar -xf "$MUSL_TARBALL"
[[ -d "$MUSL_SOURCE_DIR" ]] || fail "Source1 did not unpack as musl-1.2.5"

OPTFLAGS_TEXT="${OPTFLAGS:?OPTFLAGS must contain the expanded rpm optflags}"
read -r -a OPTFLAGS_ARRAY <<< "$OPTFLAGS_TEXT"
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=1

(
    cd "$MUSL_SOURCE_DIR"
    CC=clang CFLAGS="$OPTFLAGS_TEXT $RTLIB_FLAG" \
        LDFLAGS="$RTLIB_FLAG -static-libgcc" \
        ./configure --prefix="$MUSL_PREFIX" \
        --syslibdir="$PRIVATE_ROOT/lib" --enable-wrapper=clang
    make -j "$jobs"
    make install
)

MUSL_CC="$MUSL_PREFIX/bin/musl-clang"
MUSL_LD="$MUSL_PREFIX/bin/ld.musl-clang"
[[ -x "$MUSL_CC" ]] || fail "musl-clang wrapper was not installed"
[[ -x "$MUSL_LD" ]] || fail "ld.musl-clang wrapper was not installed"
grep -Eq '^cc="?clang"?$' "$MUSL_CC" || fail "musl-clang does not invoke clang"
grep -Eq '^cc="?clang"?$' "$MUSL_LD" || fail "ld.musl-clang does not invoke clang"
export PATH="$MUSL_PREFIX/bin:$PATH"

record_and_run() {
    local arg
    {
        for arg in "$@"; do
            printf '%q ' "$arg"
        done
        printf '\n'
    } >> "$COMMANDS"
    "$@"
}

COMMON_FLAGS=("${OPTFLAGS_ARRAY[@]}" "$RTLIB_FLAG" -static-libgcc -pthread)
record_and_run clang "${COMMON_FLAGS[@]}" "$MICRO_SOURCE" \
    -Wl,-Map,"$BUILD_ROOT/micro.glibc-dyn.map" \
    -o "$PAYLOAD/bin/micro.glibc-dyn"
record_and_run "$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE" \
    -Wl,-Map,"$BUILD_ROOT/micro.musl-static.map" \
    -o "$PAYLOAD/bin/micro.musl-static"
record_and_run "$MUSL_CC" "${COMMON_FLAGS[@]}" "$MICRO_SOURCE" \
    -Wl,--dynamic-linker="$PRIVATE_LOADER" \
    -Wl,-Map,"$BUILD_ROOT/micro.musl-dyn.map" \
    -o "$PAYLOAD/bin/micro.musl-dyn"
record_and_run clang "${COMMON_FLAGS[@]}" "$TIMER_SOURCE" \
    -o "$PAYLOAD/bin/timer"

cp -- "$MUSL_PREFIX/lib/libc.so" "$PAYLOAD/lib/libc.so"

{
    for path in \
        bin/micro.glibc-dyn \
        bin/micro.musl-static \
        bin/micro.musl-dyn \
        bin/timer \
        lib/libc.so; do
        printf '%s %s\n' "$path" "$(stat -c '%s' "$PAYLOAD/$path")"
    done
} > "$PRESTRIP"

if command -v llvm-strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v llvm-strip)"
elif command -v strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v strip)"
else
    fail "no strip implementation available"
fi
echo "strip_tool=$STRIP_TOOL" >> "$DECISION"
for path in \
    "$PAYLOAD/bin/micro.glibc-dyn" \
    "$PAYLOAD/bin/micro.musl-static" \
    "$PAYLOAD/bin/micro.musl-dyn" \
    "$PAYLOAD/bin/timer" \
    "$PAYLOAD/lib/libc.so"; do
    "$STRIP_TOOL" --strip-unneeded "$path"
done

STATIC_BIN="$PAYLOAD/bin/micro.musl-static"
MUSL_DYN_BIN="$PAYLOAD/bin/micro.musl-dyn"
GLIBC_DYN_BIN="$PAYLOAD/bin/micro.glibc-dyn"

grep -q 'statically linked' < <(file "$STATIC_BIN") || fail "musl-static is not statically linked"
if grep -q 'INTERP' < <(readelf -lW "$STATIC_BIN"); then
    fail "musl-static unexpectedly contains PT_INTERP"
fi
if grep -q '(NEEDED)' < <(readelf -dW "$STATIC_BIN" 2>/dev/null); then
    fail "musl-static unexpectedly contains DT_NEEDED"
fi
if grep -q 'GLIBC_' < <(readelf --all --wide "$STATIC_BIN"); then
    fail "musl-static contains a GLIBC_ symbol"
fi
if grep -q 'GLIBC_' < <(strings -a "$STATIC_BIN"); then
    fail "musl-static contains a GLIBC_ string"
fi
echo "gate.micro.musl-static=PASS"

interpreter_of() {
    readelf -lW "$1" | sed -n 's/.*interpreter: \([^]]*\).*/\1/p'
}

needed_of() {
    readelf -dW "$1" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
}

musl_interp="$(interpreter_of "$MUSL_DYN_BIN")"
[[ "$musl_interp" == "$PRIVATE_LOADER" ]] || \
    fail "musl-dyn interpreter expected=$PRIVATE_LOADER actual=${musl_interp:-NONE}"
musl_needed="$(needed_of "$MUSL_DYN_BIN")"
[[ "$musl_needed" == "libc.so" ]] || \
    fail "musl-dyn DT_NEEDED must be exactly libc.so; actual=${musl_needed//$'\n'/,}"
if grep -q '^libgcc_s\.so\.1$' <<< "$musl_needed"; then
    fail "musl-dyn unexpectedly needs libgcc_s.so.1"
fi
echo "gate.micro.musl-dyn=PASS interpreter=$musl_interp needed=libc.so"

glibc_interp="$(interpreter_of "$GLIBC_DYN_BIN")"
[[ "$glibc_interp" == /lib/* ]] || \
    fail "glibc-dyn does not use a system /lib loader: ${glibc_interp:-NONE}"
glibc_needed="$(needed_of "$GLIBC_DYN_BIN")"
grep -q '^libc\.so\.6$' <<< "$glibc_needed" || fail "glibc-dyn does not need libc.so.6"
while IFS= read -r needed; do
    case "$needed" in
        libc.so.6|libpthread.so.0) ;;
        *) fail "glibc-dyn has unexpected DT_NEEDED: $needed" ;;
    esac
done <<< "$glibc_needed"
echo "gate.micro.glibc-dyn=PASS interpreter=$glibc_interp"

check_arm_hard_float() {
    local binary="$1"
    grep -Eq 'Class:[[:space:]]+ELF32' < <(readelf -hW "$binary") || \
        fail "$binary is not ELF32"
    grep -Eq 'Machine:[[:space:]]+ARM' < <(readelf -hW "$binary") || \
        fail "$binary is not ARM"
    grep -Eq 'Tag_ABI_VFP_args: VFP registers|ABI_VFP_args.*AAPCS VFP' \
        < <(readelf -AW "$binary") || \
        fail "$binary is not tagged ARM hard-float"
}

for path in "$GLIBC_DYN_BIN" "$STATIC_BIN" "$MUSL_DYN_BIN"; do
    check_arm_hard_float "$path"
done
echo "gate.arm32_hard_float_all_variants=PASS"

{
    echo "glibc_dyn_interpreter=$glibc_interp"
    echo "musl_dyn_interpreter=$musl_interp"
    echo "mechanical_gates=PASS"
} >> "$DECISION"

(
    cd "$PAYLOAD"
    sha256sum \
        bin/micro.glibc-dyn \
        bin/micro.musl-static \
        bin/micro.musl-dyn \
        bin/timer \
        lib/libc.so > share/artifacts.sha256
)

echo "BUILD_GATE_PASS: all comparison artifacts passed"
