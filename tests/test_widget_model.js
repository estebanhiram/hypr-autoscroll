const assert = require("node:assert/strict")
const Model = require("../shell/Model.js")

assert.equal(Model.clampSensitivity(0), 0.5)
assert.equal(Model.clampSensitivity(4.13), 4.25)
assert.equal(Model.clampSensitivity(20), 10)
assert.equal(Model.sensitivityName(4), "Balanced")
assert.equal(Model.sensitivityName(9), "Lightning")

assert.deepEqual(Model.parseStatus(JSON.stringify({
  available: true,
  enabled: true,
  middleModeEnabled: true,
  active: false,
  sensitivity: 5.25
})), {
  available: true,
  enabled: true,
  middleModeEnabled: true,
  active: false,
  sensitivity: 5.25
})

assert.equal(Model.parseStatus("unknown request"), null)
assert.equal(Model.parseStatus('{"error":"not loaded"}'), null)

console.log("Quattro widget model tests passed")
