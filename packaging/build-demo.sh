#!/usr/bin/env bash
# Runs inside the GBS chroot from the spec's %build section.
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
    echo "usage: build-demo.sh MUSL_TARBALL MUSL_SHA256 MICRO_C TIMER_C MIMALLOC_TARBALL MIMALLOC_SHA256" >&2
    exit 2
fi

MUSL_TARBALL="$1"
FROZEN_SHA256_FILE="$2"
MICRO_SOURCE="$3"
TIMER_SOURCE="$4"
MIMALLOC_TARBALL="$5"
MIMALLOC_SHA256_FILE="$6"
EXPECTED_CLANG_VERSION="22.1.8"
PRIVATE_ROOT="/opt/usr/musl-demo"
PRIVATE_LOADER="$PRIVATE_ROOT/lib/ld-musl-arm.so.1"
BUILD_ROOT="$PWD"
MUSL_SOURCE_DIR="$BUILD_ROOT/musl-1.2.5"
MIMALLOC_SOURCE_DIR="$BUILD_ROOT/mimalloc-2.1.7"
MUSL_PREFIX="$BUILD_ROOT/musl-inst"
PAYLOAD="$BUILD_ROOT/payload"
COMMANDS="$PAYLOAD/share/build-commands.txt"
DECISION="$PAYLOAD/share/compiler-decision.txt"
PRESTRIP="$PAYLOAD/share/sizes-prestrip.txt"

fail() {
    echo "BUILD_GATE_FAIL: $*" >&2
    exit 1
}

for tool in bash clang file find getconf make nm readelf sha256sum strings tar; do
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

mimalloc_expected_sha256="$(awk 'NF { print tolower($1); exit }' "$MIMALLOC_SHA256_FILE")"
mimalloc_actual_sha256="$(sha256sum "$MIMALLOC_TARBALL" | awk '{print tolower($1)}')"
[[ "$mimalloc_expected_sha256" =~ ^[0-9a-f]{64}$ ]] || \
    fail "invalid frozen Source5 sha256"
[[ "$mimalloc_actual_sha256" == "$mimalloc_expected_sha256" ]] || \
    fail "Source5 sha256 mismatch expected=$mimalloc_expected_sha256 actual=$mimalloc_actual_sha256"
echo "gate.source5_sha256=PASS value=$mimalloc_actual_sha256"

clang_path="$(command -v clang)"
clang_version_text="$(clang --version)"
if ! grep -Eq 'clang version 22\.1\.8([^0-9]|$)' <<< "$clang_version_text"; then
    printf '%s\n' "$clang_version_text" >&2
    fail "clang version mismatch: expected $EXPECTED_CLANG_VERSION"
fi

runtime_dir="$(clang -print-runtime-dir)"
libgcc_file="$(clang -print-libgcc-file-name)"
compiler_rt_candidates=()
while IFS= read -r line; do
    compiler_rt_candidates+=("$line")
done < <(
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
    echo "musl_mi_rtlib=$RTLIB_NAME"
    echo "rtlib_consistency=PASS"
    echo "mimalloc_version=2.1.7"
    echo "mimalloc_source_sha256=$mimalloc_actual_sha256"
    echo "musl_ldso_name=ld-musl-arm.so.1"
    echo "clang_version_begin"
    printf '%s\n' "$clang_version_text"
    echo "clang_version_end"
} | tee "$DECISION"

rm -rf -- "$MUSL_SOURCE_DIR" "$MIMALLOC_SOURCE_DIR" "$MUSL_PREFIX"
tar -xf "$MUSL_TARBALL"
[[ -d "$MUSL_SOURCE_DIR" ]] || fail "Source1 did not unpack as musl-1.2.5"
tar -xf "$MIMALLOC_TARBALL"
[[ -d "$MIMALLOC_SOURCE_DIR" ]] || fail "Source5 did not unpack as mimalloc-2.1.7"

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

LDWRAPPER_BEFORE="$BUILD_ROOT/ld.musl-clang.before"
LDWRAPPER_PATCHED="$BUILD_ROOT/ld.musl-clang.patched"
cp -p -- "$MUSL_LD" "$LDWRAPPER_BEFORE"
echo "ldwrapper_before_begin"
cat "$LDWRAPPER_BEFORE"
echo "ldwrapper_before_end"

ldwrapper_before_line="$(grep '^exec ' "$LDWRAPPER_BEFORE" | tail -n 1)"
[[ -n "$ldwrapper_before_line" ]] || fail "ld.musl-clang has no exec linker line"
case "$ldwrapper_before_line" in
    'exec $($cc -print-prog-name=ld)'*) ldwrapper_style="ld" ;;
    'exec $cc '*|'exec "$cc" '*) ldwrapper_style="cc-driver" ;;
    *) fail "unrecognized ld.musl-clang exec style: $ldwrapper_before_line" ;;
esac
[[ "$ldwrapper_before_line" == *" -lc "* ]] || \
    fail "ld.musl-clang exec line has no standalone -lc"

group_rtlib_archive="$(readlink -f "$RTLIB_ARCHIVE")"
[[ -n "$group_rtlib_archive" && -f "$group_rtlib_archive" ]] || \
    fail "selected runtime archive cannot be canonicalized: $RTLIB_ARCHIVE"
group_rtlib_dir="$(dirname "$group_rtlib_archive")"
group_rtlib_eh=""
if [[ -f "$group_rtlib_dir/libgcc_eh.a" ]]; then
    group_rtlib_eh="$group_rtlib_dir/libgcc_eh.a"
fi

if [[ "$ldwrapper_style" == "ld" ]]; then
    ldwrapper_group_args="--start-group -lc $group_rtlib_archive"
    if [[ -n "$group_rtlib_eh" ]]; then
        ldwrapper_group_args="$ldwrapper_group_args $group_rtlib_eh"
    fi
    ldwrapper_group_args="$ldwrapper_group_args --end-group"
else
    ldwrapper_group_args="-Wl,--start-group -lc $group_rtlib_archive"
    if [[ -n "$group_rtlib_eh" ]]; then
        ldwrapper_group_args="$ldwrapper_group_args $group_rtlib_eh"
    fi
    ldwrapper_group_args="$ldwrapper_group_args -Wl,--end-group"
fi
ldwrapper_after_line="${ldwrapper_before_line/ -lc / $ldwrapper_group_args }"
[[ "$ldwrapper_after_line" != "$ldwrapper_before_line" ]] || \
    fail "ld.musl-clang -lc replacement made no change"

ldwrapper_replacements=0
while IFS= read -r wrapper_line || [[ -n "$wrapper_line" ]]; do
    if [[ "$wrapper_line" == "$ldwrapper_before_line" ]]; then
        printf '%s\n' "$ldwrapper_after_line"
        ldwrapper_replacements=$((ldwrapper_replacements + 1))
    else
        printf '%s\n' "$wrapper_line"
    fi
done < "$LDWRAPPER_BEFORE" > "$LDWRAPPER_PATCHED"
[[ "$ldwrapper_replacements" -eq 1 ]] || \
    fail "expected one ld.musl-clang linker line replacement, got $ldwrapper_replacements"
chmod 0755 "$LDWRAPPER_PATCHED"
mv -f -- "$LDWRAPPER_PATCHED" "$MUSL_LD"

echo "ldwrapper_after_begin"
cat "$MUSL_LD"
echo "ldwrapper_after_end"
echo "ldwrapper_diff_begin"
set +e
diff -u "$LDWRAPPER_BEFORE" "$MUSL_LD"
ldwrapper_diff_rc=$?
set -e
[[ "$ldwrapper_diff_rc" -eq 1 ]] || fail "unexpected ld.musl-clang diff status: $ldwrapper_diff_rc"
echo "ldwrapper_diff_end"

grep -Eq '^cc="?clang"?$' "$MUSL_CC" || fail "patched musl-clang does not invoke clang"
grep -Eq '^cc="?clang"?$' "$MUSL_LD" || fail "patched ld.musl-clang does not invoke clang"
{
    echo "ldwrapper_patch=start-group"
    echo "ldwrapper_style=$ldwrapper_style"
    echo "ldwrapper_group_rtlib_archive=$group_rtlib_archive"
    echo "ldwrapper_group_libgcc_eh=${group_rtlib_eh:-NOT_PRESENT}"
    printf 'ldwrapper_before_line=%s\n' "$ldwrapper_before_line"
    printf 'ldwrapper_after_line=%s\n' "$ldwrapper_after_line"
    echo "ldwrapper_clang_gate=PASS"
} >> "$DECISION"
echo "gate.ldwrapper_patch=PASS style=$ldwrapper_style"
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
MIMALLOC_OBJECT="$BUILD_ROOT/mimalloc.o"
RESDIR="$(clang -print-resource-dir)"
echo "gate.mimalloc_resource_dir=$RESDIR"
test -f "$RESDIR/include/stdatomic.h" || {
    echo "GATE: stdatomic.h not in $RESDIR/include" >&2
    exit 1
}
echo "gate.mimalloc_stdatomic_header=PASS path=$RESDIR/include/stdatomic.h"
{
    echo "mimalloc_isystem_resource=$RESDIR/include"
    echo "mimalloc_include_order=musl_first_resource_fill"
} >> "$DECISION"
record_and_run "$MUSL_CC" "${OPTFLAGS_ARRAY[@]}" -O2 -DNDEBUG -DMI_MALLOC_OVERRIDE \
    -I "$MIMALLOC_SOURCE_DIR/include" \
    -isystem "$RESDIR/include" \
    -c "$MIMALLOC_SOURCE_DIR/src/static.c" -o "$MIMALLOC_OBJECT"
echo "mimalloc_compile_env=musl-clang(headers=musl, backend=clang $EXPECTED_CLANG_VERSION)" >> "$DECISION"
mimalloc_lfs64_symbols="$(
    nm -u "$MIMALLOC_OBJECT" \
        | grep -E '[[:space:]](mmap64|munmap64|open64|openat64|pread64|pwrite64|lseek64|ftruncate64|fstat64|stat64|mmap2)$' \
        || true
)"
echo "gate.mimalloc_lfs64_symbols.scan_begin"
[[ -z "$mimalloc_lfs64_symbols" ]] || printf '%s\n' "$mimalloc_lfs64_symbols"
echo "gate.mimalloc_lfs64_symbols.scan_end"
[[ -z "$mimalloc_lfs64_symbols" ]] || \
    fail "mimalloc.o references forbidden LFS64 symbols"
echo "gate.mimalloc_lfs64_symbols=PASS"
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
record_and_run "$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE" \
    "$MIMALLOC_OBJECT" \
    -Wl,-Map,"$BUILD_ROOT/micro.musl-mi.map" \
    -o "$PAYLOAD/bin/micro.musl-mi"
record_and_run clang "${COMMON_FLAGS[@]}" "$TIMER_SOURCE" \
    -o "$PAYLOAD/bin/timer"

static_link_core=("$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE")
mi_link_core=("$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE" "$MIMALLOC_OBJECT")
[[ "${#mi_link_core[@]}" -eq $(( ${#static_link_core[@]} + 1 )) ]] || \
    fail "musl-mi link core differs by more than one argument"
for (( argument_index = 0; argument_index < ${#static_link_core[@]}; argument_index++ )); do
    [[ "${static_link_core[$argument_index]}" == "${mi_link_core[$argument_index]}" ]] || \
        fail "musl-mi link argument differs at index $argument_index"
done
[[ "${mi_link_core[${#static_link_core[@]}]}" == "$MIMALLOC_OBJECT" ]] || \
    fail "musl-mi only additional link input is not mimalloc.o"
printf 'fairness.musl_static='; printf '%q ' "${static_link_core[@]}"; printf '\n'
printf 'fairness.musl_mi='; printf '%q ' "${mi_link_core[@]}"; printf '\n'
echo "gate.musl_mi_command_delta=PASS only_extra_link_input=$MIMALLOC_OBJECT"

MI_MAP="$BUILD_ROOT/micro.musl-mi.map"
MI_BIN="$PAYLOAD/bin/micro.musl-mi"
[[ -s "$MI_MAP" ]] || fail "micro.musl-mi map file is missing"
[[ -s "$MIMALLOC_OBJECT" ]] || fail "mimalloc.o is missing"

map_symbol_owner() {
    local symbol="$1"
    awk -v symbol="$symbol" '
        /mimalloc[.]o/ { owner="mimalloc.o"; owner_line=$0 }
        /libc[.]a[(]/ { owner="libc.a"; owner_line=$0 }
        $1 ~ /^0x[0-9a-fA-F]+$/ && $NF == symbol {
            printf "%s\t%s\t%s\n", owner, owner_line, $0
            exit
        }
    ' "$MI_MAP"
}

for symbol in malloc free calloc realloc posix_memalign aligned_alloc malloc_usable_size; do
    map_evidence="$(map_symbol_owner "$symbol")"
    map_owner="${map_evidence%%$'\t'*}"
    [[ "$map_owner" == "mimalloc.o" ]] || \
        fail "$symbol is not defined by mimalloc.o map_evidence=${map_evidence:-MISSING}"
    printf 'gate.mimalloc_symbol.%s=PASS\t%s\n' "$symbol" "$map_evidence"
done
mi_symbol_line="$(nm "$MI_BIN" | grep -m 1 -E '[[:space:]][Tt][[:space:]]+mi_[A-Za-z0-9_]+$' || true)"
[[ -n "$mi_symbol_line" ]] || fail "micro.musl-mi has no mi_ prefixed text symbol"
printf 'gate.mimalloc_mi_prefix=PASS nm_line=%s\n' "$mi_symbol_line"
{
    echo "mimalloc_command_delta=PASS"
    echo "mimalloc_symbol_owner=mimalloc.o"
    echo "mimalloc_symbol_gate=PASS"
    printf 'mimalloc_nm_evidence=%s\n' "$mi_symbol_line"
} >> "$DECISION"
cp -- "$MI_MAP" "$PAYLOAD/share/micro.musl-mi.map"

cp -- "$MUSL_PREFIX/lib/libc.so" "$PAYLOAD/lib/libc.so"

{
    for path in \
        bin/micro.glibc-dyn \
        bin/micro.musl-static \
        bin/micro.musl-dyn \
        bin/micro.musl-mi \
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
    "$PAYLOAD/bin/micro.musl-mi" \
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

grep -q 'statically linked' < <(file "$MI_BIN") || fail "musl-mi is not statically linked"
if grep -q 'INTERP' < <(readelf -lW "$MI_BIN"); then
    fail "musl-mi unexpectedly contains PT_INTERP"
fi
if grep -q '(NEEDED)' < <(readelf -dW "$MI_BIN" 2>/dev/null); then
    fail "musl-mi unexpectedly contains DT_NEEDED"
fi
if grep -q 'GLIBC_' < <(readelf --all --wide "$MI_BIN"); then
    fail "musl-mi contains a GLIBC_ symbol"
fi
if grep -q 'GLIBC_' < <(strings -a "$MI_BIN"); then
    fail "musl-mi contains a GLIBC_ string"
fi
echo "gate.micro.musl-mi.structure=PASS"

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
        libc.so.6|libpthread.so.0|ld-linux.so.3) ;;
        *) fail "glibc-dyn has unexpected DT_NEEDED: $needed" ;;
    esac
done <<< "$glibc_needed"
echo "gate.micro.glibc-dyn=PASS interpreter=$glibc_interp"

vfp_args_of() {
    local tag_line
    tag_line="$(readelf -AW "$1" | grep -m 1 'Tag_ABI_VFP_args' || true)"
    if [[ -n "$tag_line" ]]; then
        printf '%s\n' "$tag_line"
    else
        printf '%s\n' "ABSENT"
    fi
}

check_arm_abi_consistency() {
    local path
    local glibc_vfp_args static_vfp_args musl_dyn_vfp_args binsh_vfp_args
    local abi_consistency="PASS"
    local abi_failure=""

    for path in "$GLIBC_DYN_BIN" "$STATIC_BIN" "$MUSL_DYN_BIN"; do
        grep -Eq 'Class:[[:space:]]+ELF32' < <(readelf -hW "$path") || \
            fail "$path is not ELF32"
        grep -Eq 'Machine:[[:space:]]+ARM' < <(readelf -hW "$path") || \
            fail "$path is not ARM"
    done

    glibc_vfp_args="$(vfp_args_of "$GLIBC_DYN_BIN")"
    static_vfp_args="$(vfp_args_of "$STATIC_BIN")"
    musl_dyn_vfp_args="$(vfp_args_of "$MUSL_DYN_BIN")"
    binsh_vfp_args="$(vfp_args_of /bin/sh)"

    if [[ "$glibc_vfp_args" != "$static_vfp_args" || \
          "$glibc_vfp_args" != "$musl_dyn_vfp_args" ]]; then
        abi_consistency="FAIL"
        abi_failure="variant Tag_ABI_VFP_args values differ"
    fi
    if [[ "$glibc_vfp_args" == *"VFP registers"* || \
          "$static_vfp_args" == *"VFP registers"* || \
          "$musl_dyn_vfp_args" == *"VFP registers"* ]]; then
        abi_consistency="FAIL"
        abi_failure="${abi_failure:+$abi_failure; }softfp variant is tagged VFP registers"
    fi
    if [[ "$binsh_vfp_args" != "$glibc_vfp_args" || \
          "$binsh_vfp_args" != "$static_vfp_args" || \
          "$binsh_vfp_args" != "$musl_dyn_vfp_args" ]]; then
        abi_consistency="FAIL"
        abi_failure="${abi_failure:+$abi_failure; }variants differ from chroot /bin/sh"
    fi

    {
        echo "platform_float_abi=softfp"
        printf 'variant_vfp_args=glibc-dyn:%s | musl-static:%s | musl-dyn:%s\n' \
            "$glibc_vfp_args" "$static_vfp_args" "$musl_dyn_vfp_args"
        printf 'binsh_vfp_args=%s\n' "$binsh_vfp_args"
        echo "abi_consistency=$abi_consistency"
    } >> "$DECISION"

    [[ "$abi_consistency" == "PASS" ]] || \
        fail "ARM float ABI consistency failed: $abi_failure"
}

check_arm_abi_consistency
echo "gate.arm32_softfp_abi_consistency=PASS"

grep -Eq 'Class:[[:space:]]+ELF32' < <(readelf -hW "$MI_BIN") || \
    fail "$MI_BIN is not ELF32"
grep -Eq 'Machine:[[:space:]]+ARM' < <(readelf -hW "$MI_BIN") || \
    fail "$MI_BIN is not ARM"
mi_vfp_args="$(vfp_args_of "$MI_BIN")"
static_vfp_args="$(vfp_args_of "$STATIC_BIN")"
binsh_vfp_args="$(vfp_args_of /bin/sh)"
[[ "$mi_vfp_args" != *"VFP registers"* ]] || \
    fail "softfp musl-mi is tagged VFP registers"
[[ "$mi_vfp_args" == "$static_vfp_args" && "$mi_vfp_args" == "$binsh_vfp_args" ]] || \
    fail "musl-mi float ABI differs from musl-static or chroot /bin/sh"
printf 'mimalloc_vfp_args=%s\n' "$mi_vfp_args" >> "$DECISION"
echo "mimalloc_abi_consistency=PASS" >> "$DECISION"
echo "gate.micro.musl-mi.arm32_softfp=PASS vfp_args=$mi_vfp_args"

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
        bin/micro.musl-mi \
        bin/timer \
        lib/libc.so > share/artifacts.sha256
)

echo "BUILD_GATE_PASS: all comparison artifacts passed"
