import Foundation
import LidSwitchCore

check(EnergyMode.parse(pmsetOutput: " powermode            0\n") == .lowPower, "Should parse low power mode")
check(EnergyMode.parse(pmsetOutput: " powermode            1\n") == .automatic, "Should parse automatic mode")
check(EnergyMode.parse(pmsetOutput: " powermode            2\n") == .highPower, "Should parse high power mode")
check(EnergyMode.parse(pmsetOutput: " sleep 1\n") == nil, "Should reject output without a power mode")

let openLidEstimate = ActiveClosedLidEstimator.estimate(
    remainingEnergyWh: 60,
    measuredSystemWatts: 10,
    displayBrightness: 0.5,
    isClamshellClosed: false
)
check(openLidEstimate?.hours == 9, "Should model active runtime after removing display power")
check(openLidEstimate?.usesClosedLidMeasurement == false, "Should mark an open-lid simulation")

let measuredClosedLidEstimate = ActiveClosedLidEstimator.estimate(
    remainingEnergyWh: 60,
    measuredSystemWatts: 10,
    displayBrightness: 1,
    isClamshellClosed: true
)
check(measuredClosedLidEstimate?.hours == 6, "Should use measured closed-lid power directly")
check(
    ActiveClosedLidEstimator.modeledDisplayWatts(brightness: 0) == 0,
    "A dark display should contribute no modeled power"
)

print("All LidSwitchCore checks passed")

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}
