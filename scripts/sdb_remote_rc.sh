#!/usr/bin/env bash
# Preserve a remote shell's explicit exit status even when sdb itself returns 0.

sdb_remote_capture() {
    local serial="$1"
    local command="$2"
    local marker transport_output transport_rc marker_count remote_rc marker_line payload

    marker="__CODEX_SDB_REMOTE_RC_${BASHPID:-$$}_${RANDOM}__="
    transport_rc=0
    transport_output="$(
        sdb -s "$serial" shell \
            "( $command ); remote_rc=\$?; printf '\n${marker}%s\n' \"\$remote_rc\"" \
            </dev/null 2>&1 | tr -d '\r'
    )" || transport_rc=$?
    if [[ "$transport_rc" -ne 0 ]]; then
        printf '%s\n' "$transport_output"
        printf 'SDB_TRANSPORT_FAIL rc=%s\n' "$transport_rc" >&2
        return "$transport_rc"
    fi

    marker_count="$(grep -Ec "^${marker}[0-9]+$" <<< "$transport_output" || true)"
    remote_rc="$(sed -n "s/^${marker}//p" <<< "$transport_output" | tail -n 1)"
    if [[ "$marker_count" -ne 1 || ! "$remote_rc" =~ ^[0-9]+$ || "$remote_rc" -gt 255 ]]; then
        printf '%s\n' "$transport_output"
        printf 'SDB_REMOTE_PROTOCOL_FAIL marker_count=%s remote_rc=%s\n' \
            "$marker_count" "${remote_rc:-MISSING}" >&2
        return 125
    fi

    marker_line="${marker}${remote_rc}"
    if [[ "$transport_output" == "$marker_line" ]]; then
        payload=""
    elif [[ "$transport_output" == *$'\n'"$marker_line" ]]; then
        payload="${transport_output%$'\n'"$marker_line"}"
    else
        printf '%s\n' "$transport_output"
        printf 'SDB_REMOTE_PROTOCOL_FAIL marker_not_terminal\n' >&2
        return 125
    fi
    printf '%s' "$payload"
    return "$remote_rc"
}
