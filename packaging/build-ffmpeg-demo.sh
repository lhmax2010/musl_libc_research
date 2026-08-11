#!/usr/bin/env bash
# Runs inside the GBS chroot and builds the six ffmpeg size/configure variants.
set -euo pipefail

if [[ "$#" -ne 8 ]]; then
    echo "usage: build-ffmpeg-demo.sh FFMPEG_TAR FFMPEG_SHA FFMPEG_COMMIT MUSL_TAR MUSL_SHA MIMALLOC_TAR MIMALLOC_SHA TIMER_C" >&2
    exit 2
fi

FFMPEG_TARBALL="$1"
FFMPEG_SHA_FILE="$2"
FFMPEG_COMMIT_FILE="$3"
MUSL_TARBALL="$4"
MUSL_SHA_FILE="$5"
MIMALLOC_TARBALL="$6"
MIMALLOC_SHA_FILE="$7"
TIMER_SOURCE="$8"
EXPECTED_CLANG_VERSION="22.1.8"
EXPECTED_FFMPEG_VERSION="8.0.1"
PRIVATE_ROOT="/opt/usr/ffmpeg-demo"
BUILD_ROOT="$PWD"
FFMPEG_SOURCE_DIR="$BUILD_ROOT/ffmpeg-tizen-src"
MUSL_SOURCE_DIR="$BUILD_ROOT/musl-1.2.5"
MIMALLOC_SOURCE_DIR="$BUILD_ROOT/mimalloc-2.1.7"
MUSL_PREFIX="$BUILD_ROOT/musl-inst"
PAYLOAD="$BUILD_ROOT/payload"
COMMANDS="$PAYLOAD/share/ffmpeg-configure-commands.txt"
DECISION="$PAYLOAD/share/compiler-decision-ffmpeg.txt"
EQUIVALENCE="$PAYLOAD/share/configure-equivalence.txt"
PATCH_GATE="$PAYLOAD/share/patch-consistency.txt"
SIZE_MATRIX="$PAYLOAD/share/sizes-matrix.txt"
FUNCTION_SURFACE="$PAYLOAD/share/function-surface.txt"
C8_LEDGER="$PAYLOAD/share/c8-ledger.txt"

fail() {
    echo "BUILD_GATE_FAIL: $*" >&2
    exit 1
}

for tool in awk bash clang cmp diff file find getconf grep make nm readelf sed \
    sha256sum sort stat strings tail tar tr; do
    command -v "$tool" >/dev/null 2>&1 || fail "required chroot tool missing: $tool"
done

mkdir -p "$PAYLOAD/bin" "$PAYLOAD/share"
: > "$COMMANDS"
: > "$DECISION"
: > "$EQUIVALENCE"
: > "$PATCH_GATE"
: > "$SIZE_MATRIX"
: > "$FUNCTION_SURFACE"

verify_sha256() {
    local label="$1"
    local archive="$2"
    local digest_file="$3"
    local expected actual
    expected="$(awk 'NF { print tolower($1); exit }' "$digest_file")"
    actual="$(sha256sum "$archive" | awk '{print tolower($1)}')"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "$label frozen sha256 is invalid"
    [[ "$actual" == "$expected" ]] || \
        fail "$label sha256 mismatch expected=$expected actual=$actual"
    printf 'gate.%s_sha256=PASS value=%s\n' "$label" "$actual"
}

verify_sha256 source0 "$FFMPEG_TARBALL" "$FFMPEG_SHA_FILE"
verify_sha256 source3 "$MUSL_TARBALL" "$MUSL_SHA_FILE"
verify_sha256 source5 "$MIMALLOC_TARBALL" "$MIMALLOC_SHA_FILE"

frozen_commit="$(awk 'NF { print tolower($1); exit }' "$FFMPEG_COMMIT_FILE")"
[[ "$frozen_commit" =~ ^[0-9a-f]{40}$ ]] || fail "invalid frozen ffmpeg commit"

clang_path="$(command -v clang)"
clang_version_text="$(clang --version)"
grep -Eq 'clang version 22\.1\.8([^0-9]|$)' <<< "$clang_version_text" || {
    printf '%s\n' "$clang_version_text" >&2
    fail "clang version mismatch expected=$EXPECTED_CLANG_VERSION"
}

runtime_dir="$(clang -print-runtime-dir)"
libgcc_file="$(clang -print-libgcc-file-name)"
compiler_rt_candidates=()
while IFS= read -r line; do
    compiler_rt_candidates+=("$line")
done < <(
    find "$runtime_dir" -maxdepth 1 -type f \
        \( -name 'libclang_rt.builtins-arm*.a' -o -name 'libclang_rt.builtins.a' \) \
        -print 2>/dev/null | sort
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
    echo "ffmpeg_frozen_commit=$frozen_commit"
    echo "platform_float_abi=softfp"
    echo "clang_version_begin"
    printf '%s\n' "$clang_version_text"
    echo "clang_version_end"
} | tee "$DECISION"

rm -rf -- "$FFMPEG_SOURCE_DIR" "$MUSL_SOURCE_DIR" "$MIMALLOC_SOURCE_DIR" \
    "$MUSL_PREFIX" "$BUILD_ROOT"/build-F*
tar -xf "$FFMPEG_TARBALL"
tar -xf "$MUSL_TARBALL"
tar -xf "$MIMALLOC_TARBALL"
[[ -d "$FFMPEG_SOURCE_DIR" ]] || fail "Source0 did not unpack as ffmpeg-tizen-src"
[[ -d "$MUSL_SOURCE_DIR" ]] || fail "Source3 did not unpack as musl-1.2.5"
[[ -d "$MIMALLOC_SOURCE_DIR" ]] || fail "Source5 did not unpack as mimalloc-2.1.7"
[[ "$(sed -n '1p' "$FFMPEG_SOURCE_DIR/RELEASE")" == "$EXPECTED_FFMPEG_VERSION" ]] || \
    fail "ffmpeg RELEASE does not match spec version"

find "$FFMPEG_SOURCE_DIR" -type f -print | sort | while IFS= read -r source_file; do
    sha256sum "$source_file"
done > "$BUILD_ROOT/ffmpeg-source-manifest.before"

declared_patches="$BUILD_ROOT/tizen-patches.declared"
prep_patches="$BUILD_ROOT/tizen-patches.prep"
actual_patches="$BUILD_ROOT/tizen-patches.actual"
awk '$1 ~ /^Patch[0-9]*:$/ { print $2 }' \
    "$FFMPEG_SOURCE_DIR/packaging/ffmpeg.spec" > "$declared_patches"
awk '
    /^%prep([[:space:]]|$)/ { active=1; next }
    active && /^%(build|install|check|clean|files)([[:space:]]|$)/ { exit }
    active && /^[[:space:]]*%patch([[:space:]]|[0-9]|$)/ { print }
' "$FFMPEG_SOURCE_DIR/packaging/ffmpeg.spec" > "$prep_patches"
: > "$actual_patches"
{
    echo "frozen_commit=$frozen_commit"
    echo "declared_patch_count=$(awk 'END {print NR + 0}' "$declared_patches")"
    echo "prep_patch_apply_count=$(awk 'END {print NR + 0}' "$prep_patches")"
    echo "actual_patch_apply_count=$(awk 'END {print NR + 0}' "$actual_patches")"
    echo "declared_begin"
    cat "$declared_patches"
    echo "declared_end"
    echo "prep_apply_begin"
    cat "$prep_patches"
    echo "prep_apply_end"
    echo "actual_begin"
    cat "$actual_patches"
    echo "actual_end"
} > "$PATCH_GATE"
diff -u "$declared_patches" "$actual_patches" >> "$PATCH_GATE" || \
    fail "Tizen spec declared patch list differs from actual applied list"
[[ ! -s "$prep_patches" ]] || fail "Tizen prep applies patches but island applied list is empty"
echo "patch_consistency=PASS" >> "$PATCH_GATE"
echo "gate.patch_consistency=PASS count=0"

OPTFLAGS_TEXT="${OPTFLAGS:?OPTFLAGS must contain expanded rpm optflags}"
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
[[ -x "$MUSL_CC" && -x "$MUSL_LD" ]] || fail "musl clang wrappers were not installed"
grep -Eq '^cc="?clang"?$' "$MUSL_CC" || fail "musl-clang does not invoke clang"
grep -Eq '^cc="?clang"?$' "$MUSL_LD" || fail "ld.musl-clang does not invoke clang"

LDWRAPPER_BEFORE="$BUILD_ROOT/ld.musl-clang.before"
LDWRAPPER_PATCHED="$BUILD_ROOT/ld.musl-clang.patched"
cp -p -- "$MUSL_LD" "$LDWRAPPER_BEFORE"
echo "ldwrapper_before_begin"
cat "$LDWRAPPER_BEFORE"
echo "ldwrapper_before_end"
ldwrapper_before_line="$(grep '^exec ' "$LDWRAPPER_BEFORE" | tail -n 1)"
[[ -n "$ldwrapper_before_line" && "$ldwrapper_before_line" == *" -lc "* ]] || \
    fail "ld.musl-clang linker line is not patchable"
case "$ldwrapper_before_line" in
    'exec $($cc -print-prog-name=ld)'*) ldwrapper_style="ld" ;;
    'exec $cc '*|'exec "$cc" '*) ldwrapper_style="cc-driver" ;;
    *) fail "unrecognized ld.musl-clang exec style: $ldwrapper_before_line" ;;
esac
group_rtlib_archive="$(readlink -f "$RTLIB_ARCHIVE")"
group_rtlib_dir="$(dirname "$group_rtlib_archive")"
group_rtlib_eh=""
[[ -f "$group_rtlib_dir/libgcc_eh.a" ]] && group_rtlib_eh="$group_rtlib_dir/libgcc_eh.a"
if [[ "$ldwrapper_style" == "ld" ]]; then
    group_args="--start-group -lc $group_rtlib_archive"
    [[ -n "$group_rtlib_eh" ]] && group_args="$group_args $group_rtlib_eh"
    group_args="$group_args --end-group"
else
    group_args="-Wl,--start-group -lc $group_rtlib_archive"
    [[ -n "$group_rtlib_eh" ]] && group_args="$group_args $group_rtlib_eh"
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
[[ "$replacements" -eq 1 ]] || fail "ld wrapper replacement count=$replacements"
chmod 0755 "$LDWRAPPER_PATCHED"
mv -f -- "$LDWRAPPER_PATCHED" "$MUSL_LD"
echo "ldwrapper_after_begin"
cat "$MUSL_LD"
echo "ldwrapper_after_end"
{
    echo "ldwrapper_patch=start-group"
    echo "ldwrapper_style=$ldwrapper_style"
    echo "ldwrapper_group_rtlib_archive=$group_rtlib_archive"
    echo "ldwrapper_group_libgcc_eh=${group_rtlib_eh:-NOT_PRESENT}"
    echo "ldwrapper_before_line=$ldwrapper_before_line"
    echo "ldwrapper_after_line=$ldwrapper_after_line"
    echo "ldwrapper_clang_gate=PASS"
} >> "$DECISION"
echo "gate.ldwrapper_patch=PASS style=$ldwrapper_style"

MIMALLOC_OBJECT="$BUILD_ROOT/mimalloc.o"
RESDIR="$(clang -print-resource-dir)"
[[ -f "$RESDIR/include/stdatomic.h" ]] || fail "stdatomic.h missing from $RESDIR/include"
echo "gate.clang_resource_stdatomic=PASS path=$RESDIR/include/stdatomic.h"
"$MUSL_CC" "${OPTFLAGS_ARRAY[@]}" -O2 -DNDEBUG -DMI_MALLOC_OVERRIDE \
    -I "$MIMALLOC_SOURCE_DIR/include" -isystem "$RESDIR/include" \
    -c "$MIMALLOC_SOURCE_DIR/src/static.c" -o "$MIMALLOC_OBJECT"
mimalloc_lfs64_symbols="$(
    nm -u "$MIMALLOC_OBJECT" | grep -E \
        '[[:space:]](mmap64|munmap64|open64|openat64|pread64|pwrite64|lseek64|ftruncate64|fstat64|stat64|mmap2)$' || true
)"
[[ -z "$mimalloc_lfs64_symbols" ]] || {
    printf '%s\n' "$mimalloc_lfs64_symbols" >&2
    fail "mimalloc.o references forbidden LFS64 symbols"
}
{
    echo "mimalloc_compile_env=musl-clang(headers=musl, backend=clang $EXPECTED_CLANG_VERSION)"
    echo "mimalloc_isystem_resource=$RESDIR/include"
    echo "mimalloc_include_order=musl_first_resource_fill"
    echo "mimalloc_lfs64_gate=PASS"
    echo "ffmpeg_f2f3_isystem_resource=$RESDIR/include"
    echo "ffmpeg_include_order=musl_first_resource_fill"
} >> "$DECISION"
echo "gate.mimalloc_lfs64_symbols=PASS"

CAPABILITY_ARGS=(
    --disable-everything
    --disable-autodetect
    --disable-doc
    --disable-network
    --disable-hwaccels
    --disable-v4l2-m2m
    --disable-mmal
    --disable-omx
    --disable-vaapi
    --disable-vdpau
    --enable-decoder=h264
    --enable-demuxer=mov
    --enable-parser=h264
    --enable-protocol=file
    --enable-ffmpeg
    --disable-ffprobe
    --disable-ffplay
    --disable-avdevice
    --enable-muxer=null
    --enable-encoder=wrapped_avframe
    --enable-filter=null
    --enable-pthreads
    --enable-neon
    --enable-static
    --disable-shared
    --disable-stripping
    --arch=arm
    --target-os=linux
)

{
    echo "capability_args_begin"
    printf '%s\n' "${CAPABILITY_ARGS[@]}"
    echo "capability_args_end"
    echo "minimum_null_output_dependencies=encoder:wrapped_avframe,muxer:null,filter:null"
} >> "$COMMANDS"

if command -v llvm-strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v llvm-strip)"
elif command -v strip >/dev/null 2>&1; then
    STRIP_TOOL="$(command -v strip)"
else
    fail "no strip implementation available"
fi
echo "strip_tool=$STRIP_TOOL" >> "$DECISION"

record_command() {
    local arg
    for arg in "$@"; do printf '%q ' "$arg" >> "$COMMANDS"; done
    printf '\n' >> "$COMMANDS"
}

build_one() {
    local variant="$1"
    local size_mode="$2"
    local cc_path="$3"
    local link_mode="$4"
    local allocator="$5"
    local build_dir="$BUILD_ROOT/build-$variant-$size_mode"
    local output_name="ffmpeg.$variant"
    local extra_cflags="$OPTFLAGS_TEXT -pthread"
    local extra_ldflags="$RTLIB_FLAG -static-libgcc -pthread"
    local map_path=""
    local configure_log="$PAYLOAD/share/configure-$variant-$size_mode.txt"
    local source_binary
    local unstripped_size stripped_size
    local configure_args=()

    [[ "$size_mode" == "gc" ]] && {
        extra_cflags="$extra_cflags -ffunction-sections -fdata-sections"
        extra_ldflags="$extra_ldflags -Wl,--gc-sections"
        output_name="$output_name.gc"
    }
    [[ "$link_mode" == "static" ]] && extra_ldflags="$extra_ldflags -static"
    [[ "$cc_path" == "$MUSL_CC" ]] && \
        extra_cflags="$extra_cflags -isystem $RESDIR/include"
    if [[ "$allocator" == "mimalloc" ]]; then
        map_path="$BUILD_ROOT/ffmpeg.$variant.$size_mode.map"
        extra_ldflags="$extra_ldflags -Wl,-Map,$map_path"
    fi

    configure_args=(
        "${CAPABILITY_ARGS[@]}"
        "--prefix=$PRIVATE_ROOT"
        "--cc=$cc_path"
        "--extra-cflags=$extra_cflags"
        "--extra-ldflags=$extra_ldflags"
    )
    [[ "$allocator" == "mimalloc" ]] && \
        configure_args+=("--extra-libs=$MIMALLOC_OBJECT")

    mkdir -p "$build_dir"
    record_command "variant=$variant" "size_mode=$size_mode" \
        "$FFMPEG_SOURCE_DIR/configure" "${configure_args[@]}"
    (
        cd "$build_dir"
        "$FFMPEG_SOURCE_DIR/configure" "${configure_args[@]}" 2>&1 | tee "$configure_log"
        make -j "$jobs" ffmpeg
    )
    source_binary="$build_dir/ffmpeg"
    [[ -x "$source_binary" ]] || fail "$variant $size_mode ffmpeg binary missing"
    unstripped_size="$(stat -c '%s' "$source_binary")"
    cp -- "$source_binary" "$PAYLOAD/bin/$output_name"
    "$STRIP_TOOL" --strip-unneeded "$PAYLOAD/bin/$output_name"
    stripped_size="$(stat -c '%s' "$PAYLOAD/bin/$output_name")"
    printf '%s,%s,unstripped,%s\n' "$variant" "$size_mode" "$unstripped_size" >> "$SIZE_MATRIX"
    printf '%s,%s,stripped,%s\n' "$variant" "$size_mode" "$stripped_size" >> "$SIZE_MATRIX"
    if [[ "$variant" == "F2" && "$size_mode" == "baseline" ]]; then
        cp -- "$source_binary" "$BUILD_ROOT/ffmpeg.F2.unstripped"
    fi
    if [[ "$variant" == "F3" && "$size_mode" == "baseline" ]]; then
        [[ -s "$map_path" ]] || fail "F3 baseline linker map missing"
        cp -- "$map_path" "$PAYLOAD/share/ffmpeg.musl-mi.map"
        cp -- "$source_binary" "$BUILD_ROOT/ffmpeg.F3.unstripped"
    fi
}

build_one F1 baseline clang dynamic system
build_one F2 baseline "$MUSL_CC" static mallocng
build_one F3 baseline "$MUSL_CC" static mimalloc
build_one F1 gc clang dynamic system
build_one F2 gc "$MUSL_CC" static mallocng
build_one F3 gc "$MUSL_CC" static mimalloc

extract_section() {
    local source="$1"
    local plural="$2"
    local destination="$3"
    grep -Fqx "Enabled $plural:" "$source" || fail "configure summary lacks Enabled $plural"
    awk -v header="Enabled $plural:" '
        $0 == header { active=1; next }
        active && $0 == "" { exit }
        active { print }
    ' "$source" > "$destination"
}

extract_arm_summary() {
    local source="$1"
    local destination="$2"
    awk '
        /^ARCH[[:space:]]+/ { active=1 }
        active { print }
        active && /^THUMB enabled[[:space:]]+/ { exit }
    ' "$source" > "$destination"
    grep -q '^ARCH[[:space:]]\+arm ' "$destination" || fail "ARM summary is missing"
    grep -q '^NEON enabled[[:space:]]\+yes$' "$destination" || fail "NEON is not enabled"
}

reference_prefix="$BUILD_ROOT/equivalence-F1-baseline"
for plural in decoders demuxers parsers protocols hwaccels; do
    extract_section "$PAYLOAD/share/configure-F1-baseline.txt" "$plural" \
        "$reference_prefix-$plural"
done
extract_arm_summary "$PAYLOAD/share/configure-F1-baseline.txt" "$reference_prefix-arm"

decoder_tokens="$(tr '[:space:]' '\n' < "$reference_prefix-decoders" | sed '/^$/d')"
[[ "$decoder_tokens" == "h264" ]] || fail "enabled decoders must be exactly h264 actual=$decoder_tokens"
[[ ! -s "$reference_prefix-hwaccels" ]] || {
    cat "$reference_prefix-hwaccels" >&2
    fail "enabled hwaccels section is not empty"
}

for size_mode in baseline gc; do
    for variant in F1 F2 F3; do
        candidate_prefix="$BUILD_ROOT/equivalence-$variant-$size_mode"
        for plural in decoders demuxers parsers protocols hwaccels; do
            extract_section "$PAYLOAD/share/configure-$variant-$size_mode.txt" "$plural" \
                "$candidate_prefix-$plural"
            cmp -s "$reference_prefix-$plural" "$candidate_prefix-$plural" || \
                fail "configure $plural differ for $variant $size_mode"
        done
        extract_arm_summary "$PAYLOAD/share/configure-$variant-$size_mode.txt" \
            "$candidate_prefix-arm"
        cmp -s "$reference_prefix-arm" "$candidate_prefix-arm" || \
            fail "ARM optimization summary differs for $variant $size_mode"
        license_line="$(grep '^License: ' "$PAYLOAD/share/configure-$variant-$size_mode.txt" | tail -n 1)"
        [[ "$license_line" == License:\ LGPL* ]] || \
            fail "unexpected ffmpeg license for $variant $size_mode: $license_line"
        printf '%s,%s,configure_equivalence=PASS,%s\n' \
            "$variant" "$size_mode" "$license_line" >> "$EQUIVALENCE"
    done
done
{
    echo "decoder_exact=h264"
    echo "hwaccels=EMPTY"
    echo "arm_summary_diff=EMPTY"
    echo "configure_equivalence=PASS"
} >> "$EQUIVALENCE"
echo "gate.configure_equivalence=PASS decoder=h264 hwaccels=EMPTY arm_neon=identical"

F1_BIN="$PAYLOAD/bin/ffmpeg.F1"
F2_BIN="$PAYLOAD/bin/ffmpeg.F2"
F3_BIN="$PAYLOAD/bin/ffmpeg.F3"

interpreter_of() {
    readelf -lW "$1" | sed -n 's/.*interpreter: \([^]]*\).*/\1/p'
}
needed_of() {
    readelf -dW "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'
}
vfp_args_of() {
    local line
    line="$(readelf -AW "$1" | grep -m 1 'Tag_ABI_VFP_args' || true)"
    [[ -n "$line" ]] && printf '%s\n' "$line" || printf 'ABSENT\n'
}

for binary in "$F1_BIN" "$F2_BIN" "$F3_BIN"; do
    grep -Eq 'Class:[[:space:]]+ELF32' < <(readelf -hW "$binary") || fail "$binary is not ELF32"
    grep -Eq 'Machine:[[:space:]]+ARM' < <(readelf -hW "$binary") || fail "$binary is not ARM"
done

for binary in "$F2_BIN" "$F3_BIN"; do
    grep -q 'statically linked' < <(file "$binary") || fail "$binary is not static"
    ! grep -q 'INTERP' < <(readelf -lW "$binary") || fail "$binary has PT_INTERP"
    ! grep -q '(NEEDED)' < <(readelf -dW "$binary" 2>/dev/null) || fail "$binary has DT_NEEDED"
    ! grep -q 'GLIBC_' < <(readelf --all --wide "$binary") || fail "$binary has GLIBC symbol"
    ! grep -q 'GLIBC_' < <(strings -a "$binary") || fail "$binary has GLIBC string"
done

f1_interp="$(interpreter_of "$F1_BIN")"
[[ "$f1_interp" == /lib/* ]] || fail "F1 loader is not under /lib: ${f1_interp:-NONE}"
f1_needed="$(needed_of "$F1_BIN")"
grep -q '^libc\.so\.6$' <<< "$f1_needed" || fail "F1 does not need libc.so.6"
while IFS= read -r needed; do
    case "$needed" in
        libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|ld-linux.so.3) ;;
        *) fail "F1 unexpected DT_NEEDED=$needed" ;;
    esac
done <<< "$f1_needed"
{
    echo "f1_interpreter=$f1_interp"
    printf 'f1_needed=%s\n' "${f1_needed//$'\n'/,}"
} >> "$DECISION"

f1_vfp="$(vfp_args_of "$F1_BIN")"
f2_vfp="$(vfp_args_of "$F2_BIN")"
f3_vfp="$(vfp_args_of "$F3_BIN")"
binsh_vfp="$(vfp_args_of /bin/sh)"
[[ "$f1_vfp" == "$f2_vfp" && "$f1_vfp" == "$f3_vfp" && "$f1_vfp" == "$binsh_vfp" ]] || \
    fail "softfp ABI tags differ across variants or chroot /bin/sh"
[[ "$f1_vfp" != *"VFP registers"* ]] || fail "variants are hard-float tagged"
{
    printf 'variant_vfp_args=F1:%s | F2:%s | F3:%s\n' "$f1_vfp" "$f2_vfp" "$f3_vfp"
    echo "binsh_vfp_args=$binsh_vfp"
    echo "abi_consistency=PASS"
} >> "$DECISION"
echo "gate.elf_softfp=PASS"

MI_MAP="$PAYLOAD/share/ffmpeg.musl-mi.map"
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
    evidence="$(map_symbol_owner "$symbol")"
    owner="${evidence%%$'\t'*}"
    [[ "$owner" == "mimalloc.o" ]] || fail "$symbol owner is not mimalloc.o evidence=${evidence:-MISSING}"
    printf 'gate.mimalloc_symbol.%s=PASS\t%s\n' "$symbol" "$evidence"
done
forbidden_allocator_members="$(grep -E \
    'libc[.]a[(](malloc|free|calloc|realloc|memalign|aligned_alloc|malloc_usable_size)[.]lo[)]' \
    "$MI_MAP" || true)"
[[ -z "$forbidden_allocator_members" ]] || {
    printf '%s\n' "$forbidden_allocator_members" >&2
    fail "musl mallocng allocator members were extracted into F3"
}
mi_symbol_line="$(nm "$BUILD_ROOT/ffmpeg.F3.unstripped" | grep -m 1 -E '[[:space:]][Tt][[:space:]]+mi_[A-Za-z0-9_]+$' || true)"
[[ -n "$mi_symbol_line" ]] || fail "F3 has no mi_ prefixed text symbol"
{
    echo "mimalloc_symbol_owner=mimalloc.o"
    echo "mimalloc_mallocng_members_extracted=0"
    echo "mimalloc_symbol_gate=PASS"
    echo "mimalloc_nm_evidence=$mi_symbol_line"
} >> "$DECISION"
echo "gate.mimalloc_link_map=PASS owner=mimalloc.o mallocng_members=0"

for symbol in strcoll iconv setlocale getaddrinfo; do
    matches="$(nm -a "$BUILD_ROOT/ffmpeg.F2.unstripped" | grep -E "[[:space:]]${symbol}$" || true)"
    if [[ -n "$matches" ]]; then
        printf '%s=PRESENT\n%s\n' "$symbol" "$matches" >> "$FUNCTION_SURFACE"
    else
        printf '%s=ABSENT\n' "$symbol" >> "$FUNCTION_SURFACE"
    fi
done

find "$FFMPEG_SOURCE_DIR" -type f -print | sort | while IFS= read -r source_file; do
    sha256sum "$source_file"
done > "$BUILD_ROOT/ffmpeg-source-manifest.after"
diff -u "$BUILD_ROOT/ffmpeg-source-manifest.before" \
    "$BUILD_ROOT/ffmpeg-source-manifest.after" > "$PAYLOAD/share/c8a-source-diff.txt" || \
    fail "ffmpeg frozen source tree was modified during island build"
{
    echo "C8a.ffmpeg_source_diff_outside_frozen_tree=0"
    echo "C8a.baseline=frozen_Tizen_tree"
    echo "C8b.1=new_isolated_rpm_spec_and_private_prefix"
    echo "C8b.2=frozen_archive_normalized_in_prep"
    echo "C8b.3=minimal_software_decode_configure_capability_set"
    echo "C8b.4=musl_wrapper_start_group_reused"
    echo "C8b.5=mimalloc_object_added_via_extra_libs"
    echo "C8b.semantic_workaround=NONE"
} > "$C8_LEDGER"
cp -- "$FFMPEG_SOURCE_DIR/packaging/ffmpeg.spec" "$PAYLOAD/share/tizen-ffmpeg-spec.orig"

clang "${OPTFLAGS_ARRAY[@]}" "$TIMER_SOURCE" "$RTLIB_FLAG" -static-libgcc -pthread \
    -o "$PAYLOAD/bin/timer"

(
    cd "$PAYLOAD"
    sha256sum bin/* > share/artifacts.sha256
)
echo "ffmpeg_license=$(grep '^License: ' "$PAYLOAD/share/configure-F1-baseline.txt" | tail -n 1 | sed 's/^License: //')" >> "$DECISION"
echo "mechanical_gates=PASS" >> "$DECISION"
echo "BUILD_GATE_PASS: ffmpeg F1/F2/F3 and size matrix passed"
