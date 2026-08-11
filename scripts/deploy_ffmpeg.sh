#!/usr/bin/env bash
# Install the FFmpeg island RPM, freeze the single board clip, and run smoke gates.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET="${SDB_TARGET:-192.168.108.26}"
RESULTS_DIR="$ROOT_DIR/results"
LOG_DIR="$RESULTS_DIR/logs"
LOG_FILE="${DEPLOY_LOG_FILE:-$LOG_DIR/deploy-ffmpeg.log}"
PRIVATE_ROOT="/opt/usr/ffmpeg-demo"
CLIP_HASH_FILE="$ROOT_DIR/packaging/ffmpeg-testclip.sha256"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-demo-rpm.XXXXXXXX")"
trap 'rm -rf -- "$EXTRACT_DIR"' EXIT HUP INT TERM

for tool in awk basename cpio diff grep rpm2cpio sdb sed sha256sum sort tee; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR required host tool missing: $tool" >&2
        exit 2
    }
done
[[ -f "$CLIP_HASH_FILE" ]] || {
    echo "ERROR frozen clip hash missing: $CLIP_HASH_FILE" >&2
    exit 2
}

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

if [[ -n "${RPM_PATH:-}" ]]; then
    rpm_path="$RPM_PATH"
else
    rpm_path="$(
        find "$RESULTS_DIR/rpms" -maxdepth 1 -type f \
            -name 'ffmpeg-musl-demo-*.armv7l.rpm' -printf '%T@ %p\n' \
            | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
fi
[[ -n "$rpm_path" && -f "$rpm_path" ]] || {
    echo "ERROR ffmpeg armv7l RPM not found" | tee -a "$LOG_FILE" >&2
    exit 3
}
rpm_base="$(basename "$rpm_path")"
[[ "$rpm_base" =~ ^[A-Za-z0-9._+-]+$ ]] || {
    echo "ERROR unsafe RPM basename: $rpm_base" | tee -a "$LOG_FILE" >&2
    exit 3
}
remote_rpm="/tmp/$rpm_base"

(
    cd "$EXTRACT_DIR"
    rpm2cpio "$rpm_path" | cpio --quiet -idm
)
HOST_PAYLOAD="$EXTRACT_DIR$PRIVATE_ROOT"
[[ -d "$HOST_PAYLOAD/bin" && -f "$HOST_PAYLOAD/share/artifacts.sha256" ]] || {
    echo "ERROR RPM private payload incomplete" | tee -a "$LOG_FILE" >&2
    exit 4
}
(
    cd "$HOST_PAYLOAD"
    sha256sum -c share/artifacts.sha256
) | tee -a "$LOG_FILE"
(
    cd "$HOST_PAYLOAD"
    sha256sum bin/* | sort -k2
) > "$EXTRACT_DIR/host-bin.sha256"

run_logged() {
    "$@" 2>&1 | tr -d '\r' | tee -a "$LOG_FILE"
}

remote_capture() {
    sdb -s "$sdb_serial" shell "$1" </dev/null 2>&1 | tr -d '\r'
}

echo "target=$TARGET" | tee -a "$LOG_FILE"
echo "rpm=$rpm_path" | tee -a "$LOG_FILE"
echo "rpm_sha256=$(sha256sum "$rpm_path" | awk '{print $1}')" | tee -a "$LOG_FILE"
run_logged sdb connect "$TARGET"
if [[ -n "${SDB_SERIAL:-}" ]]; then
    sdb_serial="$SDB_SERIAL"
else
    sdb_serial="$(
        sdb devices | awk -v target="$TARGET" '
            $2 == "device" && ($1 == target || index($1, target ":") == 1) {
                print $1
            }
        '
    )"
fi
[[ -n "$sdb_serial" && "$sdb_serial" != *$'\n'* ]] || {
    echo "ERROR expected exactly one SDB serial for target=$TARGET" \
        | tee -a "$LOG_FILE" >&2
    exit 2
}
echo "sdb_serial=$sdb_serial" | tee -a "$LOG_FILE"
run_logged sdb -s "$sdb_serial" root on

media_listing="$(remote_capture 'find /root -maxdepth 1 -type f 2>/dev/null')"
printf 'root_file_listing_begin\n%s\nroot_file_listing_end\n' "$media_listing" \
    | tee -a "$LOG_FILE"
media_candidates=()
while IFS= read -r path; do
    case "${path,,}" in
        *.mp4|*.h264|*.mkv) media_candidates+=("$path") ;;
    esac
done <<< "$media_listing"
[[ "${#media_candidates[@]}" -eq 1 ]] || {
    printf 'DEPLOY_FAIL media_candidate_count=%s\n' "${#media_candidates[@]}" \
        | tee -a "$LOG_FILE" >&2
    printf 'media_candidate=%s\n' "${media_candidates[@]}" | tee -a "$LOG_FILE" >&2
    exit 7
}
source_clip="${media_candidates[0]}"
[[ "$source_clip" != *$'\n'* && "$source_clip" != *"'"* ]] || {
    echo "DEPLOY_FAIL unsafe media path: $source_clip" | tee -a "$LOG_FILE" >&2
    exit 7
}
expected_clip_hash="$(awk 'NF && $1 !~ /^#/ {print tolower($1); exit}' "$CLIP_HASH_FILE")"
expected_clip_name="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$CLIP_HASH_FILE")"
[[ "$expected_clip_hash" =~ ^[0-9a-f]{64}$ ]] || {
    echo "DEPLOY_FAIL invalid frozen clip digest" | tee -a "$LOG_FILE" >&2
    exit 7
}
[[ "$(basename "$source_clip")" == "$expected_clip_name" ]] || {
    echo "DEPLOY_FAIL clip basename differs from frozen record" | tee -a "$LOG_FILE" >&2
    exit 7
}
actual_clip_hash="$(remote_capture "sha256sum '$source_clip'" | awk '{print tolower($1)}')"
[[ "$actual_clip_hash" == "$expected_clip_hash" ]] || {
    echo "DEPLOY_FAIL clip sha256 expected=$expected_clip_hash actual=$actual_clip_hash" \
        | tee -a "$LOG_FILE" >&2
    exit 7
}
echo "clip.source=$source_clip" | tee -a "$LOG_FILE"
echo "clip.sha256=$actual_clip_hash" | tee -a "$LOG_FILE"

run_logged sdb -s "$sdb_serial" push "$rpm_path" "$remote_rpm"
set +e
sdb -s "$sdb_serial" shell "rpm -Uvh --noplugins --force '$remote_rpm'" </dev/null 2>&1 \
    | tr -d '\r' | tee -a "$LOG_FILE"
install_rc=${PIPESTATUS[0]}
set -e
[[ "$install_rc" -eq 0 ]] || {
    echo "DEPLOY_FAIL rpm_install_rc=$install_rc" | tee -a "$LOG_FILE" >&2
    exit "$install_rc"
}

remote_capture "cd '$PRIVATE_ROOT' && sha256sum -c share/artifacts.sha256" \
    | tee -a "$LOG_FILE"
remote_capture "cd '$PRIVATE_ROOT' && sha256sum bin/*" \
    | sort -k2 > "$EXTRACT_DIR/board-bin.sha256"
if ! diff -u "$EXTRACT_DIR/host-bin.sha256" "$EXTRACT_DIR/board-bin.sha256" \
    | tee -a "$LOG_FILE"; then
    echo "DEPLOY_FAIL board binary hashes differ" | tee -a "$LOG_FILE" >&2
    exit 5
fi
echo "binary_hash_comparison=PASS" | tee -a "$LOG_FILE"
remote_capture "ls -Z '$PRIVATE_ROOT/bin' '$PRIVATE_ROOT/share'" | tee -a "$LOG_FILE"

remote_clip="$PRIVATE_ROOT/data/testclip.mp4"
remote_capture "mkdir -p '$PRIVATE_ROOT/data' && cp '$source_clip' '$remote_clip' && sha256sum '$remote_clip'" \
    | tee -a "$LOG_FILE"
copied_clip_hash="$(remote_capture "sha256sum '$remote_clip'" | awk '{print tolower($1)}')"
[[ "$copied_clip_hash" == "$expected_clip_hash" ]] || {
    echo "DEPLOY_FAIL copied clip hash mismatch" | tee -a "$LOG_FILE" >&2
    exit 7
}
echo "clip.copy=$remote_clip" | tee -a "$LOG_FILE"
echo "clip_copy_hash_gate=PASS" | tee -a "$LOG_FILE"

for variant in F1 F2 F3; do
    echo "smoke.variant=$variant" | tee -a "$LOG_FILE"
    remote_capture "'$PRIVATE_ROOT/bin/ffmpeg.$variant' -version" | tee -a "$LOG_FILE"
    decoder_output="$(remote_capture "'$PRIVATE_ROOT/bin/ffmpeg.$variant' -decoders")"
    printf 'decoders.%s.begin\n%s\ndecoders.%s.end\n' \
        "$variant" "$decoder_output" "$variant" | tee -a "$LOG_FILE"
    h264_rows="$(grep -E '^[[:space:]]*V[^[:space:]]*[[:space:]]+h264[[:space:]]' <<< "$decoder_output" || true)"
    [[ "$(grep -c . <<< "$h264_rows")" -eq 1 ]] || {
        echo "DEPLOY_FAIL $variant native h264 decoder row count is not one" | tee -a "$LOG_FILE" >&2
        exit 6
    }
    ! grep -Eqi 'h264_(v4l2m2m|mmal|omx)|h264.*hardware' <<< "$decoder_output" || {
        echo "DEPLOY_FAIL $variant hardware h264 decoder visible" | tee -a "$LOG_FILE" >&2
        exit 6
    }
    smoke_output="$(remote_capture "'$PRIVATE_ROOT/bin/ffmpeg.$variant' -nostdin -hide_banner -v info -xerror -c:v h264 -i '$remote_clip' -map 0:v:0 -an -frames:v 1 -f null -; rc=\$?; printf 'smoke_remote_rc=%s\\n' \"\$rc\"")"
    printf '%s\n' "$smoke_output" | tee -a "$LOG_FILE"
    smoke_rc="$(sed -n 's/^smoke_remote_rc=//p' <<< "$smoke_output" | tail -n 1)"
    smoke_frames="$(sed -n 's/.*frame=[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
        <<< "$smoke_output" | tail -n 1)"
    [[ "$smoke_rc" =~ ^[0-9]+$ && "$smoke_rc" -eq 0 ]] || {
        echo "DEPLOY_FAIL $variant h264 smoke remote_rc=${smoke_rc:-MISSING}" \
            | tee -a "$LOG_FILE" >&2
        exit 6
    }
    [[ "$smoke_frames" =~ ^[0-9]+$ && "$smoke_frames" -ge 1 ]] || {
        echo "DEPLOY_FAIL $variant h264 smoke produced no frame count=${smoke_frames:-MISSING}" \
            | tee -a "$LOG_FILE" >&2
        exit 6
    }
    echo "gate.smoke.$variant=PASS decoder=h264 frames=$smoke_frames" | tee -a "$LOG_FILE"
done

runtime_banner_gate() {
    local variant="$1"
    local expected="$2"
    local output stderr_text probe_rc
    local remote_out="/tmp/ffmpeg-banner-$variant.out"
    local remote_err="/tmp/ffmpeg-banner-$variant.err"
    output="$(remote_capture "MIMALLOC_VERBOSE=1 '$PRIVATE_ROOT/bin/ffmpeg.$variant' -version >'$remote_out' 2>'$remote_err'; rc=\$?; printf 'stdout_begin\\n'; cat '$remote_out'; printf 'stdout_end\\nstderr_begin\\n'; cat '$remote_err'; printf 'stderr_end\\nremote_probe_rc=%s\\n' \"\$rc\"; rm -f '$remote_out' '$remote_err'")"
    probe_rc="$(sed -n 's/^remote_probe_rc=//p' <<< "$output" | tail -n 1)"
    printf 'banner.variant=%s expected=%s remote_rc=%s\n%s\n' \
        "$variant" "$expected" "$probe_rc" "$output" | tee -a "$LOG_FILE"
    [[ "$probe_rc" =~ ^[0-9]+$ && "$probe_rc" -eq 0 ]] || exit 6
    stderr_text="$(awk '/^stderr_begin$/ {active=1; next} /^stderr_end$/ {active=0} active' <<< "$output")"
    if [[ "$expected" == present ]]; then
        grep -q '^mimalloc:' <<< "$stderr_text" || {
            echo "DEPLOY_FAIL mimalloc banner absent for $variant" | tee -a "$LOG_FILE" >&2
            exit 6
        }
    elif grep -q '^mimalloc:' <<< "$stderr_text"; then
        echo "DEPLOY_FAIL unexpected mimalloc banner for $variant" | tee -a "$LOG_FILE" >&2
        exit 6
    fi
    echo "gate.runtime_mimalloc_banner.$variant=PASS expected=$expected" | tee -a "$LOG_FILE"
}

runtime_banner_gate F3 present
runtime_banner_gate F1 absent
runtime_banner_gate F2 absent
echo "gate.runtime_mimalloc_override=PASS positive=1 negative_controls=2" | tee -a "$LOG_FILE"
echo "DEPLOY_FFMPEG_PASS clip_sha256=$expected_clip_hash" | tee -a "$LOG_FILE"
