import Foundation

public struct ActiveClosedLidEstimate: Equatable, Sendable {
    public let hours: Int
    public let predictedWatts: Double
    public let usesClosedLidMeasurement: Bool
}

public enum ActiveClosedLidEstimator {
    /// Projects active runtime with the built-in display off. When the lid is
    /// already closed, measured power is used directly. Otherwise the modeled
    /// display draw is removed from current whole-system power.
    public static func estimate(
        remainingEnergyWh: Double,
        measuredSystemWatts: Double,
        displayBrightness: Double,
        isClamshellClosed: Bool
    ) -> ActiveClosedLidEstimate? {
        guard remainingEnergyWh > 0, measuredSystemWatts > 0 else { return nil }

        let predictedWatts: Double
        if isClamshellClosed {
            predictedWatts = measuredSystemWatts
        } else {
            predictedWatts = max(
                2,
                measuredSystemWatts - modeledDisplayWatts(brightness: displayBrightness)
            )
        }

        let hours = remainingEnergyWh / predictedWatts
        guard hours.isFinite, hours > 0 else { return nil }

        return ActiveClosedLidEstimate(
            hours: min(999, max(1, Int(hours.rounded()))),
            predictedWatts: predictedWatts,
            usesClosedLidMeasurement: isClamshellClosed
        )
    }

    /// Approximation for a modern MacBook's internal panel, including panel
    /// electronics and brightness-dependent backlight draw.
    public static func modeledDisplayWatts(brightness: Double) -> Double {
        let normalized = min(1, max(0, brightness))
        guard normalized > 0.01 else { return 0 }
        return 0.8 + 6.5 * pow(normalized, 1.4)
    }
}

