#!/usr/bin/env bash
# Fetch musl 1.2.5 and establish the frozen Source1 hash by independent consensus.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="1.2.5"
ARCHIVE_NAME="musl-${VERSION}.tar.gz"
ARCHIVE="$ROOT_DIR/packaging/$ARCHIVE_NAME"
FROZEN="$SCRIPT_DIR/musl-${VERSION}.sha256"
LOG_DIR="$ROOT_DIR/results/logs"
EVIDENCE_DIR="$LOG_DIR/hash-sources"
LOG_FILE="$LOG_DIR/fetch-musl.log"
OFFICIAL_URL="https://musl.libc.org/releases/$ARCHIVE_NAME"
REFERENCE_SHA256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fetch-musl.XXXXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$ROOT_DIR/packaging" "$EVIDENCE_DIR"
touch "$LOG_FILE"
printf '\n' >> "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "ERROR required tool missing: $1"
        exit 2
    fi
}

for tool in curl sha1sum sha256sum sha512sum awk grep sed python3; do
    require_tool "$tool"
done

log "fetch_started=$(timestamp)"
log "archive=$ARCHIVE"
log "trust_root=official download corroborated by at least two independent published digests"

if [[ -f "$ARCHIVE" && -f "$FROZEN" ]]; then
    frozen_value="$(awk 'NF { print tolower($1); exit }' "$FROZEN")"
    existing_value="$(sha256sum "$ARCHIVE" | awk '{print tolower($1)}')"
    if [[ "$frozen_value" =~ ^[0-9a-f]{64}$ && "$existing_value" == "$frozen_value" ]]; then
        log "short_circuit=PASS"
        log "frozen_sha256=$frozen_value"
        log "archive_sha256=$existing_value"
        log "fetch_finished=$(timestamp)"
        exit 0
    fi
    log "short_circuit=FAIL reason=frozen_archive_mismatch frozen_sha256=${frozen_value:-INVALID} archive_sha256=$existing_value"
    log "consensus=FAIL reason=local_tamper_or_corruption"
    rm -f -- "$ARCHIVE"
    exit 6
fi

download_optional() {
    local url="$1"
    local dest="$2"
    if curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 90 \
        --output "$dest" "$url"; then
        return 0
    fi
    rm -f -- "$dest"
    return 1
}

download_required() {
    local url="$1"
    local dest="$2"
    log "official_url=$url"
    if ! download_optional "$url" "$dest"; then
        log "ERROR official download failed"
        exit 3
    fi
}

candidate="$TMP_DIR/$ARCHIVE_NAME"
download_required "$OFFICIAL_URL" "$candidate"
ACTUAL_SHA1="$(sha1sum "$candidate" | awk '{print tolower($1)}')"
ACTUAL_SHA256="$(sha256sum "$candidate" | awk '{print tolower($1)}')"
ACTUAL_SHA512="$(sha512sum "$candidate" | awk '{print tolower($1)}')"
log "official_sha1=$ACTUAL_SHA1"
log "official_sha256=$ACTUAL_SHA256"
log "official_sha512=$ACTUAL_SHA512"

CONFIRMED=0
AVAILABLE=0
MISMATCHES=()

record_digest_source() {
    local source_name="$1"
    local algorithm="$2"
    local expected="$3"
    local actual="$4"
    local url="$5"
    expected="${expected,,}"
    actual="${actual,,}"
    AVAILABLE=$((AVAILABLE + 1))
    log "source=$source_name url=$url algorithm=$algorithm expected=$expected actual=$actual"
    if [[ "$expected" == "$actual" ]]; then
        CONFIRMED=$((CONFIRMED + 1))
        log "source_verdict.$source_name=PASS"
    else
        MISMATCHES+=("$source_name $algorithm expected=$expected actual=$actual")
        log "source_verdict.$source_name=MISMATCH"
    fi
}

# S1: Rich Felker's musl-cross-make hash list.
S1_URL="https://raw.githubusercontent.com/richfelker/musl-cross-make/master/hashes/$ARCHIVE_NAME.sha1"
S1_FILE="$EVIDENCE_DIR/S1-richfelker-musl-cross-make.sha1"
if download_optional "$S1_URL" "$S1_FILE"; then
    S1_EXPECTED="$(grep -Eio '[0-9a-f]{40}' "$S1_FILE" | head -n 1 || true)"
    if [[ "$S1_EXPECTED" =~ ^[0-9a-fA-F]{40}$ ]]; then
        record_digest_source "S1-richfelker" "sha1" "$S1_EXPECTED" "$ACTUAL_SHA1" "$S1_URL"
    else
        log "source=S1-richfelker url=$S1_URL verdict=UNAVAILABLE reason=no_sha1_in_response"
    fi
else
    log "source=S1-richfelker url=$S1_URL verdict=UNAVAILABLE reason=download_failed"
fi

find_alpine_source() {
    local master_url="https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/main/musl/APKBUILD"
    local master_file="$EVIDENCE_DIR/S2-alpine-APKBUILD.master"
    local expected=""
    if download_optional "$master_url" "$master_file"; then
        expected="$(grep -Eo "[0-9a-fA-F]{128}[[:space:]]+$ARCHIVE_NAME" "$master_file" | awk '{print $1; exit}' || true)"
        if [[ "$expected" =~ ^[0-9a-fA-F]{128}$ ]]; then
            ALPINE_EXPECTED="$expected"
            ALPINE_URL="$master_url"
            ALPINE_FILE="$master_file"
            return 0
        fi
    fi

    local page api_file ids commit raw_url history_file
    for page in 1 2 3 4 5 6 7 8 9 10; do
        api_file="$TMP_DIR/alpine-commits-$page.json"
        if ! download_optional "https://gitlab.alpinelinux.org/api/v4/projects/alpine%2Faports/repository/commits?path=main%2Fmusl%2FAPKBUILD&per_page=100&page=$page" "$api_file"; then
            return 1
        fi
        ids="$(python3 - "$api_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for item in data:
    value = item.get("id", "")
    if value:
        print(value)
PY
)"
        [[ -n "$ids" ]] || break
        while IFS= read -r commit; do
            raw_url="https://gitlab.alpinelinux.org/alpine/aports/-/raw/$commit/main/musl/APKBUILD"
            history_file="$TMP_DIR/alpine-APKBUILD-$commit"
            if ! download_optional "$raw_url" "$history_file"; then
                continue
            fi
            expected="$(grep -Eo "[0-9a-fA-F]{128}[[:space:]]+$ARCHIVE_NAME" "$history_file" | awk '{print $1; exit}' || true)"
            if [[ "$expected" =~ ^[0-9a-fA-F]{128}$ ]]; then
                ALPINE_EXPECTED="$expected"
                ALPINE_URL="$raw_url"
                ALPINE_FILE="$EVIDENCE_DIR/S2-alpine-APKBUILD.$commit"
                cp -- "$history_file" "$ALPINE_FILE"
                return 0
            fi
        done <<< "$ids"
    done
    return 1
}

ALPINE_EXPECTED=""
ALPINE_URL=""
ALPINE_FILE=""
if find_alpine_source; then
    record_digest_source "S2-alpine" "sha512" "$ALPINE_EXPECTED" "$ACTUAL_SHA512" "$ALPINE_URL"
    log "source_archive.S2=$ALPINE_FILE"
else
    log "source=S2-alpine verdict=UNAVAILABLE reason=version_not_found_or_history_fetch_failed"
fi

find_buildroot_source() {
    local master_url="https://raw.githubusercontent.com/buildroot/buildroot/master/package/musl/musl.hash"
    local master_file="$EVIDENCE_DIR/S3-buildroot-musl.hash.master"
    local expected=""
    if download_optional "$master_url" "$master_file"; then
        expected="$(awk -v name="$ARCHIVE_NAME" '$1 == "sha256" && $3 == name { print $2; exit }' "$master_file")"
        if [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
            BUILDROOT_EXPECTED="$expected"
            BUILDROOT_URL="$master_url"
            BUILDROOT_FILE="$master_file"
            return 0
        fi
    fi

    local page api_file ids commit raw_url history_file
    for page in 1 2 3 4 5 6 7 8 9 10; do
        api_file="$TMP_DIR/buildroot-commits-$page.json"
        if ! download_optional "https://api.github.com/repos/buildroot/buildroot/commits?path=package/musl/musl.hash&per_page=100&page=$page" "$api_file"; then
            return 1
        fi
        ids="$(python3 - "$api_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for item in data:
    value = item.get("sha", "")
    if value:
        print(value)
PY
)"
        [[ -n "$ids" ]] || break
        while IFS= read -r commit; do
            raw_url="https://raw.githubusercontent.com/buildroot/buildroot/$commit/package/musl/musl.hash"
            history_file="$TMP_DIR/buildroot-musl.hash-$commit"
            if ! download_optional "$raw_url" "$history_file"; then
                continue
            fi
            expected="$(awk -v name="$ARCHIVE_NAME" '$1 == "sha256" && $3 == name { print $2; exit }' "$history_file")"
            if [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
                BUILDROOT_EXPECTED="$expected"
                BUILDROOT_URL="$raw_url"
                BUILDROOT_FILE="$EVIDENCE_DIR/S3-buildroot-musl.hash.$commit"
                cp -- "$history_file" "$BUILDROOT_FILE"
                return 0
            fi
        done <<< "$ids"
    done
    return 1
}

BUILDROOT_EXPECTED=""
BUILDROOT_URL=""
BUILDROOT_FILE=""
if find_buildroot_source; then
    record_digest_source "S3-buildroot" "sha256" "$BUILDROOT_EXPECTED" "$ACTUAL_SHA256" "$BUILDROOT_URL"
    log "source_archive.S3=$BUILDROOT_FILE"
else
    log "source=S3-buildroot verdict=UNAVAILABLE reason=version_not_found_or_history_fetch_failed"
fi

# S4: official signature and signing key. This is corroborating evidence only.
S4_ASC_URL="$OFFICIAL_URL.asc"
S4_ASC_FILE="$EVIDENCE_DIR/S4-$ARCHIVE_NAME.asc"
S4_PAGE_URL="https://musl.libc.org/"
S4_PAGE_FILE="$EVIDENCE_DIR/S4-musl-homepage.html"
S4_KEY_URL="https://musl.libc.org/musl.pub"
S4_KEY_FILE="$EVIDENCE_DIR/S4-musl.pub"
download_optional "$S4_PAGE_URL" "$S4_PAGE_FILE" || true
if download_optional "$S4_ASC_URL" "$S4_ASC_FILE" && download_optional "$S4_KEY_URL" "$S4_KEY_FILE"; then
    if command -v gpg >/dev/null 2>&1; then
        GNUPGHOME="$TMP_DIR/gnupg"
        export GNUPGHOME
        mkdir -m 0700 "$GNUPGHOME"
        if gpg --batch --import "$S4_KEY_FILE" >>"$LOG_FILE" 2>&1; then
            S4_FINGERPRINT="$(gpg --batch --with-colons --show-keys "$S4_KEY_FILE" | awk -F: '$1 == "fpr" { print $10; exit }')"
            log "source=S4-gpg signature_url=$S4_ASC_URL key_url=$S4_KEY_URL fingerprint=${S4_FINGERPRINT:-UNKNOWN}"
            if gpg --batch --verify "$S4_ASC_FILE" "$candidate" >>"$LOG_FILE" 2>&1; then
                log "source_verdict.S4-gpg=PASS"
            else
                log "source_verdict.S4-gpg=FAILED_NONFATAL"
            fi
        else
            log "source_verdict.S4-gpg=UNAVAILABLE reason=key_import_failed"
        fi
    else
        log "source_verdict.S4-gpg=UNAVAILABLE reason=gpg_missing"
    fi
else
    log "source_verdict.S4-gpg=UNAVAILABLE reason=signature_or_key_download_failed"
fi

if [[ "$ACTUAL_SHA256" != "$REFERENCE_SHA256" ]]; then
    MISMATCHES+=("advisory-reference sha256 expected=$REFERENCE_SHA256 actual=$ACTUAL_SHA256")
    log "reference_verdict=MISMATCH expected=$REFERENCE_SHA256 actual=$ACTUAL_SHA256"
else
    log "reference_verdict=PASS expected=$REFERENCE_SHA256 actual=$ACTUAL_SHA256"
fi

log "independent_sources_available=$AVAILABLE"
log "independent_sources_confirmed=$CONFIRMED"
if (( ${#MISMATCHES[@]} > 0 )); then
    log "consensus=FAIL reason=digest_mismatch"
    for mismatch in "${MISMATCHES[@]}"; do
        log "mismatch=$mismatch"
    done
    rm -f -- "$ARCHIVE"
    exit 4
fi
if (( AVAILABLE < 2 || CONFIRMED < 2 )); then
    log "consensus=FAIL reason=insufficient_independent_sources required=2 available=$AVAILABLE confirmed=$CONFIRMED"
    rm -f -- "$ARCHIVE"
    exit 5
fi

mv -f -- "$candidate" "$ARCHIVE"
printf '%s  %s\n' "$ACTUAL_SHA256" "$ARCHIVE_NAME" > "$FROZEN"
log "consensus=PASS"
log "frozen_file=$FROZEN"
log "fetch_finished=$(timestamp)"
