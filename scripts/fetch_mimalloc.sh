#!/usr/bin/env bash
# Fetch mimalloc 2.1.7 and validate its frozen digest against archived sources.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="2.1.7"
ARCHIVE_NAME="mimalloc-${VERSION}.tar.gz"
FROZEN_ARCHIVE_NAME="$ARCHIVE_NAME.frozen"
ARCHIVE="$ROOT_DIR/packaging/$FROZEN_ARCHIVE_NAME"
FROZEN="$SCRIPT_DIR/mimalloc-${VERSION}.sha256"
LOG_DIR="$ROOT_DIR/results/logs"
EVIDENCE_DIR="$LOG_DIR/mimalloc-hash-sources"
LOG_FILE="$LOG_DIR/fetch-mimalloc.log"
OFFICIAL_URL="https://github.com/microsoft/mimalloc/archive/refs/tags/v${VERSION}.tar.gz"
VCPKG_COMMIT="d8e2b83a6b6981e7e019b9b6ad8884be1765720a"
VCPKG_PORT_URL="https://raw.githubusercontent.com/microsoft/vcpkg/$VCPKG_COMMIT/ports/mimalloc/portfile.cmake"
VCPKG_MANIFEST_URL="https://raw.githubusercontent.com/microsoft/vcpkg/$VCPKG_COMMIT/ports/mimalloc/vcpkg.json"
CONAN_COMMIT="a8ab0ecbeaa1eeba447d8fccda1c43f110cdbdc3"
CONAN_DATA_URL="https://raw.githubusercontent.com/conan-io/conan-center-index/$CONAN_COMMIT/recipes/mimalloc/all/conandata.yml"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fetch-mimalloc.XXXXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$ROOT_DIR/packaging" "$EVIDENCE_DIR"
: > "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

fail() {
    log "MIMALLOC_FETCH_FAIL: $*"
    exit 1
}

download() {
    local url="$1"
    local destination="$2"
    curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 \
        --output "$destination" "$url"
}

for tool in awk cp curl date grep head mkdir sed sha256sum sha512sum tee; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
done
[[ -f "$FROZEN" ]] || fail "frozen digest file missing: $FROZEN"

frozen_sha256="$(awk 'NF { print tolower($1); exit }' "$FROZEN")"
[[ "$frozen_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid frozen sha256"

candidate="$TMP_DIR/$ARCHIVE_NAME"
vcpkg_port="$EVIDENCE_DIR/vcpkg-portfile.$VCPKG_COMMIT.cmake"
vcpkg_manifest="$EVIDENCE_DIR/vcpkg-manifest.$VCPKG_COMMIT.json"
conan_data="$EVIDENCE_DIR/conan-conandata.$CONAN_COMMIT.yml"

log "fetch_started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "version=$VERSION"
log "official_url=$OFFICIAL_URL"
download "$OFFICIAL_URL" "$candidate" || fail "official archive unavailable"

actual_sha256="$(sha256sum "$candidate" | awk '{print tolower($1)}')"
actual_sha512="$(sha512sum "$candidate" | awk '{print tolower($1)}')"
log "official_sha256=$actual_sha256"
log "official_sha512=$actual_sha512"
[[ "$actual_sha256" == "$frozen_sha256" ]] || \
    fail "frozen sha256 mismatch expected=$frozen_sha256 actual=$actual_sha256"
log "frozen_sha256_verdict=PASS"

if download "$VCPKG_PORT_URL" "$vcpkg_port" && \
   download "$VCPKG_MANIFEST_URL" "$vcpkg_manifest"; then
    vcpkg_version="$(grep -E '"version"[[:space:]]*:' "$vcpkg_manifest" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    vcpkg_sha512="$(awk '$1 == "SHA512" { gsub(/\r/, "", $2); print tolower($2); exit }' "$vcpkg_port")"
    log "source=vcpkg commit=$VCPKG_COMMIT version=${vcpkg_version:-UNKNOWN} sha512=${vcpkg_sha512:-MISSING}"
    [[ "$vcpkg_version" == "$VERSION" ]] || fail "vcpkg version mismatch"
    [[ "$vcpkg_sha512" =~ ^[0-9a-f]{128}$ ]] || fail "vcpkg sha512 missing"
    [[ "$vcpkg_sha512" == "$actual_sha512" ]] || fail "vcpkg sha512 mismatch"
    log "source_verdict.vcpkg=PASS"
else
    log "source_verdict.vcpkg=UNAVAILABLE"
fi

if download "$CONAN_DATA_URL" "$conan_data"; then
    conan_sha256="$(awk -v version="\"$VERSION\":" '
        $1 == version { active=1; next }
        active && $1 == "sha256:" { gsub(/\"/, "", $2); print tolower($2); exit }
        active && /^[^[:space:]]/ { exit }
    ' "$conan_data")"
    log "source=conan-center commit=$CONAN_COMMIT version=$VERSION sha256=${conan_sha256:-MISSING}"
    [[ "$conan_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "Conan Center sha256 missing"
    [[ "$conan_sha256" == "$actual_sha256" ]] || fail "Conan Center sha256 mismatch"
    log "source_verdict.conan_center=PASS"
else
    log "source_verdict.conan_center=UNAVAILABLE"
fi

available="$(grep -Ec '^source_verdict\.(vcpkg|conan_center)=PASS$' "$LOG_FILE" || true)"
(( available >= 1 )) || fail "no independent digest source available"

cp -p -- "$candidate" "$ARCHIVE"
archive_sha256="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
[[ "$archive_sha256" == "$frozen_sha256" ]] || fail "copied archive verification failed"
log "archive=$ARCHIVE"
log "archive_sha256=$archive_sha256"
log "independent_sources_confirmed=$available"
log "validation=PASS"
log "source_review=REQUIRED before formal GBS build"
log "fetch_finished=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
