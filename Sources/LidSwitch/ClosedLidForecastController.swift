import AppKit
import Foundation
import IOKit.ps
import LidSwitchCore

struct BatterySnapshot {
    let isOnBattery: Bool
    let chargePercent: Double
}

final class ClosedLidForecastController {
    var didUpdate: ((BatterySnapshot, ClosedLidEstimate?) -> Void)?

    private var learnedLog: String?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.publishCurrentEstimate()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadHistory()
        }
        reloadHistory()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func reloadHistory() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "log"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return }

                DispatchQueue.main.async {
                    self?.learnedLog = String(decoding: data, as: UTF8.self)
                    self?.publishCurrentEstimate()
                }
            } catch {
                DispatchQueue.main.async { self?.publishCurrentEstimate() }
            }
        }
    }

    private func publishCurrentEstimate() {
        guard let battery = readBatterySnapshot() else { return }
        let estimate = learnedLog.flatMap {
            ClosedLidEstimator.estimate(log: $0, currentChargePercent: battery.chargePercent)
        }
        didUpdate?(battery, estimate)
    }

    private func readBatterySnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?,
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double,
                  maximum > 0 else {
                continue
            }
            return BatterySnapshot(
                isOnBattery: sourceType == kIOPSBatteryPowerValue,
                chargePercent: current / maximum * 100
            )
        }
        return nil
    }
}
