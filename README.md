# hypr-autoscroll

Windows-style middle-click autoscrolling for Hyprland.

Enable middle-button autoscroll mode, middle-click a scrollable surface, then
move the pointer away from the activation point. Direction controls the scroll
direction and distance controls the speed.

The plugin sends native Wayland continuous-axis events from inside Hyprland. It
does not require root access, `/dev/input`, `uinput`, or a background input
daemon.

> [!WARNING]
> Hyprland plugins run inside the compositor and are ABI-sensitive. Install
> with `hyprpm` so the plugin is built against your Hyprland version. Do not
> copy a prebuilt `.so` from another system.

Buy me a coffee. https://donate.stripe.com/aFa6oIgw87pIbtk7FVe3e03

## Features

- Smooth vertical and horizontal autoscrolling
- Configurable sensitivity, acceleration, dead zone, and maximum speed
- Fixed scroll target while the pointer moves
- Native `all-scroll` cursor while scrolling
- Shortcut-controlled middle-button mode
- Native Omarchy Quattro bar widget with an on/off switch and sensitivity slider
- Normal middle-button behavior when the mode is disabled
- Automatic exit on another click or physical wheel input
- Pointer-constrained applications such as games are ignored
- Lua and legacy Hyprland configuration support

## Requirements

- Hyprland with plugin support
- `hyprpm` for the recommended managed installation
- Omarchy Quattro (version 4 or newer) for the automatic Omarchy setup
- A C++23 compiler, Make, and Hyprland headers for manual installation

Omarchy 4.0.2 with Hyprland 0.56.2 is currently verified, along with standalone
Hyprland 0.55.2 and 0.56.0. Other Hyprland releases may require a matching
plugin revision because Hyprland does not guarantee plugin ABI compatibility.

## Install with hyprpm

### Automatic Omarchy Quattro setup

Omarchy Quattro users can install the plugin, configure startup loading,
register an Omarchy-native shortcut, and add the bar widget with one command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/estebanhiram/hypr-autoscroll/main/scripts/setup-omarchy.sh)
```

The default shortcut is `SUPER + A`. Choose another combination during setup:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/estebanhiram/hypr-autoscroll/main/scripts/setup-omarchy.sh) \
  --shortcut "SUPER + ALT + A"
```

The script verifies that Omarchy Quattro is installed, keeps Hyprland changes
under `~/.config/hypr/`, and installs the shell widget through Omarchy's plugin
commands. It creates backups before changing existing files, refuses
conflicting shortcuts or unmanaged configuration, and updates an existing
hyprpm installation when run again.
Review [`setup-omarchy.sh`](scripts/setup-omarchy.sh) before running it if
desired.

#### Quattro bar widget

The mouse icon is placed near the other system controls on the right side of
the bar:

- Left-click opens the popup. Use its switch to enable or disable
  middle-button autoscroll mode.
- Drag the sensitivity slider from `0.5×` to `10×`; the setting persists across
  logins.
- Right-click or middle-click toggles the mode immediately.
- Scroll over the bar icon to adjust sensitivity in `0.25×` steps.

The icon is dim while normal middle-click behavior is active and highlighted
while autoscroll mode is enabled. The popup and shortcut stay synchronized.

To remove the managed configuration and plugin:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/estebanhiram/hypr-autoscroll/main/scripts/setup-omarchy.sh) \
  --uninstall
```

This also removes the Quattro shell widget and its managed sensitivity file.

### Manual hyprpm setup

```bash
hyprpm add https://github.com/estebanhiram/hypr-autoscroll
hyprpm enable hypr-autoscroll
hyprpm reload
```

On Omarchy Quattro, install the shell widget separately after loading the
Hyprland plugin:

```bash
omarchy plugin add https://github.com/estebanhiram/hypr-autoscroll --yes
omarchy bar put io.github.estebanhiram.hypr-autoscroll --before omarchy.power
```

To load enabled plugins when Hyprland starts, add the following to your Lua
autostart configuration:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprpm reload")
end)
```

For legacy configuration:

```ini
exec-once = hyprpm reload
```

## Manual installation

Use this method if `hyprpm` cannot update its cached Hyprland headers. It builds
the plugin against the headers installed by your distribution.

On Arch Linux and Omarchy:

```bash
sudo pacman -S --needed base-devel git hyprland
git clone https://github.com/estebanhiram/hypr-autoscroll \
  "$HOME/.local/src/hypr-autoscroll"
make -C "$HOME/.local/src/hypr-autoscroll" clean all test
hyprctl plugin load \
  "$HOME/.local/src/hypr-autoscroll/build/hypr-autoscroll.so"
```

The path passed to Hyprland must be absolute. To load the plugin automatically
with a Lua configuration, place this before the plugin settings:

```lua
hl.plugin.load(
  os.getenv("HOME") .. "/.local/src/hypr-autoscroll/build/hypr-autoscroll.so"
)
```

For a legacy configuration, use your actual absolute path:

```ini
plugin = /home/your-user/.local/src/hypr-autoscroll/build/hypr-autoscroll.so
```

After a Hyprland update, rebuild the plugin before loading it again:

```bash
git -C "$HOME/.local/src/hypr-autoscroll" pull --ff-only
make -C "$HOME/.local/src/hypr-autoscroll" clean all test
```

## Recommended setup

Installing the plugin does not create a shortcut automatically. The shortcut
is a normal Hyprland binding, so you can use any free key combination.

The recommended setup keeps the middle button normal by default. Change
`autoscroll_shortcut` below to choose the toggle shortcut:

```lua
local autoscroll_shortcut = "SUPER + A"

hl.config({
  plugin = {
    hypr_autoscroll = {
      direct_activation = false,
    },
  },
})

hl.bind(autoscroll_shortcut, hl.dsp.exec_cmd("hyprctl hypr-autoscroll toggle"), {
  description = "Toggle middle-button autoscroll",
})
```

Usage:

1. Press `SUPER + A` to enable middle-button autoscroll mode.
2. Middle-click a scrollable window.
3. Move away from the activation point to scroll.
4. Click or use the physical wheel to end the current scroll session.
5. Press `SUPER + A` again to restore normal middle-button behavior.

Hyprland displays a notification when the middle-button mode changes.

### Omarchy

Put the `hl.config` block in `~/.config/hypr/hyprland.lua`. Put this
Omarchy-native binding in `~/.config/hypr/bindings.lua`:

```lua
local autoscroll_shortcut = "SUPER + A" -- Change this to any free combination.

o.bind(autoscroll_shortcut, "Toggle middle-button autoscroll", "hyprctl hypr-autoscroll toggle")
```

The description makes the shortcut appear in Omarchy's keybindings menu. Keep
customizations under `~/.config/hypr/`; files under `/usr/share/omarchy/` are
managed by Omarchy and must not be edited directly.

### Legacy Hyprland configuration

Choose the modifiers and key in the `bindd` line:

```ini
bindd = SUPER, A, Toggle middle-button autoscroll, hypr-autoscroll:middle-mode, toggle
```

## Uninstall

First remove the `hypr_autoscroll` configuration and shortcut binding that you
added during setup.

If installed with `hyprpm`:

```bash
hyprpm disable hypr-autoscroll
hyprpm remove hypr-autoscroll
hyprpm reload
```

If the Quattro widget was installed manually, remove it with:

```bash
omarchy plugin remove io.github.estebanhiram.hypr-autoscroll --yes
```

Keep your startup `hyprpm reload` command if you use other Hyprland plugins.

If loaded from a manual build, also remove its `hl.plugin.load(...)` or legacy
`plugin = ...` line. Unload the running plugin using the same absolute path
that was used to load it:

```bash
hyprctl plugin unload /absolute/path/to/build/hypr-autoscroll.so
```

Run `make clean` inside the cloned repository to remove the compiled plugin.
The source directory can then be deleted if it is no longer needed.

## Configuration

```lua
hl.config({
  plugin = {
    hypr_autoscroll = {
      enabled = true,
      direct_activation = false,
      button = 274,
      dead_zone = 12.0,
      sensitivity = 4.0,
      acceleration = 1.075,
      max_speed = 1500.0,
      horizontal = true,
      vertical = true,
      frame_interval_ms = 16,
    },
  },
})
```

| Option | Default | Description |
| --- | ---: | --- |
| `enabled` | `true` | Enables the plugin |
| `direct_activation` | `true` | Starts with middle-button autoscroll mode enabled |
| `button` | `274` | Linux input button code; `274` is `BTN_MIDDLE` |
| `dead_zone` | `12.0` | Pointer distance before scrolling starts |
| `sensitivity` | `4.0` | Scroll velocity multiplier |
| `acceleration` | `1.075` | Speed curve exponent; `1.0` is linear |
| `max_speed` | `1500.0` | Maximum scroll velocity |
| `horizontal` | `true` | Enables horizontal scrolling |
| `vertical` | `true` | Enables vertical scrolling |
| `frame_interval_ms` | `16` | Delay between generated scroll frames |

Legacy configuration uses the same option names:

```ini
plugin {
    hypr_autoscroll {
        enabled = true
        direct_activation = false
        sensitivity = 4
    }
}

bind = SUPER, A, hypr-autoscroll:middle-mode, toggle
```

## Commands

### Status and Quattro controls

The plugin registers a `hyprctl` command used by the Quattro widget. Query its
current state as JSON:

```bash
hyprctl -j hypr-autoscroll
```

Toggle middle-button mode or update the live sensitivity:

```bash
hyprctl hypr-autoscroll toggle
hyprctl hypr-autoscroll sensitivity 5.25
```

Sensitivity changes made through the Quattro widget are also saved to
`~/.config/hypr/autoscroll-sensitivity` and restored at login.

### Middle-button mode

The Lua function accepts `toggle`, `on`, `off`, and `status`, and returns the
resulting mode state:

```lua
hl.plugin.hypr_autoscroll.middle_mode("toggle")
```

Legacy dispatcher:

```ini
hypr-autoscroll:middle-mode, toggle
```

### Current scroll session

The separate session command starts or stops autoscrolling immediately at the
current pointer:

```lua
hl.plugin.hypr_autoscroll.toggle("toggle")
```

Legacy dispatcher:

```ini
hypr-autoscroll:toggle, toggle
```

Both commands accept `toggle`, `on`, and `off`.

## Build from source

On Arch Linux:

```bash
sudo pacman -S --needed base-devel hyprland
make
make test
```

The plugin is written to `build/hypr-autoscroll.so`.

Load a local build:

```bash
hyprctl plugin load "$(pwd)/build/hypr-autoscroll.so"
```

Unload it:

```bash
hyprctl plugin unload "$(pwd)/build/hypr-autoscroll.so"
```

CMake is also supported:

```bash
cmake -S . -B build-cmake -DBUILD_TESTING=ON
cmake --build build-cmake
ctest --test-dir build-cmake --output-on-failure
```

## Behavior and limitations

- Autoscroll is refused when the session is locked, no pointer-focused surface
  exists, or a client has constrained the pointer.
- Pointer motion is withheld from clients during a scroll session so scrolling
  remains attached to the original surface.
- A non-activation click restores normal pointer focus before the click is
  passed through.
- There is not yet a fixed visual marker at the activation point.
- Applications can interpret continuous-axis values differently, so tuning
  may vary slightly between toolkits.

## Troubleshooting

If `hyprpm add` reports that its headers are outdated, refresh its cache and
retry:

```bash
hyprpm update
hyprpm add https://github.com/estebanhiram/hypr-autoscroll
```

If `hyprpm update` fails or the error remains, use the manual installation
method above. `hyprpm purge-cache` is also available, but it removes the cache
and build state for every `hyprpm` plugin.

After updating Hyprland, rebuild a manual installation or update managed
plugins:

```bash
hyprpm update -f
hyprpm reload
```

List loaded plugins:

```bash
hyprctl plugin list
```

Check configuration errors:

```bash
hyprctl configerrors
```

If Hyprland rejects a manually built plugin, clean and rebuild it against the
currently installed headers:

```bash
make clean
make
```

## Contributing

Bug reports and pull requests are welcome. When reporting a problem, include:

- Hyprland version
- Application and toolkit, if known
- Relevant plugin configuration
- Steps that reproduce the behavior

Please run both build paths and the tests before submitting changes.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
