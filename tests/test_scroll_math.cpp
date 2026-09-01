#include "../src/button_state.hpp"
#include "../src/control.hpp"
#include "../src/scroll_math.hpp"

#include <cassert>
#include <cmath>
#include <iostream>

namespace {

    bool near(const double actual, const double expected, const double epsilon = 1e-9) {
        return std::abs(actual - expected) <= epsilon;
    }

} // namespace

int main() {
    const auto statusRequest = Autoscroll::parseControlRequest("hypr-autoscroll");
    assert(statusRequest.action == Autoscroll::ControlAction::Status);

    const auto toggleRequest = Autoscroll::parseControlRequest("hypr-autoscroll toggle");
    assert(toggleRequest.action == Autoscroll::ControlAction::Toggle);

    const auto sensitivityRequest = Autoscroll::parseControlRequest("hypr-autoscroll sensitivity 5.25");
    assert(sensitivityRequest.action == Autoscroll::ControlAction::SetSensitivity);
    assert(near(sensitivityRequest.sensitivity, 5.25));

    const auto invalidSensitivity = Autoscroll::parseControlRequest("hypr-autoscroll sensitivity 101");
    assert(invalidSensitivity.action == Autoscroll::ControlAction::Invalid);

    const auto nanSensitivity = Autoscroll::parseControlRequest("hypr-autoscroll sensitivity nan");
    assert(nanSensitivity.action == Autoscroll::ControlAction::Invalid);

    const auto infiniteSensitivity = Autoscroll::parseControlRequest("hypr-autoscroll sensitivity inf");
    assert(infiniteSensitivity.action == Autoscroll::ControlAction::Invalid);

    const auto unrelatedButton = Autoscroll::decideSwallowedButtonEvent(false, false, false, false);
    assert(!unrelatedButton.cancelEvent);
    assert(!unrelatedButton.clearButton);

    const auto pendingRelease = Autoscroll::decideSwallowedButtonEvent(true, false, false, true);
    assert(pendingRelease.cancelEvent);
    assert(pendingRelease.clearButton);

    const auto stalePressWhileDisabled = Autoscroll::decideSwallowedButtonEvent(true, false, false, false);
    assert(!stalePressWhileDisabled.cancelEvent);
    assert(stalePressWhileDisabled.clearButton);

    const auto pendingPressWhileEnabled = Autoscroll::decideSwallowedButtonEvent(true, true, false, false);
    assert(pendingPressWhileEnabled.cancelEvent);
    assert(!pendingPressWhileEnabled.clearButton);

    const auto pendingPressWhileActive = Autoscroll::decideSwallowedButtonEvent(true, false, true, false);
    assert(pendingPressWhileActive.cancelEvent);
    assert(!pendingPressWhileActive.clearButton);

    const Autoscroll::ScrollCurve defaults;
    assert(near(defaults.sensitivity, 4.0));
    assert(near(defaults.acceleration, 1.075));
    assert(near(defaults.maxSpeed, 1500.0));

    const Autoscroll::ScrollCurve linear{
        .deadZone     = 10.0,
        .sensitivity  = 2.0,
        .acceleration = 1.0,
        .maxSpeed     = 100.0,
    };

    assert(near(Autoscroll::velocityForDisplacement(0.0, linear), 0.0));
    assert(near(Autoscroll::velocityForDisplacement(10.0, linear), 0.0));
    assert(near(Autoscroll::velocityForDisplacement(-9.0, linear), 0.0));
    assert(near(Autoscroll::velocityForDisplacement(20.0, linear), 20.0));
    assert(near(Autoscroll::velocityForDisplacement(-20.0, linear), -20.0));
    assert(near(Autoscroll::velocityForDisplacement(1000.0, linear), 100.0));
    assert(near(Autoscroll::deltaForFrame(20.0, 0.5, linear), 10.0));
    assert(near(Autoscroll::deltaForFrame(20.0, 0.0, linear), 0.0));

    const Autoscroll::ScrollCurve accelerated{
        .deadZone     = 0.0,
        .sensitivity  = 1.0,
        .acceleration = 2.0,
        .maxSpeed     = 1000.0,
    };

    assert(near(Autoscroll::velocityForDisplacement(5.0, accelerated), 25.0));
    assert(near(Autoscroll::velocityForDisplacement(-5.0, accelerated), -25.0));

    std::cout << "button state and scroll math tests passed\n";
    return 0;
}
