#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
readonly MOCK_BIN="${TEST_ROOT}/bin"
readonly MOCK_LOG="${TEST_ROOT}/hyprctl.log"

cleanup() {
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MOCK_LOG}"
printf '{"available":true,"enabled":true,"middleModeEnabled":false,"active":false,"sensitivity":%s}\n' "${@: -1}"
EOF
chmod +x "$MOCK_BIN/hyprctl"

run_helper() {
    env HOME="${TEST_ROOT}/home" \
        PATH="${MOCK_BIN}:${PATH}" \
        MOCK_LOG="$MOCK_LOG" \
        bash "$PROJECT_ROOT/scripts/set-sensitivity.sh" "$@"
}

run_helper 5.25 >/dev/null

config_file="${TEST_ROOT}/home/.config/hypr/autoscroll-sensitivity"
grep -Fxq '# Managed by hypr-autoscroll' "$config_file"
grep -Fxq '5.25' "$config_file"
grep -Fxq -- '-j hypr-autoscroll sensitivity 5.25' "$MOCK_LOG"

if run_helper 0 >/dev/null 2>&1; then
    printf '%s\n' "sensitivity helper accepted a value below the supported range" >&2
    exit 1
fi

if run_helper fast >/dev/null 2>&1; then
    printf '%s\n' "sensitivity helper accepted a non-numeric value" >&2
    exit 1
fi

printf '%s\n' "sensitivity helper tests passed"
