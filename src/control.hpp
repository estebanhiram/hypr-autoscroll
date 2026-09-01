#pragma once

#include <cmath>
#include <sstream>
#include <string>

namespace Autoscroll {

    inline constexpr double MINIMUM_CONTROL_SENSITIVITY = 0.1;
    inline constexpr double MAXIMUM_CONTROL_SENSITIVITY = 100.0;

    enum class ControlAction {
        Status,
        Toggle,
        Enable,
        Disable,
        SetSensitivity,
        Invalid,
    };

    struct ControlRequest {
        ControlAction action      = ControlAction::Status;
        double        sensitivity = 0.0;
        std::string   error;
    };

    [[nodiscard]] inline ControlRequest parseControlRequest(const std::string& request) {
        std::istringstream stream(request);
        std::string        command;
        std::string        action;
        std::string        extra;

        stream >> command;
        if (command != "hypr-autoscroll")
            return {.action = ControlAction::Invalid, .error = "invalid command"};

        if (!(stream >> action) || action == "status") {
            if (stream >> extra)
                return {.action = ControlAction::Invalid, .error = "status does not accept arguments"};
            return {};
        }

        if (action == "toggle" || action == "on" || action == "off") {
            if (stream >> extra)
                return {.action = ControlAction::Invalid, .error = action + " does not accept arguments"};

            if (action == "toggle")
                return {.action = ControlAction::Toggle, .sensitivity = 0.0, .error = {}};
            if (action == "on")
                return {.action = ControlAction::Enable, .sensitivity = 0.0, .error = {}};
            return {.action = ControlAction::Disable, .sensitivity = 0.0, .error = {}};
        }

        if (action == "sensitivity") {
            std::string value;
            if (!(stream >> value) || (stream >> extra))
                return {.action = ControlAction::Invalid, .error = "sensitivity requires exactly one number"};

            try {
                size_t parsed = 0;
                double sensitivity = std::stod(value, &parsed);
                if (parsed != value.size() || !std::isfinite(sensitivity) ||
                    sensitivity < MINIMUM_CONTROL_SENSITIVITY ||
                    sensitivity > MAXIMUM_CONTROL_SENSITIVITY) {
                    return {.action = ControlAction::Invalid, .error = "sensitivity must be between 0.1 and 100"};
                }
                return {.action = ControlAction::SetSensitivity, .sensitivity = sensitivity, .error = {}};
            } catch (...) {
                return {.action = ControlAction::Invalid, .error = "sensitivity must be between 0.1 and 100"};
            }
        }

        return {.action = ControlAction::Invalid,
                .error  = "expected one of: status, toggle, on, off, sensitivity <value>"};
    }

} // namespace Autoscroll
