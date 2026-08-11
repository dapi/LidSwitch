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

final class ClosedLidForecastController {
    var didUpdate: ((BatterySnapshot, ActiveClosedLidEstimate?) -> Void)?

    private var engine = ClosedLidForecastEngine()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.sampleAndPublish()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
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
        let energyMode = readEnergyMode() ?? .automatic
        let learnedWatts = UserDefaults.standard.object(forKey: learnedWattsKey(for: energyMode)) == nil
            ? nil
            : UserDefaults.standard.double(forKey: learnedWattsKey(for: energyMode))
        let result = engine.forecast(
            measurement: measurement,
            energyMode: energyMode,
            learnedWatts: learnedWatts
        )
        if let learnedWattsToPersist = result.learnedWattsToPersist {
            UserDefaults.standard.set(learnedWattsToPersist, forKey: learnedWattsKey(for: energyMode))
        }
        didUpdate?(
            BatterySnapshot(
                isOnBattery: measurement.isOnBattery,
                chargePercent: measurement.chargePercent,
                forecastSource: result.source
            ),
            result.estimate
        )
    }

    private func readPowerMeasurement() -> ClosedLidPowerMeasurement? {
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

        return ClosedLidPowerMeasurement(
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

    private func readEnergyMode() -> EnergyMode? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return EnergyMode.parse(pmsetOutput: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ))
        } catch {
            return nil
        }
    }

    private func learnedWattsKey(for mode: EnergyMode) -> String {
        "lastPredictedClosedLidWatts.mode.\(mode.rawValue)"
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
