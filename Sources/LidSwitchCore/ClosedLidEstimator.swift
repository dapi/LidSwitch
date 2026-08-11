import Foundation

public struct ClosedLidEstimate: Equatable, Sendable {
    public let hours: Int
    public let sampleCount: Int
    public let drainPercentPerHour: Double
}

public enum ClosedLidEstimator {
    /// Learns standby drain from completed clamshell-sleep sessions recorded by
    /// `pmset -g log`, then projects the current charge using that rate.
    public static func estimate(log: String, currentChargePercent: Double) -> ClosedLidEstimate? {
        let sessions = sessions(from: log).suffix(12)
        guard !sessions.isEmpty else { return nil }

        let totalHours = sessions.reduce(0) { $0 + $1.durationHours }
        let totalDrain = sessions.reduce(0) { $0 + $1.drainPercent }
        guard totalHours > 0, totalDrain > 0 else { return nil }

        let rate = totalDrain / totalHours
        guard rate >= 0.05, rate <= 5 else { return nil }

        let projectedHours = Int((max(0, currentChargePercent) / rate).rounded(.down))
        return ClosedLidEstimate(
            hours: min(999, projectedHours),
            sampleCount: sessions.count,
            drainPercentPerHour: rate
        )
    }

    private struct Session {
        let durationHours: Double
        let drainPercent: Double
    }

    private struct PendingSession {
        let date: Date
        let charge: Double
        var sawExternalPower: Bool
    }

    private static func sessions(from log: String) -> [Session] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var pending: PendingSession?
        var result: [Session] = []

        for line in log.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.contains("Clamshell Sleep"),
               line.contains("Using Batt"),
               let date = parseDate(line, formatter: formatter),
               let charge = parseCharge(line) {
                pending = PendingSession(date: date, charge: charge, sawExternalPower: false)
                continue
            }

            guard var current = pending else { continue }

            if line.contains("Using AC") {
                current.sawExternalPower = true
                pending = current
            }

            guard isFullWake(line),
                  let wakeDate = parseDate(line, formatter: formatter),
                  let wakeCharge = parseCharge(line) else {
                continue
            }

            defer { pending = nil }
            guard !current.sawExternalPower, line.contains("Using BATT") else { continue }

            let hours = wakeDate.timeIntervalSince(current.date) / 3600
            let drain = current.charge - wakeCharge

            // Integer percentages in pmset logs are too coarse for short
            // sleeps. Longer sessions with a measurable drop are useful.
            guard hours >= 2, drain >= 1 else { continue }
            let rate = drain / hours
            guard rate >= 0.05, rate <= 5 else { continue }
            result.append(Session(durationHours: hours, drainPercent: drain))
        }

        return result
    }

    private static func isFullWake(_ line: String) -> Bool {
        line.range(
            of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4} Wake\s+"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseDate(_ line: String, formatter: DateFormatter) -> Date? {
        guard line.count >= 25 else { return nil }
        return formatter.date(from: String(line.prefix(25)))
    }

    private static func parseCharge(_ line: String) -> Double? {
        guard let range = line.range(
            of: #"Charge:\s*([0-9]+)%?"#,
            options: .regularExpression
        ) else { return nil }

        let match = String(line[range])
        return Double(match.filter(\.isNumber))
    }
}

