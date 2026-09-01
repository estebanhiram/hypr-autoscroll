#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT
TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
readonly TEST_HOME="${TEST_ROOT}/home"
readonly MOCK_BIN="${TEST_ROOT}/bin"
readonly MOCK_STATE="${TEST_ROOT}/state"
readonly MOCK_LOG="${TEST_ROOT}/commands.log"

cleanup() {
    rm -rf -- "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
    printf 'setup test failed: %s\n' "$*" >&2
    exit 1
}

mkdir -p "$TEST_HOME/.config/hypr" "$MOCK_BIN" "$MOCK_STATE"

cat >"$TEST_HOME/.config/hypr/hyprland.lua" <<'EOF'
require("default.hypr.omarchy")
require("hypr.bindings")
EOF

cat >"$MOCK_BIN/hyprpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'hyprpm %s\n' "$*" >>"${MOCK_LOG}"

case "${1:-}" in
    list)
        if [[ -e "${MOCK_STATE}/installed" ]]; then
            printf 'Repository hypr-autoscroll (by test)\n'
            if [[ -e "${MOCK_STATE}/enabled" ]]; then
                printf 'enabled: true\n'
            else
                printf 'enabled: false\n'
            fi
        fi
        ;;
    add)
        touch "${MOCK_STATE}/installed"
        ;;
    enable)
        touch "${MOCK_STATE}/enabled"
        ;;
    disable)
        rm -f "${MOCK_STATE}/enabled"
        ;;
    remove)
        rm -f "${MOCK_STATE}/installed"
        ;;
    reload) ;;
    *) exit 2 ;;
esac
EOF

cat >"$MOCK_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'hyprctl %s\n' "$*" >>"${MOCK_LOG}"

case "${1:-}" in
    reload) printf 'ok\n' ;;
    configerrors) ;;
    *) exit 2 ;;
esac
EOF

cat >"$MOCK_BIN/omarchy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'omarchy %s\n' "$*" >>"${MOCK_LOG}"

case "${1:-}" in
    version)
        printf '%s\n' "${MOCK_OMARCHY_VERSION}"
        ;;
    menu)
        [[ "${2:-}" == "keybindings" && "${3:-}" == "--print" ]] || exit 2
        ;;
    *) exit 2 ;;
esac
EOF

chmod +x "$MOCK_BIN/hyprpm" "$MOCK_BIN/hyprctl" "$MOCK_BIN/omarchy"

run_setup() {
    env HOME="$TEST_HOME" \
        PATH="${MOCK_BIN}:${PATH}" \
        MOCK_LOG="$MOCK_LOG" \
        MOCK_STATE="$MOCK_STATE" \
        MOCK_OMARCHY_VERSION="${MOCK_OMARCHY_VERSION:-4.0.2-1}" \
        bash "$PROJECT_ROOT/scripts/setup-omarchy.sh" "$@"
}

if MOCK_OMARCHY_VERSION="3.8.4-1" run_setup 2>/dev/null; then
    fail "pre-Quattro Omarchy version was accepted"
fi
[[ ! -e "$MOCK_STATE/installed" ]] || fail "version check happened after plugin installation"

run_setup --shortcut "SUPER + ALT + A"

module="$TEST_HOME/.config/hypr/autoscroll.lua"
main_config="$TEST_HOME/.config/hypr/hyprland.lua"

[[ -f "$module" ]] || fail "managed module was not created"
grep -Fq 'local autoscroll_shortcut = "SUPER + ALT + A"' "$module" ||
    fail "requested shortcut was not written"
grep -Fq 'hl.exec_cmd("hyprpm reload")' "$module" ||
    fail "startup reload hook was not written"
[[ "$(grep -Fxc 'require("hypr.autoscroll")' "$main_config")" -eq 1 ]] ||
    fail "module require was not added exactly once"
[[ -e "$MOCK_STATE/installed" && -e "$MOCK_STATE/enabled" ]] ||
    fail "plugin was not installed and enabled"
grep -Fq 'hyprpm add https://github.com/estebanhiram/hypr-autoscroll' "$MOCK_LOG" ||
    fail "canonical GitHub repository was not installed"

run_setup --shortcut "SUPER + ALT + S"

grep -Fq 'local autoscroll_shortcut = "SUPER + ALT + S"' "$module" ||
    fail "rerun did not update shortcut"
[[ "$(grep -Fxc 'require("hypr.autoscroll")' "$main_config")" -eq 1 ]] ||
    fail "rerun duplicated module require"
[[ "$(grep -Fc 'hyprpm add ' "$MOCK_LOG")" -eq 1 ]] ||
    fail "rerun attempted to add repository again"
[[ "$(grep -Fc 'hyprpm enable ' "$MOCK_LOG")" -eq 1 ]] ||
    fail "rerun attempted to enable plugin again"

run_setup --uninstall

[[ ! -e "$module" ]] || fail "managed module was not removed"
! grep -Fq 'require("hypr.autoscroll")' "$main_config" ||
    fail "module require was not removed"
[[ ! -e "$MOCK_STATE/installed" ]] || fail "hyprpm repository was not removed"

run_setup --uninstall

printf 'Omarchy setup tests passed\n'
