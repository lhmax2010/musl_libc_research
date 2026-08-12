#!/usr/bin/env bash
# Fetch rpmalloc 1.4.5 and validate its frozen digest against archived sources.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="1.4.5"
ARCHIVE_NAME="rpmalloc-${VERSION}.tar.gz"
FROZEN_ARCHIVE_NAME="$ARCHIVE_NAME.frozen"
ARCHIVE="$ROOT_DIR/packaging/$FROZEN_ARCHIVE_NAME"
FROZEN="$SCRIPT_DIR/rpmalloc-${VERSION}.sha256"
PACKAGING_FROZEN="$ROOT_DIR/packaging/rpmalloc-${VERSION}.sha256"
LOG_DIR="$ROOT_DIR/results/logs"
EVIDENCE_DIR="$LOG_DIR/rpmalloc-hash-sources"
LOG_FILE="$LOG_DIR/fetch-rpmalloc.log"
OFFICIAL_URL="https://github.com/mjansson/rpmalloc/archive/refs/tags/${VERSION}.tar.gz"
GITHUB_RELEASE_URL="https://api.github.com/repos/mjansson/rpmalloc/releases/tags/${VERSION}"
XMAKE_COMMIT="34812a68d605778d664af2b70e03d17de93d731c"
XMAKE_RECORD_URL="https://raw.githubusercontent.com/xmake-io/xmake-repo/$XMAKE_COMMIT/packages/r/rpmalloc/xmake.lua"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fetch-rpmalloc.XXXXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$ROOT_DIR/packaging" "$EVIDENCE_DIR"
: > "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

fail() {
    log "RPMALLOC_FETCH_FAIL: $*"
    exit 1
}

download() {
    local url="$1"
    local destination="$2"
    curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 \
        --output "$destination" "$url"
}

for tool in awk cp curl date grep head mkdir sed sha256sum tar tee; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
done
[[ -f "$FROZEN" ]] || fail "frozen digest file missing: $FROZEN"

frozen_sha256="$(awk 'NF { print tolower($1); exit }' "$FROZEN")"
[[ "$frozen_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid frozen sha256"

candidate="$TMP_DIR/$ARCHIVE_NAME"
github_release="$EVIDENCE_DIR/github-release-${VERSION}.json"
xmake_record="$EVIDENCE_DIR/xmake-rpmalloc.$XMAKE_COMMIT.lua"

log "fetch_started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "version=$VERSION"
log "official_url=$OFFICIAL_URL"
download "$OFFICIAL_URL" "$candidate" || fail "official archive unavailable"

actual_sha256="$(sha256sum "$candidate" | awk '{print tolower($1)}')"
log "official_sha256=$actual_sha256"
[[ "$actual_sha256" == "$frozen_sha256" ]] || \
    fail "frozen sha256 mismatch expected=$frozen_sha256 actual=$actual_sha256"
log "frozen_sha256_verdict=PASS"

archive_listing="$TMP_DIR/archive.list"
tar -tzf "$candidate" > "$archive_listing"
archive_root="$(sed -n '1p' "$archive_listing")"
[[ "$archive_root" == "rpmalloc-${VERSION}/" ]] || \
    fail "unexpected archive root: $archive_root"
for required_path in rpmalloc/rpmalloc.c rpmalloc/malloc.c rpmalloc/rpmalloc.h LICENSE; do
    grep -Fxq "rpmalloc-${VERSION}/$required_path" "$archive_listing" || \
        fail "archive member missing: $required_path"
done
log "archive_layout_verdict=PASS"

download "$GITHUB_RELEASE_URL" "$github_release" || \
    fail "GitHub release record unavailable"
github_tag="$(sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' "$github_release" | head -n 1)"
github_page="$(sed -n 's/^[[:space:]]*"html_url":[[:space:]]*"\([^"]*\)".*/\1/p' "$github_release" | head -n 1)"
[[ "$github_tag" == "$VERSION" ]] || fail "GitHub release tag mismatch: $github_tag"
[[ "$github_page" == "https://github.com/mjansson/rpmalloc/releases/tag/$VERSION" ]] || \
    fail "GitHub release page mismatch: $github_page"
log "source=github-release tag=$github_tag page=$github_page"
log "source_verdict.github_release=PASS"

download "$XMAKE_RECORD_URL" "$xmake_record" || \
    fail "xmake package record unavailable"
xmake_sha256="$(sed -n 's/.*add_versions("1\.4\.5",[[:space:]]*"\([0-9a-fA-F]\{64\}\)").*/\1/p' "$xmake_record" | head -n 1 | tr '[:upper:]' '[:lower:]')"
[[ "$xmake_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "xmake sha256 missing"
[[ "$xmake_sha256" == "$actual_sha256" ]] || \
    fail "xmake sha256 mismatch expected=$actual_sha256 actual=$xmake_sha256"
log "source=xmake-repo commit=$XMAKE_COMMIT version=$VERSION sha256=$xmake_sha256"
log "source_verdict.xmake_repo=PASS"

cp -p -- "$candidate" "$ARCHIVE"
cp -p -- "$FROZEN" "$PACKAGING_FROZEN"
archive_sha256="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
[[ "$archive_sha256" == "$frozen_sha256" ]] || fail "copied archive verification failed"
cmp -s "$FROZEN" "$PACKAGING_FROZEN" || fail "packaging digest copy differs"
log "archive=$ARCHIVE"
log "archive_sha256=$archive_sha256"
log "packaging_digest_copy=$PACKAGING_FROZEN"
log "independent_sources_confirmed=2"
log "validation=PASS"
log "source_review=REQUIRED before formal GBS build"
log "fetch_finished=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
