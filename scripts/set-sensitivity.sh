#!/usr/bin/env bash

set -euo pipefail

readonly CONFIG_ROOT="${HOME}/.config/hypr"
readonly CONFIG_FILE="${CONFIG_ROOT}/autoscroll-sensitivity"
readonly MANAGED_MARKER="# Managed by hypr-autoscroll"

fail() {
    printf 'hypr-autoscroll sensitivity: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "expected one sensitivity value"

normalized="$(awk -v raw="$1" '
    BEGIN {
        if (raw !~ /^[0-9]+([.][0-9]+)?$/)
            exit 1
        value = raw + 0
        if (value < 0.1 || value > 100)
            exit 1
        printf "%.2f", value
    }
')" || fail "sensitivity must be between 0.1 and 100"

mkdir -p "$CONFIG_ROOT"

if [[ -e "$CONFIG_FILE" ]] && ! grep -Fxq "$MANAGED_MARKER" "$CONFIG_FILE"; then
    fail "refusing to overwrite unmanaged file: ${CONFIG_FILE}"
fi

temporary_file="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
cleanup() {
    [[ ! -e "$temporary_file" ]] || rm -f -- "$temporary_file"
}
trap cleanup EXIT

printf '%s\n%s\n' "$MANAGED_MARKER" "$normalized" >"$temporary_file"
install -m 0644 "$temporary_file" "$CONFIG_FILE"
rm -f -- "$temporary_file"

hyprctl -j hypr-autoscroll sensitivity "$normalized"
