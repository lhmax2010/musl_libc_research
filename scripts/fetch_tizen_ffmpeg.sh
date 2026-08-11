#!/usr/bin/env bash
# Freeze the first observed Tizen ffmpeg commit and archive its provenance.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
REMOTE_URL="git://review.tizen.org/git/platform/upstream/ffmpeg"
REMOTE_BRANCH="tizen"
SOURCE_DIR="${FFMPEG_SOURCE_DIR:-$ROOT_DIR/tmp/ffmpeg-tizen}"
COMMIT_FILE="$ROOT_DIR/packaging/ffmpeg-tizen.commit"
ARCHIVE_NAME="ffmpeg-tizen-src.tar.gz.frozen"
ARCHIVE="$ROOT_DIR/packaging/$ARCHIVE_NAME"
HASH_FILE="$ROOT_DIR/packaging/ffmpeg-tizen-src.sha256"
PROVENANCE="$ROOT_DIR/results/logs/ffmpeg-src-provenance.txt"
FETCH_LOG="$ROOT_DIR/results/logs/fetch-tizen-ffmpeg.log"
SPEC_ARCHIVE="$ROOT_DIR/share/tizen-ffmpeg-spec.orig"
PATCH_ARCHIVE="$ROOT_DIR/share/tizen-ffmpeg-patch-sequence.orig"
REVIEW_FILE="$ROOT_DIR/results/logs/ffmpeg-source-review.md"

mkdir -p "$ROOT_DIR/packaging" "$ROOT_DIR/results/logs" "$ROOT_DIR/share" \
    "$(dirname -- "$SOURCE_DIR")"
touch "$FETCH_LOG"
printf '\n' >> "$FETCH_LOG"

log() {
    printf '%s\n' "$*" | tee -a "$FETCH_LOG"
}

fail() {
    log "FFMPEG_FETCH_FAIL: $*"
    exit 1
}

for tool in awk chmod cmp cp date find git grep gzip mkdir mktemp mv sed sha256sum sort tee tr; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
done

log "fetch_started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "remote=$REMOTE_URL"
log "branch=$REMOTE_BRANCH"
log "source_dir=$SOURCE_DIR"

first_freeze=0
if [[ ! -e "$SOURCE_DIR" ]]; then
    log "command=git clone \"$REMOTE_URL\" -b $REMOTE_BRANCH $SOURCE_DIR"
    git clone "$REMOTE_URL" -b "$REMOTE_BRANCH" "$SOURCE_DIR" 2>&1 | tee -a "$FETCH_LOG"
elif [[ ! -d "$SOURCE_DIR/.git" ]]; then
    fail "source path exists but is not a git checkout: $SOURCE_DIR"
else
    log "clone=SKIP existing_checkout"
fi

actual_remote="$(git -C "$SOURCE_DIR" remote get-url origin)"
[[ "$actual_remote" == "$REMOTE_URL" ]] || \
    fail "origin mismatch expected=$REMOTE_URL actual=$actual_remote"

head_commit="$(git -C "$SOURCE_DIR" rev-parse --verify HEAD)"
[[ "$head_commit" =~ ^[0-9a-f]{40}$ ]] || fail "invalid HEAD: $head_commit"

if [[ -f "$COMMIT_FILE" ]]; then
    frozen_commit="$(awk 'NF { print tolower($1); exit }' "$COMMIT_FILE")"
    [[ "$frozen_commit" =~ ^[0-9a-f]{40}$ ]] || \
        fail "invalid frozen commit file: $COMMIT_FILE"
else
    frozen_commit="$head_commit"
    printf '%s\n' "$frozen_commit" > "$COMMIT_FILE"
    first_freeze=1
    log "freeze=CREATE"
fi

[[ "$head_commit" == "$frozen_commit" ]] || \
    fail "checkout is not the frozen commit expected=$frozen_commit actual=$head_commit"

status_porcelain="$(git -C "$SOURCE_DIR" status --porcelain)"
[[ -z "$status_porcelain" ]] || {
    printf '%s\n' "$status_porcelain" | tee -a "$FETCH_LOG"
    fail "source checkout is dirty"
}
log "checkout_commit=$head_commit"
log "checkout_status=clean"

spec_path="$SOURCE_DIR/packaging/ffmpeg.spec"
[[ -f "$spec_path" ]] || fail "Tizen spec not found at packaging/ffmpeg.spec"

if (( first_freeze == 0 )) && \
   [[ -f "$ARCHIVE" && -f "$HASH_FILE" && -f "$PROVENANCE" && \
      -f "$SPEC_ARCHIVE" && -f "$PATCH_ARCHIVE" && -f "$REVIEW_FILE" ]]; then
    existing_hash="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
    recorded_hash="$(awk 'NF { print tolower($1); exit }' "$HASH_FILE")"
    embedded_commit="$(git get-tar-commit-id < <(gzip -cd "$ARCHIVE"))"
    if [[ "$existing_hash" == "$recorded_hash" && \
          "$embedded_commit" == "$frozen_commit" ]] && \
       cmp -s "$spec_path" "$SPEC_ARCHIVE" && \
       grep -Fqx "frozen_commit=$frozen_commit" "$PROVENANCE" && \
       grep -Fqx "archive_embedded_commit=$frozen_commit" "$PROVENANCE" && \
       grep -Eq '^patch_declaration_count=[0-9]+$' "$PROVENANCE" && \
       grep -Fq -- "- Frozen commit: \`$frozen_commit\`" "$REVIEW_FILE"; then
        log "short_circuit=PASS frozen checkout and all archived evidence match"
        log "frozen_commit=$frozen_commit"
        log "archive_sha256=$existing_hash"
        log "source_review=REQUIRED"
        log "fetch_finished=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        log "FFMPEG_FETCH_PASS"
        exit 0
    fi
    log "short_circuit=MISS archived evidence requires regeneration"
fi

cp -- "$spec_path" "$SPEC_ARCHIVE"

{
    printf '# Tizen ffmpeg patch declarations and prep sequence\n'
    printf '# frozen_commit=%s\n' "$frozen_commit"
    printf '# source=packaging/ffmpeg.spec\n\n'
    printf '## Patch declarations\n'
    grep -nE '^[[:space:]]*Patch[0-9]*:' "$spec_path" || true
    printf '\n## Prep section (verbatim)\n'
    awk '
        /^%prep([[:space:]]|$)/ { in_prep=1 }
        in_prep && /^%(build|install|check|clean|files|package|description|pre|post|preun|postun|triggerin|triggerun|triggerpostun)([[:space:]]|$)/ { exit }
        in_prep { print }
    ' "$spec_path"
    printf '\n## Patch files in packaging (path and sha256)\n'
    while IFS= read -r patch_path; do
        printf '%s  %s\n' "$(sha256sum "$patch_path" | awk '{print $1}')" \
            "${patch_path#"$SOURCE_DIR/"}"
    done < <(find "$SOURCE_DIR/packaging" -maxdepth 1 -type f \
        \( -name '*.patch' -o -name '*.diff' \) -print | sort)
} > "$PATCH_ARCHIVE"

patch_declaration_count="$(grep -Ec '^[[:space:]]*Patch[0-9]*:' "$spec_path" || true)"
patch_file_count="$(find "$SOURCE_DIR/packaging" -maxdepth 1 -type f \
    \( -name '*.patch' -o -name '*.diff' \) -print | awk 'END { print NR + 0 }')"
prep_patch_apply_count="$(grep -Ec '^[[:space:]]*%patch([[:space:]]|[0-9]|$)' "$PATCH_ARCHIVE" || true)"

release_value="ABSENT"
if [[ -f "$SOURCE_DIR/RELEASE" ]]; then
    release_value="$(sed -n '1,20p' "$SOURCE_DIR/RELEASE" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
fi

version_header="$SOURCE_DIR/libavutil/version.h"
version_lines="ABSENT"
if [[ -f "$version_header" ]]; then
    version_lines="$(grep -E '^[[:space:]]*#define[[:space:]]+(LIBAVUTIL_VERSION_(MAJOR|MINOR|MICRO)|FFMPEG_VERSION)' "$version_header" || true)"
    [[ -n "$version_lines" ]] || version_lines="NO_MATCHING_VERSION_DEFINES"
fi

archive_tmp="$(mktemp "$ROOT_DIR/packaging/.ffmpeg-tizen-src.XXXXXXXX.tar.gz")"
trap 'rm -f -- "$archive_tmp"' EXIT HUP INT TERM
git -C "$SOURCE_DIR" archive --format=tar.gz --prefix=ffmpeg-tizen-src/ \
    --output="$archive_tmp" "$frozen_commit"
archive_sha256="$(sha256sum "$archive_tmp" | awk '{print tolower($1)}')"

if [[ -f "$ARCHIVE" && -f "$HASH_FILE" ]]; then
    old_frozen="$(awk 'NF { print tolower($1); exit }' "$HASH_FILE")"
    old_actual="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
    [[ "$old_frozen" == "$old_actual" ]] || \
        fail "existing frozen archive does not match its digest"
    [[ "$archive_sha256" == "$old_frozen" ]] || \
        fail "git archive is not stable for frozen commit expected=$old_frozen actual=$archive_sha256"
    rm -f -- "$archive_tmp"
    trap - EXIT HUP INT TERM
    log "archive_reproducibility=PASS frozen checkout produces identical archive"
else
    mv -- "$archive_tmp" "$ARCHIVE"
    trap - EXIT HUP INT TERM
    printf '%s  %s\n' "$archive_sha256" "$ARCHIVE_NAME" > "$HASH_FILE"
    log "archive=CREATE"
fi

archive_actual="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
hash_frozen="$(awk 'NF { print tolower($1); exit }' "$HASH_FILE")"
[[ "$archive_actual" == "$hash_frozen" ]] || fail "final archive digest mismatch"
archive_embedded_commit="$(git get-tar-commit-id < <(gzip -cd "$ARCHIVE"))"
[[ "$archive_embedded_commit" == "$frozen_commit" ]] || \
    fail "archive commit mismatch expected=$frozen_commit actual=$archive_embedded_commit"

{
    printf 'Tizen ffmpeg frozen source provenance\n'
    printf 'generated_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'remote_url=%s\n' "$REMOTE_URL"
    printf 'remote_branch=%s\n' "$REMOTE_BRANCH"
    printf 'frozen_commit=%s\n' "$frozen_commit"
    printf 'checkout_head=%s\n' "$head_commit"
    printf 'checkout_status_porcelain=EMPTY\n'
    printf 'archive=%s\n' "packaging/$ARCHIVE_NAME"
    printf 'archive_sha256=%s\n' "$archive_actual"
    printf 'archive_embedded_commit=%s\n' "$archive_embedded_commit"
    printf 'release_file=%s\n' "$release_value"
    printf 'patch_declaration_count=%s\n' "$patch_declaration_count"
    printf 'patch_file_count=%s\n' "$patch_file_count"
    printf 'prep_patch_apply_count=%s\n' "$prep_patch_apply_count"
    printf '\n[git log -1 --decorate=full --date=iso-strict --format=fuller]\n'
    git -C "$SOURCE_DIR" log -1 --decorate=full --date=iso-strict --format=fuller
    printf '\n[libavutil/version.h extracted defines]\n%s\n' "$version_lines"
    printf '\n[Tizen packaging spec]\npath=packaging/ffmpeg.spec\n'
    printf 'archived_as=share/tizen-ffmpeg-spec.orig\n'
    printf 'sha256=%s\n' "$(sha256sum "$SPEC_ARCHIVE" | awk '{print $1}')"
    printf '\n[Tizen patch declarations and prep sequence]\n'
    printf 'archived_as=share/tizen-ffmpeg-patch-sequence.orig\n'
    printf 'sha256=%s\n' "$(sha256sum "$PATCH_ARCHIVE" | awk '{print $1}')"
    printf '\n[git status --porcelain]\n<EMPTY>\n'
} > "$PROVENANCE"

if [[ ! -f "$REVIEW_FILE" ]]; then
    {
        printf '# Tizen ffmpeg frozen commit review gate\n\n'
        printf -- '- [ ] FatTank verified the frozen Tizen ffmpeg commit and archived provenance.\n\n'
        printf 'Formal GBS build is fail-closed until FatTank changes the checkbox above to `[x]`.\n'
        printf 'Automation must not check it on FatTank\x27s behalf.\n\n'
        printf '## Frozen source\n\n'
        printf -- '- Remote: `%s`\n' "$REMOTE_URL"
        printf -- '- Branch observed at first fetch: `%s`\n' "$REMOTE_BRANCH"
        printf -- '- Frozen commit: `%s`\n' "$frozen_commit"
        printf -- '- Archive SHA-256: `%s`\n\n' "$archive_actual"
        printf -- '- Tizen spec Patch declarations: `%s`\n' "$patch_declaration_count"
        printf -- '- Patch files in `packaging/`: `%s`\n\n' "$patch_file_count"
        printf 'Evidence: `results/logs/ffmpeg-src-provenance.txt`, '
        printf '`share/tizen-ffmpeg-spec.orig`, and '
        printf '`share/tizen-ffmpeg-patch-sequence.orig`.\n'
    } > "$REVIEW_FILE"
fi

chmod 0644 "$ARCHIVE" "$COMMIT_FILE" "$HASH_FILE" "$PROVENANCE" \
    "$SPEC_ARCHIVE" "$PATCH_ARCHIVE" "$REVIEW_FILE"

log "first_freeze=$first_freeze"
log "frozen_commit=$frozen_commit"
log "archive_sha256=$archive_actual"
log "patch_declaration_count=$patch_declaration_count"
log "patch_file_count=$patch_file_count"
log "prep_patch_apply_count=$prep_patch_apply_count"
log "provenance=$PROVENANCE"
log "source_review=REQUIRED"
log "fetch_finished=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "FFMPEG_FETCH_PASS"
