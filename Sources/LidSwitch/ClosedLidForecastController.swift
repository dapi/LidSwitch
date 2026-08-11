import AppKit
import Foundation
import IOKit
import IOKit.ps
import LidSwitchCore

struct BatterySnapshot {
    let isOnBattery: Bool
    let chargePercent: Double
    let forecastSource: ClosedLidForecastSource
}

enum ClosedLidForecastSource {
    case measuredClosed
    case modeledDisplayOff
    case learnedOnAC
    case baselineOnAC
}

final class ClosedLidForecastController {
    var didUpdate: ((BatterySnapshot, ActiveClosedLidEstimate?) -> Void)?

    private var powerSamples: [Double] = []
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var previousClamshellState: Bool?
    private let learnedWattsKey = "lastPredictedClosedLidWatts"

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.sampleAndPublish()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.powerSamples.removeAll()
            self?.sampleAndPublish()
        }
        sampleAndPublish()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func sampleAndPublish() {
        guard let measurement = readPowerMeasurement() else { return }

        guard measurement.isOnBattery else {
            powerSamples.removeAll()
            let learnedWatts = UserDefaults.standard.double(forKey: learnedWattsKey)
            let hasLearnedWatts = learnedWatts >= 2 && learnedWatts <= 150
            let predictedWatts = hasLearnedWatts ? learnedWatts : 8
            let estimate = ActiveClosedLidEstimator.estimate(
                remainingEnergyWh: measurement.remainingEnergyWh,
                measuredSystemWatts: predictedWatts,
                displayBrightness: 0,
                isClamshellClosed: true
            )
            didUpdate?(
                BatterySnapshot(
                    isOnBattery: false,
                    chargePercent: measurement.chargePercent,
                    forecastSource: hasLearnedWatts ? .learnedOnAC : .baselineOnAC
                ),
                estimate
            )
            return
        }

        if previousClamshellState != measurement.isClamshellClosed {
            powerSamples.removeAll()
            previousClamshellState = measurement.isClamshellClosed
        }

        if measurement.systemWatts >= 0.5, measurement.systemWatts <= 150 {
            powerSamples.append(measurement.systemWatts)
            if powerSamples.count > 18 {
                powerSamples.removeFirst(powerSamples.count - 18)
            }
        }

        guard let medianWatts = median(powerSamples) else {
            didUpdate?(
                BatterySnapshot(
                    isOnBattery: true,
                    chargePercent: measurement.chargePercent,
                    forecastSource: .modeledDisplayOff
                ),
                nil
            )
            return
        }

        let estimate = ActiveClosedLidEstimator.estimate(
            remainingEnergyWh: measurement.remainingEnergyWh,
            measuredSystemWatts: medianWatts,
            displayBrightness: measurement.displayBrightness,
            isClamshellClosed: measurement.isClamshellClosed
        )
        if let estimate {
            UserDefaults.standard.set(estimate.predictedWatts, forKey: learnedWattsKey)
        }
        didUpdate?(
            BatterySnapshot(
                isOnBattery: true,
                chargePercent: measurement.chargePercent,
                forecastSource: measurement.isClamshellClosed ? .measuredClosed : .modeledDisplayOff
            ),
            estimate
        )
    }

    private struct PowerMeasurement {
        let isOnBattery: Bool
        let chargePercent: Double
        let remainingEnergyWh: Double
        let systemWatts: Double
        let displayBrightness: Double
        let isClamshellClosed: Bool
    }

    private func readPowerMeasurement() -> PowerMeasurement? {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != 0 else { return nil }
        defer { IOObjectRelease(battery) }

        guard let properties = IORegistryEntryCreateCFPropertiesValue(battery) else { return nil }
        let isExternalConnected = bool(properties["ExternalConnected"]) ?? true
        let chargePercent = number(properties["CurrentCapacity"]) ?? 0
        let rawCapacityMAh = number(properties["AppleRawCurrentCapacity"]) ?? 0
        let voltageMV = number(properties["Voltage"]) ?? 0
        let amperageMA = signedNumber(properties["InstantAmperage"])

        // Raw capacity uses mAh. A nominal pack voltage is less volatile than
        // instantaneous voltage for estimating remaining energy.
        let remainingEnergyWh = rawCapacityMAh * 11.55 / 1000
        let systemWatts = abs(amperageMA) * voltageMV / 1_000_000

        return PowerMeasurement(
            isOnBattery: !isExternalConnected,
            chargePercent: chargePercent,
            remainingEnergyWh: remainingEnergyWh,
            systemWatts: systemWatts,
            displayBrightness: readDisplayBrightness(),
            isClamshellClosed: readClamshellState()
        )
    }

    private func readDisplayBrightness() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return 0.5 }
        defer { IOObjectRelease(service) }

        guard let parameters = IORegistryEntryCreateCFProperty(
            service,
            "IODisplayParameters" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any],
              let brightness = parameters["brightness"] as? [String: Any],
              let value = number(brightness["value"]),
              let maximum = number(brightness["max"]),
              maximum > 0 else {
            return 0.5
        }
        return value / maximum
    }

    private func readClamshellState() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return false }
        return bool(value) ?? false
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func signedNumber(_ value: Any?) -> Double {
        guard let number = value as? NSNumber else { return 0 }
        return Double(Int64(bitPattern: number.uint64Value))
    }

    private func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}

private func IORegistryEntryCreateCFPropertiesValue(_ entry: io_registry_entry_t) -> [String: Any]? {
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
        return nil
    }
    return properties?.takeRetainedValue() as? [String: Any]
}
