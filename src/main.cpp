#include "button_state.hpp"
#include "scroll_math.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>

#include <linux/input-event-codes.h>

#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#if __has_include(<hyprland/src/pointer/PointerManager.hpp>)
#define HYPR_AUTOSCROLL_NAMESPACED_POINTER_API 1
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#else
#include <hyprland/src/managers/PointerManager.hpp>
#include <hyprland/src/managers/cursor/CursorShapeOverrideController.hpp>
#endif

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

namespace {

    constexpr auto PLUGIN_NAME = "hypr-autoscroll";

    HANDLE         pluginHandle = nullptr;

    struct ConfigValues {
        SP<Config::Values::CBoolValue>  enabled;
        SP<Config::Values::CBoolValue>  directActivation;
        SP<Config::Values::CIntValue>   button;
        SP<Config::Values::CFloatValue> deadZone;
        SP<Config::Values::CFloatValue> sensitivity;
        SP<Config::Values::CFloatValue> acceleration;
        SP<Config::Values::CFloatValue> maxSpeed;
        SP<Config::Values::CBoolValue>  horizontal;
        SP<Config::Values::CBoolValue>  vertical;
        SP<Config::Values::CIntValue>   frameIntervalMs;
    } config;

    struct RuntimeState {
        bool                    active                 = false;
        bool                    middleModeEnabled      = false;
        bool                    middleModeConfigLoaded = false;
        bool                    lastConfiguredMode     = false;
        std::optional<uint32_t> swallowedButton;
        bool                    sentHorizontal = false;
        bool                    sentVertical   = false;
        Vector2D                anchor;
        WP<CWLSurfaceResource>  target;
        Time::steady_tp         lastTick;
        SP<CEventLoopTimer>     timer;
        CHyprSignalListener     buttonListener;
        CHyprSignalListener     moveListener;
        CHyprSignalListener     axisListener;
        CHyprSignalListener     focusListener;
        CHyprSignalListener     configListener;
    } state;

    uint32_t eventTimeMs() {
        return static_cast<uint32_t>(Time::millis(Time::steadyNow()));
    }

    Vector2D pointerPosition() {
#ifdef HYPR_AUTOSCROLL_NAMESPACED_POINTER_API
        return Pointer::mgr()->position();
#else
        return g_pPointerManager->position();
#endif
    }

    void setAutoscrollCursor() {
#ifdef HYPR_AUTOSCROLL_NAMESPACED_POINTER_API
        Pointer::Cursor::overrideController->setOverride("all-scroll", Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
#else
        Cursor::overrideController->setOverride("all-scroll", Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
#endif
    }

    void unsetAutoscrollCursor() {
#ifdef HYPR_AUTOSCROLL_NAMESPACED_POINTER_API
        Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
#else
        Cursor::overrideController->unsetOverride(Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
#endif
    }

    void sendAxisStop(const wl_pointer_axis axis) {
        g_pSeatManager->sendPointerAxis(eventTimeMs(), axis, 0.0, 0, 0, WL_POINTER_AXIS_SOURCE_CONTINUOUS,
                                        WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
    }

    void stopAxisStreams() {
        bool sentStop = false;

        if (state.sentHorizontal) {
            sendAxisStop(WL_POINTER_AXIS_HORIZONTAL_SCROLL);
            state.sentHorizontal = false;
            sentStop             = true;
        }

        if (state.sentVertical) {
            sendAxisStop(WL_POINTER_AXIS_VERTICAL_SCROLL);
            state.sentVertical = false;
            sentStop           = true;
        }

        if (sentStop)
            g_pSeatManager->sendPointerFrame();
    }

    void deactivate(const bool restorePointerFocus) {
        if (!state.active)
            return;

        stopAxisStreams();
        state.active = false;
        state.target.reset();
        state.timer->updateTimeout(std::nullopt);
        unsetAutoscrollCursor();

        if (restorePointerFocus)
            g_pInputManager->simulateMouseMovement();
    }

    bool activate() {
        if (!config.enabled->value() || state.active || g_pInputManager->isLocked() ||
            g_pInputManager->isConstrained()) {
            return false;
        }

        const auto target = g_pSeatManager->m_state.pointerFocus.lock();
        if (!target)
            return false;

        state.active         = true;
        state.anchor         = pointerPosition();
        state.target         = target;
        state.lastTick       = Time::steadyNow();
        state.sentHorizontal = false;
        state.sentVertical   = false;

        setAutoscrollCursor();
        state.timer->updateTimeout(std::chrono::milliseconds(config.frameIntervalMs->value()));

        return true;
    }

    Autoscroll::ScrollCurve currentCurve() {
        return {
            .deadZone     = config.deadZone->value(),
            .sensitivity  = config.sensitivity->value(),
            .acceleration = config.acceleration->value(),
            .maxSpeed     = config.maxSpeed->value(),
        };
    }

    void sendScrollAxis(const wl_pointer_axis axis, const double delta, bool& streamActive) {
        if (delta == 0.0) {
            if (streamActive) {
                sendAxisStop(axis);
                streamActive = false;
            }
            return;
        }

        g_pSeatManager->sendPointerAxis(eventTimeMs(), axis, delta, 0, 0, WL_POINTER_AXIS_SOURCE_CONTINUOUS,
                                        WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
        streamActive = true;
    }

    void onTimer(SP<CEventLoopTimer> self, void*) {
        if (!state.active)
            return;

        const auto target = state.target.lock();
        if (!target || g_pSeatManager->m_state.pointerFocus.lock() != target) {
            deactivate(false);
            return;
        }

        const auto   now     = Time::steadyNow();
        const double elapsed = std::clamp(std::chrono::duration<double>(now - state.lastTick).count(), 0.0, 0.05);
        state.lastTick       = now;

        const Vector2D displacement = pointerPosition() - state.anchor;
        const auto     curve        = currentCurve();
        const double   horizontalDelta =
            config.horizontal->value() ? Autoscroll::deltaForFrame(displacement.x, elapsed, curve) : 0.0;
        const double verticalDelta =
            config.vertical->value() ? Autoscroll::deltaForFrame(displacement.y, elapsed, curve) : 0.0;

        const bool hadActiveStream = state.sentHorizontal || state.sentVertical;

        sendScrollAxis(WL_POINTER_AXIS_HORIZONTAL_SCROLL, horizontalDelta, state.sentHorizontal);
        sendScrollAxis(WL_POINTER_AXIS_VERTICAL_SCROLL, verticalDelta, state.sentVertical);

        if (horizontalDelta != 0.0 || verticalDelta != 0.0 || state.sentHorizontal || state.sentVertical ||
            hadActiveStream) {
            g_pSeatManager->sendPointerFrame();
        }

        self->updateTimeout(std::chrono::milliseconds(config.frameIntervalMs->value()));
    }

    SDispatchResult dispatchToggle(std::string argument) {
        if (argument.empty())
            argument = "toggle";

        if (argument == "off") {
            deactivate(true);
            return {};
        }

        if (argument == "on") {
            if (!activate()) {
                return {.success = false, .error = "autoscroll could not activate at the current pointer"};
            }
            return {};
        }

        if (argument == "toggle") {
            if (state.active)
                deactivate(true);
            else if (!activate()) {
                return {.success = false, .error = "autoscroll could not activate at the current pointer"};
            }
            return {};
        }

        return {.success = false, .error = "expected one of: toggle, on, off"};
    }

    void notifyMiddleMode() {
        HyprlandAPI::addNotificationV2(
            pluginHandle,
            {
                {"text",
                 state.middleModeEnabled ? "Middle-button autoscroll enabled" : "Middle-button autoscroll disabled"},
                {"time", uint64_t{2000}},
                {"color", CHyprColor{0}},
            });
    }

    void setMiddleMode(const bool enabled, const bool notify) {
        state.middleModeEnabled = enabled;

        if (!enabled)
            deactivate(true);

        if (notify)
            notifyMiddleMode();
    }

    SDispatchResult dispatchMiddleMode(std::string argument) {
        if (argument.empty())
            argument = "toggle";

        if (argument == "toggle") {
            setMiddleMode(!state.middleModeEnabled, true);
            return {};
        }

        if (argument == "on") {
            setMiddleMode(true, true);
            return {};
        }

        if (argument == "off") {
            setMiddleMode(false, true);
            return {};
        }

        if (argument == "status")
            return {};

        return {.success = false, .error = "expected one of: toggle, on, off, status"};
    }

    int luaToggle(lua_State* lua) {
        const char* argument = luaL_optstring(lua, 1, "toggle");
        const auto  result   = dispatchToggle(argument);

        if (!result.success)
            return luaL_error(lua, "%s", result.error.c_str());

        lua_pushboolean(lua, state.active);
        return 1;
    }

    int luaMiddleMode(lua_State* lua) {
        const char* argument = luaL_optstring(lua, 1, "toggle");
        const auto  result   = dispatchMiddleMode(argument);

        if (!result.success)
            return luaL_error(lua, "%s", result.error.c_str());

        lua_pushboolean(lua, state.middleModeEnabled);
        return 1;
    }

    void registerConfigValues() {
        config.enabled          = makeShared<Config::Values::CBoolValue>("plugin:hypr_autoscroll:enabled",
                                                                         "Enable the autoscroll plugin", true);
        config.directActivation = makeShared<Config::Values::CBoolValue>(
            "plugin:hypr_autoscroll:direct_activation", "Start with middle-button autoscroll mode enabled", true);
        config.button = makeShared<Config::Values::CIntValue>(
            "plugin:hypr_autoscroll:button", "Linux input button code used to activate autoscroll", BTN_MIDDLE,
            Config::Values::SIntValueOptions{.min = BTN_LEFT, .max = 0x2ff});
        config.deadZone = makeShared<Config::Values::CFloatValue>(
            "plugin:hypr_autoscroll:dead_zone", "Pointer distance that produces no scrolling",
            static_cast<float>(Autoscroll::DEFAULT_DEAD_ZONE),
            Config::Values::SFloatValueOptions{.min = 0.0F, .max = 200.0F});
        config.sensitivity = makeShared<Config::Values::CFloatValue>(
            "plugin:hypr_autoscroll:sensitivity", "Autoscroll velocity multiplier",
            static_cast<float>(Autoscroll::DEFAULT_SENSITIVITY),
            Config::Values::SFloatValueOptions{.min = 0.1F, .max = 100.0F});
        config.acceleration = makeShared<Config::Values::CFloatValue>(
            "plugin:hypr_autoscroll:acceleration", "Exponent applied to distance outside the dead zone",
            static_cast<float>(Autoscroll::DEFAULT_ACCELERATION),
            Config::Values::SFloatValueOptions{.min = 0.5F, .max = 3.0F});
        config.maxSpeed = makeShared<Config::Values::CFloatValue>(
            "plugin:hypr_autoscroll:max_speed", "Maximum scroll velocity in axis units per second",
            static_cast<float>(Autoscroll::DEFAULT_MAX_SPEED),
            Config::Values::SFloatValueOptions{.min = 1.0F, .max = 20000.0F});
        config.horizontal      = makeShared<Config::Values::CBoolValue>("plugin:hypr_autoscroll:horizontal",
                                                                        "Enable horizontal autoscrolling", true);
        config.vertical        = makeShared<Config::Values::CBoolValue>("plugin:hypr_autoscroll:vertical",
                                                                        "Enable vertical autoscrolling", true);
        config.frameIntervalMs = makeShared<Config::Values::CIntValue>(
            "plugin:hypr_autoscroll:frame_interval_ms", "Delay between synthetic scroll frames", 16,
            Config::Values::SIntValueOptions{.min = 4, .max = 100});

        HyprlandAPI::addConfigValueV2(pluginHandle, config.enabled);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.directActivation);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.button);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.deadZone);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.sensitivity);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.acceleration);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.maxSpeed);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.horizontal);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.vertical);
        HyprlandAPI::addConfigValueV2(pluginHandle, config.frameIntervalMs);
    }

    void registerListeners() {
        state.buttonListener = Event::bus()->m_events.input.mouse.button.listen(
            [](IPointer::SButtonEvent event, Event::SCallbackInfo& info) {
                const auto activationButton = static_cast<uint32_t>(config.button->value());

                const auto swallowedButtonDecision = Autoscroll::decideSwallowedButtonEvent(
                    state.swallowedButton && event.button == *state.swallowedButton, state.middleModeEnabled,
                    state.active, event.state == WL_POINTER_BUTTON_STATE_RELEASED);

                if (swallowedButtonDecision.clearButton)
                    state.swallowedButton.reset();

                if (swallowedButtonDecision.cancelEvent) {
                    info.cancelled = true;
                    return;
                }

                if (state.active) {
                    if (event.button == activationButton && event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
                        state.swallowedButton = event.button;
                        info.cancelled        = true;
                        deactivate(false);
                        return;
                    }

                    if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
                        deactivate(true);
                    }
                    return;
                }

                if (config.enabled->value() && state.middleModeEnabled && event.button == activationButton &&
                    event.state == WL_POINTER_BUTTON_STATE_PRESSED && activate()) {
                    state.swallowedButton = event.button;
                    info.cancelled        = true;
                }
            });

        state.moveListener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo& info) {
            if (!state.active)
                return;

            if (!state.target) {
                deactivate(false);
                return;
            }

            info.cancelled = true;
        });

        state.axisListener =
            Event::bus()->m_events.input.mouse.axis.listen([](IPointer::SAxisEvent, Event::SCallbackInfo&) {
                if (state.active)
                    deactivate(true);
            });

        state.focusListener = g_pSeatManager->m_events.pointerFocusChange.listen([] {
            if (state.active && g_pSeatManager->m_state.pointerFocus.lock() != state.target.lock()) {
                deactivate(false);
            }
        });

        state.configListener = Event::bus()->m_events.config.reloaded.listen([] {
            if (state.active && !config.enabled->value())
                deactivate(true);

            const bool configuredMode = config.directActivation->value();
            if (!state.middleModeConfigLoaded || configuredMode != state.lastConfiguredMode) {
                state.middleModeConfigLoaded = true;
                state.lastConfiguredMode     = configuredMode;
                setMiddleMode(configuredMode, false);
            }
        });
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    pluginHandle = handle;

    const std::string hyprlandHash = __hyprland_api_get_hash();
    const std::string pluginHash   = __hyprland_api_get_client_hash();

    if (hyprlandHash != pluginHash) {
        HyprlandAPI::addNotificationV2(pluginHandle,
                                       {
                                           {"text", "[hypr-autoscroll] Hyprland/header version mismatch"},
                                           {"time", uint64_t{5000}},
                                           {"color", CHyprColor{1.0, 0.2, 0.2, 1.0}},
                                       });
        throw std::runtime_error("hypr-autoscroll: Hyprland/header version mismatch");
    }

    registerConfigValues();

    if (!HyprlandAPI::addDispatcherV2(pluginHandle, "hypr-autoscroll:toggle", dispatchToggle)) {
        throw std::runtime_error("hypr-autoscroll: failed to register dispatcher");
    }

    if (!HyprlandAPI::addDispatcherV2(pluginHandle, "hypr-autoscroll:middle-mode", dispatchMiddleMode)) {
        throw std::runtime_error("hypr-autoscroll: failed to register middle-mode dispatcher");
    }

    if (Config::mgr()->type() == Config::CONFIG_LUA &&
        !HyprlandAPI::addLuaFunction(pluginHandle, "hypr_autoscroll", "toggle", luaToggle)) {
        throw std::runtime_error("hypr-autoscroll: failed to register Lua function");
    }

    if (Config::mgr()->type() == Config::CONFIG_LUA &&
        !HyprlandAPI::addLuaFunction(pluginHandle, "hypr_autoscroll", "middle_mode", luaMiddleMode)) {
        throw std::runtime_error("hypr-autoscroll: failed to register middle-mode Lua function");
    }

    state.timer = makeShared<CEventLoopTimer>(std::nullopt, onTimer, nullptr);
    g_pEventLoopManager->addTimer(state.timer);

    registerListeners();
    HyprlandAPI::reloadConfig();

    return {PLUGIN_NAME, "Windows-style middle-click autoscrolling", "hypr-autoscroll contributors", "0.2.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    deactivate(false);

    state.buttonListener.reset();
    state.moveListener.reset();
    state.axisListener.reset();
    state.focusListener.reset();
    state.configListener.reset();

    if (state.timer) {
        g_pEventLoopManager->removeTimer(state.timer);
        state.timer.reset();
    }
}
