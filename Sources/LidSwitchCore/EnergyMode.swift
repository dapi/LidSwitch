import Foundation

public enum EnergyMode: Int, CaseIterable, Equatable, Sendable {
    case lowPower = 0
    case automatic = 1
    case highPower = 2

    public static func parse(pmsetOutput: String) -> EnergyMode? {
        for line in pmsetOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, fields[0] == "powermode", let value = Int(fields[1]) else {
                continue
            }
            return EnergyMode(rawValue: value)
        }
        return nil
    }
}
