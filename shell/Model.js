function clampSensitivity(value) {
  var number = Number(value)
  if (!isFinite(number)) return 4
  return Math.max(0.5, Math.min(10, Math.round(number * 4) / 4))
}

function sensitivityName(value) {
  var sensitivity = clampSensitivity(value)
  if (sensitivity >= 9) return "Lightning"
  if (sensitivity >= 7) return "Very fast"
  if (sensitivity >= 5) return "Quick"
  if (sensitivity >= 3) return "Balanced"
  if (sensitivity >= 1.5) return "Gentle"
  return "Featherlight"
}

function parseStatus(raw) {
  try {
    var status = JSON.parse(String(raw || ""))
    if (!status || status.error || status.available !== true) return null
    return {
      available: true,
      enabled: status.enabled === true,
      middleModeEnabled: status.middleModeEnabled === true,
      active: status.active === true,
      sensitivity: clampSensitivity(status.sensitivity)
    }
  } catch (error) {
    return null
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    clampSensitivity: clampSensitivity,
    sensitivityName: sensitivityName,
    parseStatus: parseStatus
  }
}
