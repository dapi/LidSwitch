import Foundation
import LidSwitchCore

testEnergyModeParsing()
testEstimator()
testForecastEngine()
testHelperAllowlist()

print("All LidSwitchCore checks passed")

private func testEnergyModeParsing() {
    check(EnergyMode.parse(pmsetOutput: " powermode            0\n") == .lowPower, "Parse low power mode")
    check(EnergyMode.parse(pmsetOutput: "\tpowermode\t1\n") == .automatic, "Parse automatic mode")
    check(EnergyMode.parse(pmsetOutput: " sleep 1\n powermode 2\n") == .highPower, "Parse high power mode")
    check(EnergyMode.parse(pmsetOutput: "sleep 1\n") == nil, "Reject missing power mode")
    check(EnergyMode.parse(pmsetOutput: "powermode automatic\n") == nil, "Reject malformed power mode")
    check(EnergyMode.parse(pmsetOutput: "powermode 3\n") == nil, "Reject unsupported power mode")
}

private func testEstimator() {
    let openLid = require(ActiveClosedLidEstimator.estimate(
        remainingEnergyWh: 60,
        measuredSystemWatts: 10,
        displayBrightness: 0.5,
        isClamshellClosed: false
    ), "Open-lid estimate should exist")
    check(openLid.hours == 9, "Model active runtime after removing display power")
    check(approximatelyEqual(openLid.predictedWatts, 6.737, accuracy: 0.001), "Model display draw")
    check(!openLid.usesClosedLidMeasurement, "Mark an open-lid simulation")

    let closedLid = require(ActiveClosedLidEstimator.estimate(
        remainingEnergyWh: 60,
        measuredSystemWatts: 10,
        displayBrightness: 1,
        isClamshellClosed: true
    ), "Closed-lid estimate should exist")
    check(closedLid.hours == 6, "Use measured closed-lid power directly")
    check(closedLid.predictedWatts == 10, "Do not subtract display power while closed")
    check(closedLid.usesClosedLidMeasurement, "Mark a closed-lid measurement")

    check(ActiveClosedLidEstimator.modeledDisplayWatts(brightness: -1) == 0, "Clamp negative brightness")
    check(ActiveClosedLidEstimator.modeledDisplayWatts(brightness: 0.01) == 0, "Treat dark panel as off")
    check(
        ActiveClosedLidEstimator.modeledDisplayWatts(brightness: 2)
            == ActiveClosedLidEstimator.modeledDisplayWatts(brightness: 1),
        "Clamp brightness above maximum"
    )
    check(ActiveClosedLidEstimator.estimate(
        remainingEnergyWh: 0,
        measuredSystemWatts: 10,
        displayBrightness: 0.5,
        isClamshellClosed: false
    ) == nil, "Reject empty battery")
    check(ActiveClosedLidEstimator.estimate(
        remainingEnergyWh: 60,
        measuredSystemWatts: 0,
        displayBrightness: 0.5,
        isClamshellClosed: false
    ) == nil, "Reject zero power")
    check(ActiveClosedLidEstimator.estimate(
        remainingEnergyWh: 10_000,
        measuredSystemWatts: 2,
        displayBrightness: 0,
        isClamshellClosed: true
    )?.hours == 999, "Bound the displayed runtime")
}

private func testForecastEngine() {
    var medianEngine = ClosedLidForecastEngine(maximumSampleCount: 3)
    _ = medianEngine.forecast(measurement: battery(watts: 4, closed: false), energyMode: .automatic, learnedWatts: nil)
    _ = medianEngine.forecast(measurement: battery(watts: 100, closed: false), energyMode: .automatic, learnedWatts: nil)
    let median = medianEngine.forecast(
        measurement: battery(watts: 6, closed: false),
        energyMode: .automatic,
        learnedWatts: nil
    )
    check(median.source == .modeledDisplayOff, "Identify modeled open-lid forecast")
    check(median.estimate?.predictedWatts == 6, "Use rolling median on battery")
    check(median.learnedWattsToPersist == 6, "Persist predicted battery power")

    let closed = medianEngine.forecast(
        measurement: battery(watts: 20, closed: true),
        energyMode: .automatic,
        learnedWatts: nil
    )
    check(closed.source == .measuredClosed, "Identify directly measured closed-lid forecast")
    check(closed.estimate?.predictedWatts == 20, "Drop samples after clamshell transition")

    var energyModeEngine = ClosedLidForecastEngine(maximumSampleCount: 3)
    for _ in 0..<3 {
        _ = energyModeEngine.forecast(
            measurement: battery(watts: 6, closed: true),
            energyMode: .lowPower,
            learnedWatts: nil
        )
    }
    let highPower = energyModeEngine.forecast(
        measurement: battery(watts: 30, closed: true),
        energyMode: .highPower,
        learnedWatts: nil
    )
    check(highPower.estimate?.predictedWatts == 30, "Drop samples after energy-mode transition")

    for (mode, watts) in [(EnergyMode.lowPower, 6.0), (.automatic, 8.0), (.highPower, 12.0)] {
        var engine = ClosedLidForecastEngine()
        let result = engine.forecast(measurement: acPower(), energyMode: mode, learnedWatts: nil)
        check(result.source == .baselineOnAC(watts: Int(watts)), "Use mode-specific AC baseline")
        check(result.estimate?.predictedWatts == watts, "Apply mode-specific AC baseline watts")
        check(result.learnedWattsToPersist == nil, "Do not learn from AC baseline")
    }

    var acEngine = ClosedLidForecastEngine()
    let learned = acEngine.forecast(measurement: acPower(), energyMode: .automatic, learnedWatts: 7.5)
    check(learned.source == .learnedOnAC, "Prefer learned value on AC")
    check(learned.estimate?.predictedWatts == 7.5, "Apply learned value on AC")
    let invalidLearned = acEngine.forecast(measurement: acPower(), energyMode: .automatic, learnedWatts: 151)
    check(invalidLearned.source == .baselineOnAC(watts: 8), "Reject invalid learned value")

    var invalidSampleEngine = ClosedLidForecastEngine()
    let invalidSample = invalidSampleEngine.forecast(
        measurement: battery(watts: 0.4, closed: true),
        energyMode: .automatic,
        learnedWatts: nil
    )
    check(invalidSample.estimate == nil, "Do not forecast from invalid battery sample")

    var resetEngine = ClosedLidForecastEngine(maximumSampleCount: 3)
    _ = resetEngine.forecast(measurement: battery(watts: 6, closed: true), energyMode: .automatic, learnedWatts: nil)
    resetEngine.reset()
    let afterReset = resetEngine.forecast(
        measurement: battery(watts: 24, closed: true),
        energyMode: .automatic,
        learnedWatts: nil
    )
    check(afterReset.estimate?.predictedWatts == 24, "Drop samples after wake reset")
}

private func testHelperAllowlist() {
    let expected = Set([
        "check-v3",
        "set-energy-low",
        "set-energy-automatic",
        "set-energy-high"
    ])
    check(Set(PrivilegedHelperOperation.allCases.map(\.rawValue)) == expected, "Keep helper allowlist exact")
    check(PrivilegedHelperOperation(rawValue: "pmset") == nil, "Reject arbitrary helper commands")
    check(PrivilegedHelperOperation(rawValue: "set-energy-high extra") == nil, "Reject appended helper arguments")
    check(PrivilegedHelperOperation.check.pmsetArguments == nil, "Version check must not invoke pmset")
    check(PrivilegedHelperOperation.setEnergyLow.pmsetArguments == ["-a", "powermode", "0"], "Map low-power operation")
    check(PrivilegedHelperOperation.setEnergyAutomatic.pmsetArguments == ["-a", "powermode", "1"], "Map automatic operation")
    check(PrivilegedHelperOperation.setEnergyHigh.pmsetArguments == ["-a", "powermode", "2"], "Map high-power operation")
    check(PrivilegedHelperOperation.energyMode(.lowPower) == .setEnergyLow, "Map low energy mode")
    check(PrivilegedHelperOperation.energyMode(.automatic) == .setEnergyAutomatic, "Map automatic energy mode")
    check(PrivilegedHelperOperation.energyMode(.highPower) == .setEnergyHigh, "Map high energy mode")
}

private func battery(watts: Double, closed: Bool) -> ClosedLidPowerMeasurement {
    ClosedLidPowerMeasurement(
        isOnBattery: true,
        chargePercent: 75,
        remainingEnergyWh: 60,
        systemWatts: watts,
        displayBrightness: 0,
        isClamshellClosed: closed
    )
}

private func acPower() -> ClosedLidPowerMeasurement {
    ClosedLidPowerMeasurement(
        isOnBattery: false,
        chargePercent: 75,
        remainingEnergyWh: 60,
        systemWatts: 0,
        displayBrightness: 0.5,
        isClamshellClosed: false
    )
}

private func approximatelyEqual(_ lhs: Double, _ rhs: Double, accuracy: Double) -> Bool {
    abs(lhs - rhs) <= accuracy
}

private func require<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        fail(message)
    }
    return value
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fail(message) }
}

private func fail(_ message: String) -> Never {
    fputs("Check failed: \(message)\n", stderr)
    exit(1)
}
