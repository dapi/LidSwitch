import Foundation

public struct ClosedLidPowerMeasurement: Equatable, Sendable {
    public let isOnBattery: Bool
    public let chargePercent: Double
    public let remainingEnergyWh: Double
    public let systemWatts: Double
    public let displayBrightness: Double
    public let isClamshellClosed: Bool

    public init(
        isOnBattery: Bool,
        chargePercent: Double,
        remainingEnergyWh: Double,
        systemWatts: Double,
        displayBrightness: Double,
        isClamshellClosed: Bool
    ) {
        self.isOnBattery = isOnBattery
        self.chargePercent = chargePercent
        self.remainingEnergyWh = remainingEnergyWh
        self.systemWatts = systemWatts
        self.displayBrightness = displayBrightness
        self.isClamshellClosed = isClamshellClosed
    }
}

public enum ClosedLidForecastSource: Equatable, Sendable {
    case measuredClosed
    case modeledDisplayOff
    case learnedOnAC
    case baselineOnAC(watts: Int)
}

public struct ClosedLidForecastResult: Equatable, Sendable {
    public let estimate: ActiveClosedLidEstimate?
    public let source: ClosedLidForecastSource
    public let learnedWattsToPersist: Double?
}

/// Stateful forecast policy, separated from IOKit, timers, and UserDefaults so
/// battery/AC transitions and rolling-sample behavior can be tested directly.
public struct ClosedLidForecastEngine: Sendable {
    private let maximumSampleCount: Int
    private var powerSamples: [Double] = []
    private var previousClamshellState: Bool?
    private var previousEnergyMode: EnergyMode?

    public init(maximumSampleCount: Int = 18) {
        precondition(maximumSampleCount > 0)
        self.maximumSampleCount = maximumSampleCount
    }

    public mutating func reset() {
        powerSamples.removeAll()
        previousClamshellState = nil
        previousEnergyMode = nil
    }

    public mutating func forecast(
        measurement: ClosedLidPowerMeasurement,
        energyMode: EnergyMode,
        learnedWatts: Double?
    ) -> ClosedLidForecastResult {
        guard measurement.isOnBattery else {
            powerSamples.removeAll()
            previousEnergyMode = energyMode
            let usableLearnedWatts = learnedWatts.flatMap { (2...150).contains($0) ? $0 : nil }
            let predictedWatts = usableLearnedWatts ?? Self.baselineWatts(for: energyMode)
            return ClosedLidForecastResult(
                estimate: ActiveClosedLidEstimator.estimate(
                    remainingEnergyWh: measurement.remainingEnergyWh,
                    measuredSystemWatts: predictedWatts,
                    displayBrightness: 0,
                    isClamshellClosed: true
                ),
                source: usableLearnedWatts == nil
                    ? .baselineOnAC(watts: Int(predictedWatts))
                    : .learnedOnAC,
                learnedWattsToPersist: nil
            )
        }

        // Samples from another lid state or energy mode represent a different
        // power profile and must not dilute the first forecast after a switch.
        if previousClamshellState != measurement.isClamshellClosed
            || previousEnergyMode != energyMode {
            powerSamples.removeAll()
        }
        previousClamshellState = measurement.isClamshellClosed
        previousEnergyMode = energyMode

        if (0.5...150).contains(measurement.systemWatts) {
            powerSamples.append(measurement.systemWatts)
            if powerSamples.count > maximumSampleCount {
                powerSamples.removeFirst(powerSamples.count - maximumSampleCount)
            }
        }

        let source: ClosedLidForecastSource = measurement.isClamshellClosed
            ? .measuredClosed
            : .modeledDisplayOff
        guard let medianWatts = median(powerSamples) else {
            return ClosedLidForecastResult(
                estimate: nil,
                source: source,
                learnedWattsToPersist: nil
            )
        }

        let estimate = ActiveClosedLidEstimator.estimate(
            remainingEnergyWh: measurement.remainingEnergyWh,
            measuredSystemWatts: medianWatts,
            displayBrightness: measurement.displayBrightness,
            isClamshellClosed: measurement.isClamshellClosed
        )
        return ClosedLidForecastResult(
            estimate: estimate,
            source: source,
            learnedWattsToPersist: estimate?.predictedWatts
        )
    }

    public static func baselineWatts(for mode: EnergyMode) -> Double {
        switch mode {
        case .lowPower: return 6
        case .automatic: return 8
        case .highPower: return 12
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
