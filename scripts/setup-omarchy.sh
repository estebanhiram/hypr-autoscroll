#!/usr/bin/env bash

set -euo pipefail

readonly REPOSITORY_URL="https://github.com/estebanhiram/hypr-autoscroll"
readonly PLUGIN_NAME="hypr-autoscroll"
readonly SHELL_PLUGIN_ID="io.github.estebanhiram.hypr-autoscroll"
readonly MINIMUM_OMARCHY_MAJOR=4
readonly CONFIG_ROOT="${HOME}/.config/hypr"
readonly MAIN_CONFIG="${CONFIG_ROOT}/hyprland.lua"
readonly MODULE_CONFIG="${CONFIG_ROOT}/autoscroll.lua"
readonly SENSITIVITY_CONFIG="${CONFIG_ROOT}/autoscroll-sensitivity"
readonly SENSITIVITY_MARKER="# Managed by hypr-autoscroll"
readonly REQUIRE_LINE='require("hypr.autoscroll")'

shortcut="SUPER + A"
uninstall=false
temporary_file=""

cleanup() {
    if [[ -n "$temporary_file" && -e "$temporary_file" ]]; then
        rm -f -- "$temporary_file"
    fi
}

trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage:
  setup-omarchy.sh [--shortcut "SUPER + A"]
  setup-omarchy.sh --uninstall

Installs and configures hypr-autoscroll for Omarchy Quattro (version 4 or
newer). Running the setup again updates the managed configuration without
duplicating it.
EOF
}

fail() {
    printf 'hypr-autoscroll setup: %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --shortcut)
            (($# >= 2)) || fail "--shortcut requires a key combination"
            shortcut="$2"
            shift 2
            ;;
        --uninstall)
            uninstall=true
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

for command in git hyprctl jq omarchy; do
    command -v "$command" >/dev/null 2>&1 || fail "required command not found: ${command}"
done

if ! command -v hyprpm >/dev/null 2>&1; then
    fail "required command not found: hyprpm; recent Hyprland packages no longer bundle it. Install it with 'omarchy pkg add hyprpm' (or 'sudo pacman -S hyprpm') and run the setup again"
fi

omarchy_version="$(omarchy version 2>/dev/null)" || fail "could not determine the Omarchy version"
if [[ "$omarchy_version" =~ ([0-9]+)\. ]]; then
    omarchy_major=$((10#${BASH_REMATCH[1]}))
else
    fail "could not parse Omarchy version: ${omarchy_version}"
fi

((omarchy_major >= MINIMUM_OMARCHY_MAJOR)) ||
    fail "Omarchy Quattro (version 4 or newer) is required; found ${omarchy_version}"

[[ -f "$MAIN_CONFIG" ]] || fail "Omarchy Quattro configuration not found at ${MAIN_CONFIG}"
grep -Fq 'require("default.hypr.omarchy")' "$MAIN_CONFIG" ||
    fail "${MAIN_CONFIG} does not load the Omarchy Quattro Hyprland defaults"

timestamp="$(date +%Y%m%d%H%M%S)-$$"

backup_file() {
    local source_file="$1"
    local backup_file="${source_file}.bak.hypr-autoscroll-${timestamp}"

    cp -- "$source_file" "$backup_file"
    printf 'Backed up %s to %s\n' "$source_file" "$backup_file"
}

remove_require_line() {
    grep -Fxq "$REQUIRE_LINE" "$MAIN_CONFIG" || return 0

    backup_file "$MAIN_CONFIG"
    temporary_file="$(mktemp)"
    awk -v line="$REQUIRE_LINE" '$0 != line' "$MAIN_CONFIG" >"$temporary_file"
    install -m 0644 "$temporary_file" "$MAIN_CONFIG"
    rm -f -- "$temporary_file"
    temporary_file=""
}

remove_sensitivity_config() {
    [[ -f "$SENSITIVITY_CONFIG" ]] || return 0
    grep -Fxq "$SENSITIVITY_MARKER" "$SENSITIVITY_CONFIG" ||
        fail "refusing to remove unmanaged file: ${SENSITIVITY_CONFIG}"

    backup_file "$SENSITIVITY_CONFIG"
    rm -- "$SENSITIVITY_CONFIG"
}

ensure_sensitivity_config() {
    if [[ -e "$SENSITIVITY_CONFIG" ]]; then
        grep -Fxq "$SENSITIVITY_MARKER" "$SENSITIVITY_CONFIG" ||
            fail "refusing to overwrite unmanaged file: ${SENSITIVITY_CONFIG}"
        return 0
    fi

    temporary_file="$(mktemp)"
    printf '%s\n4.00\n' "$SENSITIVITY_MARKER" >"$temporary_file"
    install -m 0644 "$temporary_file" "$SENSITIVITY_CONFIG"
    rm -f -- "$temporary_file"
    temporary_file=""
}

shell_plugin_is_installed() {
    local plugin_list="$1"
    jq -e --arg id "$SHELL_PLUGIN_ID" 'any(.[]; .id == $id and .firstParty == false)' \
        <<<"$plugin_list" >/dev/null
}

install_shell_widget() {
    local plugin_list
    plugin_list="$(omarchy plugin list --json 2>/dev/null || printf '[]')"

    if shell_plugin_is_installed "$plugin_list"; then
        omarchy plugin update "$SHELL_PLUGIN_ID" --yes
    else
        omarchy plugin add "$REPOSITORY_URL" --yes
    fi

    omarchy bar put "$SHELL_PLUGIN_ID" --before omarchy.power
}

remove_shell_widget() {
    local plugin_list
    plugin_list="$(omarchy plugin list --json 2>/dev/null || printf '[]')"
    if shell_plugin_is_installed "$plugin_list"; then
        omarchy plugin remove "$SHELL_PLUGIN_ID" --yes
    fi
}

validate_hyprland() {
    hyprctl reload >/dev/null

    local errors
    errors="$(hyprctl configerrors)"
    if [[ -n "${errors//[[:space:]]/}" ]]; then
        printf '%s\n' "$errors" >&2
        fail "Hyprland reported configuration errors"
    fi
}

repository_is_installed() {
    local list_output="$1"
    grep -Fq "Repository ${PLUGIN_NAME}" <<<"$list_output"
}

plugin_is_enabled() {
    local list_output="$1"
    awk -v name="$PLUGIN_NAME" '
        /Repository / {
            in_repository = index($0, "Repository " name " ") > 0
        }
        in_repository && /enabled:/ && /true/ {
            found = 1
        }
        END {
            exit !found
        }
    ' <<<"$list_output"
}

if [[ "$uninstall" == true ]]; then
    remove_shell_widget
    remove_require_line

    if [[ -f "$MODULE_CONFIG" ]]; then
        grep -Fq "Managed by hypr-autoscroll" "$MODULE_CONFIG" ||
            fail "refusing to remove unmanaged file: ${MODULE_CONFIG}"
        backup_file "$MODULE_CONFIG"
        rm -- "$MODULE_CONFIG"
    fi

    remove_sensitivity_config

    list_output="$(hyprpm list 2>/dev/null || true)"
    if repository_is_installed "$list_output"; then
        if plugin_is_enabled "$list_output"; then
            hyprpm disable "$PLUGIN_NAME"
        fi
        hyprpm remove "$PLUGIN_NAME"
        hyprpm reload
    fi

    validate_hyprland
    printf 'hypr-autoscroll was removed from Omarchy.\n'
    exit 0
fi

[[ "$shortcut" != *$'\n'* && "$shortcut" != *$'\r'* ]] ||
    fail "shortcut must be a single line"
[[ "$shortcut" != *'"'* && "$shortcut" != *$'\\'* ]] ||
    fail 'shortcut cannot contain quotes or backslashes'
[[ "$shortcut" =~ ^[[:alnum:]_:+\ -]+$ ]] ||
    fail "shortcut contains unsupported characters"

if [[ -e "$MODULE_CONFIG" ]] &&
    ! grep -Fq "Managed by hypr-autoscroll" "$MODULE_CONFIG"; then
    fail "refusing to overwrite unmanaged file: ${MODULE_CONFIG}"
fi

existing_shortcut=""
if [[ -f "$MODULE_CONFIG" ]]; then
    existing_shortcut="$(awk -F'"' '/^local autoscroll_shortcut = / { print $2; exit }' "$MODULE_CONFIG")"
fi

if [[ "$shortcut" != "$existing_shortcut" ]] &&
    omarchy menu keybindings --print |
        awk -F ' → ' -v shortcut="$shortcut" '
            {
                key = $1
                sub(/[[:space:]]+$/, "", key)
                if (key == shortcut)
                    found = 1
            }
            END { exit !found }
        '; then
    fail "${shortcut} is already bound; choose another combination with --shortcut"
fi

for candidate in "${CONFIG_ROOT}"/*.lua; do
    [[ -e "$candidate" && "$candidate" != "$MODULE_CONFIG" ]] || continue
    if grep -Eq 'hypr_autoscroll|middle_mode' "$candidate"; then
        fail "existing autoscroll configuration found in ${candidate}; remove it before using automated setup"
    fi
done

list_output="$(hyprpm list 2>/dev/null || true)"
if ! repository_is_installed "$list_output"; then
    if ! hyprpm add "$REPOSITORY_URL"; then
        fail "hyprpm could not install the plugin; run 'hyprpm update' and retry"
    fi
    hyprpm enable "$PLUGIN_NAME"
else
    if ! hyprpm update; then
        hyprpm reload >/dev/null 2>&1 || true
        fail "hyprpm could not update the installed plugin; fix its cache permissions and retry"
    fi

    list_output="$(hyprpm list 2>/dev/null || true)"
    if ! plugin_is_enabled "$list_output"; then
        hyprpm enable "$PLUGIN_NAME"
    fi
fi

if [[ -f "$MODULE_CONFIG" ]]; then
    backup_file "$MODULE_CONFIG"
fi

ensure_sensitivity_config

temporary_file="$(mktemp)"
cat >"$temporary_file" <<EOF
-- Managed by hypr-autoscroll's Omarchy setup script.
-- Run the setup again with --shortcut to change this value.
local autoscroll_shortcut = "${shortcut}"

local function stored_autoscroll_sensitivity()
  local file = io.open((os.getenv("HOME") or "") .. "/.config/hypr/autoscroll-sensitivity", "r")
  if not file then return 4.0 end

  local sensitivity = 4.0
  for line in file:lines() do
    local value = tonumber(line)
    if value and value >= 0.1 and value <= 100.0 then
      sensitivity = value
      break
    end
  end
  file:close()
  return sensitivity
end

local autoscroll_sensitivity = stored_autoscroll_sensitivity()

hl.config({
  plugin = {
    hypr_autoscroll = {
      direct_activation = false,
      sensitivity = autoscroll_sensitivity,
    },
  },
})

o.bind(autoscroll_shortcut, "Toggle middle-button autoscroll", "hyprctl hypr-autoscroll toggle")

hl.on("hyprland.start", function()
  hl.exec_cmd("hyprpm reload && hyprctl hypr-autoscroll off && hyprctl hypr-autoscroll sensitivity " .. autoscroll_sensitivity)
end)
EOF
install -m 0644 "$temporary_file" "$MODULE_CONFIG"
rm -f -- "$temporary_file"
temporary_file=""

if ! grep -Fxq "$REQUIRE_LINE" "$MAIN_CONFIG"; then
    backup_file "$MAIN_CONFIG"
    printf '\n%s\n' "$REQUIRE_LINE" >>"$MAIN_CONFIG"
fi

hyprpm reload
validate_hyprland
install_shell_widget

printf 'hypr-autoscroll is ready. Toggle shortcut: %s. Quattro bar widget added.\n' "$shortcut"
