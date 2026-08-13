#!/usr/bin/env bash
# Runs inside the GBS chroot; builds only S5 and attempts optional S6.
set -euo pipefail

if [[ "$#" -ne 7 ]]; then
    echo "usage: build-allocator-shootout.sh MUSL_TARBALL MUSL_SHA MICRO_C RPMALLOC_TARBALL RPMALLOC_SHA SCUDO_TARBALL SCUDO_SHA" >&2
    exit 2
fi

MUSL_TARBALL="$1"
MUSL_SHA_FILE="$2"
MICRO_SOURCE="$3"
RPMALLOC_TARBALL="$4"
RPMALLOC_SHA_FILE="$5"
SCUDO_TARBALL="$6"
SCUDO_SHA_FILE="$7"
EXPECTED_CLANG_VERSION="22.1.8"
BUILD_ROOT="$PWD"
MUSL_SOURCE_DIR="$BUILD_ROOT/musl-1.2.5"
MUSL_PREFIX="$BUILD_ROOT/musl-inst"
RPMALLOC_SOURCE_DIR="$BUILD_ROOT/rpmalloc-1.4.5"
SCUDO_SOURCE_DIR="$BUILD_ROOT/scudo-standalone-22.1.8"
PAYLOAD="$BUILD_ROOT/payload"
COMMANDS="$PAYLOAD/share/shootout-build-commands.txt"
DECISION="$PAYLOAD/share/shootout-compiler-decision.txt"
S6_STATUS="$PAYLOAD/share/shootout-s6-status.txt"

fail() {
    echo "BUILD_GATE_FAIL: $*" >&2
    exit 1
}

for tool in ar awk bash clang diff file find getconf grep ln ls make nm readelf readlink sha256sum strings tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "required chroot tool missing: $tool"
done

mkdir -p "$PAYLOAD/bin" "$PAYLOAD/share"
: > "$COMMANDS"
: > "$DECISION"
: > "$S6_STATUS"

verify_source() {
    local label="$1"
    local archive="$2"
    local digest_file="$3"
    local expected actual
    expected="$(awk 'NF { print tolower($1); exit }' "$digest_file")"
    actual="$(sha256sum "$archive" | awk '{ print tolower($1) }')"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "$label frozen digest is invalid"
    [[ "$actual" == "$expected" ]] || \
        fail "$label sha256 mismatch expected=$expected actual=$actual"
    printf 'gate.%s_sha256=PASS value=%s\n' "$label" "$actual"
}

verify_source source1 "$MUSL_TARBALL" "$MUSL_SHA_FILE"
verify_source rpmalloc "$RPMALLOC_TARBALL" "$RPMALLOC_SHA_FILE"
verify_source scudo "$SCUDO_TARBALL" "$SCUDO_SHA_FILE"

clang_version_text="$(clang --version)"
grep -Eq 'clang version 22\.1\.8([^0-9]|$)' <<< "$clang_version_text" || {
    printf '%s\n' "$clang_version_text" >&2
    fail "clang version mismatch: expected $EXPECTED_CLANG_VERSION"
}
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
    echo "clang_path=$(command -v clang)"
    echo "clang_dumpmachine=$(clang -dumpmachine)"
    echo "selected_rtlib=$RTLIB_NAME"
    echo "selected_rtlib_flag=$RTLIB_FLAG"
    echo "selected_rtlib_archive=$RTLIB_ARCHIVE"
    echo "rpmalloc_version=1.4.5"
    echo "rpmalloc_source_sha256=$(awk 'NF { print tolower($1); exit }' "$RPMALLOC_SHA_FILE")"
    echo "scudo_version=llvmorg-22.1.8"
    echo "scudo_source_commit=ca7933e47d3a3451d81e72ac174dcb5aa28b59d1"
    echo "baseline_binary_source=musl-libc-demo-1.0.0-2.armv7l.rpm"
    echo "baseline_binaries_rebuilt=NO"
    echo "clang_version_begin"
    printf '%s\n' "$clang_version_text"
    echo "clang_version_end"
} | tee "$DECISION"

rm -rf -- "$MUSL_SOURCE_DIR" "$MUSL_PREFIX" "$RPMALLOC_SOURCE_DIR" "$SCUDO_SOURCE_DIR"
tar -xf "$MUSL_TARBALL"
tar -xf "$RPMALLOC_TARBALL"
tar -xf "$SCUDO_TARBALL"
[[ -d "$MUSL_SOURCE_DIR" ]] || fail "musl source layout mismatch"
[[ -d "$RPMALLOC_SOURCE_DIR/rpmalloc" ]] || fail "rpmalloc source layout mismatch"
[[ -d "$SCUDO_SOURCE_DIR/include/scudo" ]] || fail "Scudo source layout mismatch"
[[ "$(< "$SCUDO_SOURCE_DIR/LLVM_COMMIT")" == "ca7933e47d3a3451d81e72ac174dcb5aa28b59d1" ]] || \
    fail "Scudo source commit marker mismatch"

OPTFLAGS_TEXT="${OPTFLAGS:?OPTFLAGS must contain expanded rpm optflags}"
read -r -a OPTFLAGS_ARRAY <<< "$OPTFLAGS_TEXT"
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=1

(
    cd "$MUSL_SOURCE_DIR"
    CC=clang CFLAGS="$OPTFLAGS_TEXT $RTLIB_FLAG" \
        LDFLAGS="$RTLIB_FLAG -static-libgcc" \
        ./configure --prefix="$MUSL_PREFIX" \
        --syslibdir=/opt/usr/musl-demo/lib --enable-wrapper=clang
    make -j "$jobs"
    make install
)

MUSL_CC="$MUSL_PREFIX/bin/musl-clang"
MUSL_LD="$MUSL_PREFIX/bin/ld.musl-clang"
[[ -x "$MUSL_CC" && -x "$MUSL_LD" ]] || fail "musl clang wrappers missing"
grep -Eq '^cc="?clang"?$' "$MUSL_CC" || fail "musl-clang does not invoke clang"
grep -Eq '^cc="?clang"?$' "$MUSL_LD" || fail "ld.musl-clang does not invoke clang"

# Keep the established static-archive group correction identical to release 2.
LDWRAPPER_BEFORE="$BUILD_ROOT/ld.musl-clang.before"
LDWRAPPER_PATCHED="$BUILD_ROOT/ld.musl-clang.patched"
cp -p -- "$MUSL_LD" "$LDWRAPPER_BEFORE"
ldwrapper_before_line="$(grep '^exec ' "$LDWRAPPER_BEFORE" | tail -n 1)"
[[ -n "$ldwrapper_before_line" && "$ldwrapper_before_line" == *" -lc "* ]] || \
    fail "ld.musl-clang linker line cannot be patched"
case "$ldwrapper_before_line" in
    'exec $($cc -print-prog-name=ld)'*) ldwrapper_style="ld" ;;
    'exec $cc '*|'exec "$cc" '*) ldwrapper_style="cc-driver" ;;
    *) fail "unrecognized ld.musl-clang style: $ldwrapper_before_line" ;;
esac
group_rtlib_archive="$(readlink -f "$RTLIB_ARCHIVE")"
[[ -f "$group_rtlib_archive" ]] || fail "runtime archive cannot be canonicalized"
group_rtlib_eh=""
if [[ -f "$(dirname "$group_rtlib_archive")/libgcc_eh.a" ]]; then
    group_rtlib_eh="$(dirname "$group_rtlib_archive")/libgcc_eh.a"
fi
if [[ "$ldwrapper_style" == "ld" ]]; then
    group_args="--start-group -lc $group_rtlib_archive"
    [[ -z "$group_rtlib_eh" ]] || group_args="$group_args $group_rtlib_eh"
    group_args="$group_args --end-group"
else
    group_args="-Wl,--start-group -lc $group_rtlib_archive"
    [[ -z "$group_rtlib_eh" ]] || group_args="$group_args $group_rtlib_eh"
    group_args="$group_args -Wl,--end-group"
fi
ldwrapper_after_line="${ldwrapper_before_line/ -lc / $group_args }"
replacements=0
while IFS= read -r wrapper_line || [[ -n "$wrapper_line" ]]; do
    if [[ "$wrapper_line" == "$ldwrapper_before_line" ]]; then
        printf '%s\n' "$ldwrapper_after_line"
        replacements=$((replacements + 1))
    else
        printf '%s\n' "$wrapper_line"
    fi
done < "$LDWRAPPER_BEFORE" > "$LDWRAPPER_PATCHED"
[[ "$replacements" -eq 1 ]] || fail "wrapper replacement count=$replacements"
chmod 0755 "$LDWRAPPER_PATCHED"
mv -f -- "$LDWRAPPER_PATCHED" "$MUSL_LD"
{
    echo "ldwrapper_patch=start-group"
    echo "ldwrapper_before_line=$ldwrapper_before_line"
    echo "ldwrapper_after_line=$ldwrapper_after_line"
} >> "$DECISION"
echo "gate.ldwrapper_patch=PASS"

record_and_run() {
    local arg
    {
        for arg in "$@"; do printf '%q ' "$arg"; done
        printf '\n'
    } >> "$COMMANDS"
    "$@"
}

RESDIR="$(clang -print-resource-dir)"
[[ -f "$RESDIR/include/stdatomic.h" ]] || fail "stdatomic.h missing in $RESDIR/include"
COMMON_FLAGS=("${OPTFLAGS_ARRAY[@]}" "$RTLIB_FLAG" -static-libgcc -pthread)
LFS64_PATTERN='[[:space:]](mmap64|munmap64|open64|openat64|pread64|pwrite64|lseek64|ftruncate64|fstat64|stat64|mmap2)$'
RPMALLOC_OBJECT="$BUILD_ROOT/rpmalloc.o"
RPMALLOC_DEPFILE="$BUILD_ROOT/rpmalloc.d"

record_and_run "$MUSL_CC" "${OPTFLAGS_ARRAY[@]}" -O2 -DNDEBUG \
    -DENABLE_PRELOAD=1 -DENABLE_OVERRIDE=1 \
    -I "$RPMALLOC_SOURCE_DIR/rpmalloc" -isystem "$RESDIR/include" \
    -MMD -MF "$RPMALLOC_DEPFILE" \
    -c "$RPMALLOC_SOURCE_DIR/rpmalloc/rpmalloc.c" -o "$RPMALLOC_OBJECT"
grep -Fq "$RPMALLOC_SOURCE_DIR/rpmalloc/malloc.c" "$RPMALLOC_DEPFILE" || \
    fail "rpmalloc override translation unit did not incorporate malloc.c"
rpmalloc_lfs64="$(nm -u "$RPMALLOC_OBJECT" | grep -E "$LFS64_PATTERN" || true)"
echo "gate.rpmalloc_lfs64.scan_begin"
[[ -z "$rpmalloc_lfs64" ]] || printf '%s\n' "$rpmalloc_lfs64"
echo "gate.rpmalloc_lfs64.scan_end"
[[ -z "$rpmalloc_lfs64" ]] || fail "rpmalloc object references forbidden LFS64 symbols"
echo "gate.rpmalloc_lfs64=PASS"

RP_BIN="$PAYLOAD/bin/micro.musl-rp"
RP_MAP="$BUILD_ROOT/micro.musl-rp.map"
record_and_run "$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE" \
    "$RPMALLOC_OBJECT" -Wl,-Map,"$RP_MAP" -o "$RP_BIN"

map_symbol_owner() {
    local map_file="$1"
    local allocator_pattern="$2"
    local symbol="$3"
    awk -v allocator_pattern="$allocator_pattern" -v symbol="$symbol" '
        $0 ~ allocator_pattern { owner=$0 }
        /libc[.]a[(]/ { owner=$0 }
        $1 ~ /^0x[0-9a-fA-F]+$/ && $NF == symbol { print owner; exit }
    ' "$map_file"
}

for symbol in malloc free calloc realloc posix_memalign aligned_alloc malloc_usable_size; do
    owner="$(map_symbol_owner "$RP_MAP" "rpmalloc[.]o" "$symbol")"
    [[ "$owner" == *"rpmalloc.o"* ]] || \
        fail "$symbol is not defined by rpmalloc.o evidence=${owner:-MISSING}"
    printf 'gate.rpmalloc_symbol.%s=PASS owner=%s\n' "$symbol" "$owner"
done
rpmalloc_nm="$(nm "$RP_BIN" | grep -m 1 -E '[[:space:]][Tt][[:space:]]+rpmalloc(_initialize)?$' || true)"
[[ -n "$rpmalloc_nm" ]] || fail "S5 has no rpmalloc-prefixed text symbol"

main_allocator_members="$(grep -E 'libc[.]a[(](malloc|calloc|free|realloc|reallocarray|memalign|aligned_alloc|posix_memalign|malloc_usable_size)[.]lo[)]' "$RP_MAP" || true)"
echo "gate.rpmalloc_musl_allocator_members.scan_begin"
[[ -z "$main_allocator_members" ]] || printf '%s\n' "$main_allocator_members"
echo "gate.rpmalloc_musl_allocator_members.scan_end"
[[ -z "$main_allocator_members" ]] || fail "musl primary allocator members were extracted into S5"
echo "gate.rpmalloc_musl_allocator_members=PASS count=0"
rpmalloc_pthread_owner="$(map_symbol_owner "$RP_MAP" "rpmalloc[.]o" "pthread_create")"
rpmalloc_dlsym_owner="$(map_symbol_owner "$RP_MAP" "rpmalloc[.]o" "dlsym")"
printf 'h1.pthread_create_owner=%s\n' "${rpmalloc_pthread_owner:-MISSING}"
printf 'h1.dlsym_owner=%s\n' "${rpmalloc_dlsym_owner:-MISSING}"
{
    echo "rpmalloc_compile_defines=ENABLE_PRELOAD=1 ENABLE_OVERRIDE=1"
    echo "rpmalloc_h1_pthread_create_owner=${rpmalloc_pthread_owner:-MISSING}"
    echo "rpmalloc_h1_dlsym_owner=${rpmalloc_dlsym_owner:-MISSING}"
} >> "$DECISION"

check_static_arm_softfp() {
    local label="$1"
    local binary="$2"
    grep -q 'statically linked' < <(file "$binary") || fail "$label is not static"
    ! grep -q 'INTERP' < <(readelf -lW "$binary") || fail "$label has PT_INTERP"
    ! grep -q '(NEEDED)' < <(readelf -dW "$binary" 2>/dev/null) || fail "$label has DT_NEEDED"
    grep -Eq 'Class:[[:space:]]+ELF32' < <(readelf -hW "$binary") || fail "$label is not ELF32"
    grep -Eq 'Machine:[[:space:]]+ARM' < <(readelf -hW "$binary") || fail "$label is not ARM"
    ! grep -q 'GLIBC_' < <(readelf --all --wide "$binary") || fail "$label has GLIBC symbol"
    ! grep -q 'GLIBC_' < <(strings -a "$binary") || fail "$label has GLIBC string"
    vfp="$(readelf -AW "$binary" | grep -m 1 'Tag_ABI_VFP_args' || true)"
    binsh_vfp="$(readelf -AW /bin/sh | grep -m 1 'Tag_ABI_VFP_args' || true)"
    [[ "${vfp:-ABSENT}" == "${binsh_vfp:-ABSENT}" ]] || fail "$label float ABI differs from /bin/sh"
    [[ "$vfp" != *"VFP registers"* ]] || fail "$label is hard-float tagged"
    printf 'gate.%s.elf_softfp=PASS vfp=%s\n' "$label" "${vfp:-ABSENT}"
}

check_static_arm_softfp s5_rpmalloc "$RP_BIN"
{
    echo "rpmalloc_compile_env=musl-clang(headers=musl,resource_fill=$RESDIR/include,backend=clang $EXPECTED_CLANG_VERSION)"
    echo "rpmalloc_malloc_c_incorporated=PASS"
    echo "rpmalloc_symbol_owner=rpmalloc.o"
    echo "rpmalloc_musl_primary_allocator_members=0"
    echo "rpmalloc_nm_evidence=$rpmalloc_nm"
    echo "s5_gate=PASS"
} >> "$DECISION"
cp -- "$RP_MAP" "$PAYLOAD/share/micro.musl-rp.map"

# Optional S6: standalone deliberately avoids the C++ standard library. Any
# actual C++ runtime friction is preserved and downgraded to P1, never repaired
# by introducing libc++ in this workstream.
SCUDO_OBJ_DIR="$BUILD_ROOT/scudo-objects"
SCUDO_ARCHIVE="$BUILD_ROOT/libscudo_standalone.a"
SCUDO_LOG="$BUILD_ROOT/scudo-attempt.log"
SCUDO_BIN="$PAYLOAD/bin/micro.musl-scudo"
SCUDO_MAP="$BUILD_ROOT/micro.musl-scudo.map"
UAPI_STAGE="$BUILD_ROOT/uapi-stage"
rm -rf -- "$UAPI_STAGE"
mkdir -p "$SCUDO_OBJ_DIR" "$UAPI_STAGE"
scudo_uapi_whitelist=()
for uapi_dir in linux asm asm-generic; do
    if [[ -d "/usr/include/$uapi_dir" ]]; then
        ln -s "/usr/include/$uapi_dir" "$UAPI_STAGE/$uapi_dir"
        scudo_uapi_whitelist+=("$uapi_dir")
    fi
done
echo "gate.scudo_uapi_stage.listing_begin"
ls -l "$UAPI_STAGE"
echo "gate.scudo_uapi_stage.listing_end"
uapi_stage_entries=()
while IFS= read -r entry; do
    uapi_stage_entries+=("$entry")
done < <(find "$UAPI_STAGE" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
for entry in "${uapi_stage_entries[@]}"; do
    case "$entry" in
        linux|asm|asm-generic) ;;
        *) fail "Scudo UAPI stage contains non-whitelisted entry: $entry" ;;
    esac
done
[[ "${#uapi_stage_entries[@]}" -eq "${#scudo_uapi_whitelist[@]}" ]] || \
    fail "Scudo UAPI stage entry count does not match available whitelist"
{
    printf 'scudo_uapi_stage=%s\n' "${scudo_uapi_whitelist[*]}"
    echo "scudo_include_order=musl_first_resource_fill_uapi_last"
    echo "scudo_uapi_stage_path=$UAPI_STAGE"
} >> "$DECISION"
scudo_sources=(
    checksum.cpp common.cpp condition_variable_linux.cpp crc32_hw.cpp
    flags_parser.cpp flags.cpp fuchsia.cpp linux.cpp mem_map.cpp
    mem_map_fuchsia.cpp mem_map_linux.cpp release.cpp report.cpp
    report_linux.cpp string_utils.cpp timing.cpp wrappers_c.cpp
)
scudo_objects=()
set +e
(
    for source in "${scudo_sources[@]}"; do
        object="$SCUDO_OBJ_DIR/${source%.cpp}.o"
        depfile="$SCUDO_OBJ_DIR/${source%.cpp}.d"
        scudo_objects+=("$object")
        record_and_run "$MUSL_CC" "${OPTFLAGS_ARRAY[@]}" -O2 -DNDEBUG \
            -std=c++17 -nostdinc++ -fno-exceptions -fno-rtti \
            -fvisibility=hidden -ffunction-sections -fdata-sections \
            -I "$SCUDO_SOURCE_DIR" -I "$SCUDO_SOURCE_DIR/include" \
            -isystem "$RESDIR/include" -isystem "$UAPI_STAGE" \
            -MD -MF "$depfile" \
            -c "$SCUDO_SOURCE_DIR/$source" -o "$object" || exit $?
    done

    audit_first=$((RANDOM % ${#scudo_sources[@]}))
    audit_second=$((RANDOM % ${#scudo_sources[@]}))
    while [[ "$audit_second" -eq "$audit_first" ]]; do
        audit_second=$((RANDOM % ${#scudo_sources[@]}))
    done
    for audit_index in "$audit_first" "$audit_second"; do
        audit_source="${scudo_sources[$audit_index]}"
        audit_depfile="$SCUDO_OBJ_DIR/${audit_source%.cpp}.d"
        echo "gate.scudo_dependency_audit.sample=$audit_source"
        echo "gate.scudo_dependency_audit.depfile_begin"
        cat "$audit_depfile"
        echo "gate.scudo_dependency_audit.depfile_end"
        direct_glibc_headers="$(
            sed ':join;N;$!b join;s/\\\n/ /g' "$audit_depfile" \
                | tr ' ' '\n' \
                | grep -E '^/usr/include/' \
                | grep -Ev '^/usr/include/(linux|asm|asm-generic)/' \
                || true
        )"
        [[ -z "$direct_glibc_headers" ]] || {
            printf '%s\n' "$direct_glibc_headers"
            fail "Scudo dependency audit found non-UAPI /usr/include headers"
        }
        echo "gate.scudo_dependency_audit.$audit_source=PASS direct_glibc_headers=0"
    done

    record_and_run ar rcs "$SCUDO_ARCHIVE" "${scudo_objects[@]}" || exit $?
    record_and_run "$MUSL_CC" "${COMMON_FLAGS[@]}" -static "$MICRO_SOURCE" \
        "$SCUDO_ARCHIVE" -Wl,-Map,"$SCUDO_MAP" -o "$SCUDO_BIN" || exit $?

    scudo_lfs64="$(nm -u "$SCUDO_ARCHIVE" | grep -E "$LFS64_PATTERN" || true)"
    [[ -z "$scudo_lfs64" ]] || fail "Scudo archive references forbidden LFS64 symbols"
    for symbol in malloc free calloc realloc posix_memalign aligned_alloc malloc_usable_size; do
        owner="$(map_symbol_owner "$SCUDO_MAP" "libscudo_standalone[.]a" "$symbol")"
        [[ "$owner" == *"libscudo_standalone.a"* ]] || \
            fail "$symbol is not defined by Scudo archive evidence=${owner:-MISSING}"
    done
    scudo_musl_members="$(grep -E 'libc[.]a[(](malloc|calloc|free|realloc|reallocarray|memalign|aligned_alloc|posix_memalign|malloc_usable_size)[.]lo[)]' "$SCUDO_MAP" || true)"
    [[ -z "$scudo_musl_members" ]] || fail "musl primary allocator members extracted into S6"
    scudo_nm="$(nm "$SCUDO_BIN" | grep -m 1 -E '[[:space:]][Tt][[:space:]]+__scudo_print_stats$' || true)"
    [[ -n "$scudo_nm" ]] || fail "S6 has no __scudo_print_stats symbol"
    check_static_arm_softfp s6_scudo "$SCUDO_BIN"
    cp -- "$SCUDO_MAP" "$PAYLOAD/share/micro.musl-scudo.map"
) > "$SCUDO_LOG" 2>&1
scudo_attempt_rc=$?
set -e
cat "$SCUDO_LOG"

if [[ "$scudo_attempt_rc" -ne 0 ]]; then
    s6_first_error="$(grep -m 1 -E 'fatal error:|error:|undefined reference|BUILD_GATE_FAIL:' "$SCUDO_LOG" || true)"
    {
        echo "s6_status=P1-DEFERRED"
        echo "s6_reason=POST_UAPI_FRICTION_BUDGET_EXHAUSTED"
        echo "s6_attempt_rc=$scudo_attempt_rc"
        echo "s6_first_error=${s6_first_error:-UNCLASSIFIED; see gbs-build-shootout.log}"
        echo "libcxx_environment_added=NO"
    } | tee "$S6_STATUS"
    echo "s6_status=P1-DEFERRED reason=POST_UAPI_FRICTION_BUDGET_EXHAUSTED" >> "$DECISION"
    rm -f -- "$SCUDO_BIN" "$SCUDO_MAP" "$PAYLOAD/share/micro.musl-scudo.map"
else
    {
        echo "s6_status=BUILT"
        echo "s6_reason=NONE"
        echo "s6_attempt_rc=0"
        echo "libcxx_environment_added=NO"
    } | tee "$S6_STATUS"
    echo "s6_status=BUILT" >> "$DECISION"
fi

if command -v llvm-strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v llvm-strip)"
elif command -v strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v strip)"
else
    fail "no strip tool available"
fi
"$STRIP_TOOL" --strip-unneeded "$RP_BIN"
if [[ -x "$SCUDO_BIN" ]]; then "$STRIP_TOOL" --strip-unneeded "$SCUDO_BIN"; fi

(
    cd "$PAYLOAD"
    sha256sum bin/micro.musl-* > share/shootout-artifacts.sha256
)
echo "BUILD_GATE_PASS: S5 complete; S6 status=$(awk -F= '$1 == "s6_status" { print $2 }' "$S6_STATUS")"
