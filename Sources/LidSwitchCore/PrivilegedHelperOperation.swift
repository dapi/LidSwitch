public enum PrivilegedHelperOperation: String, CaseIterable, Equatable, Sendable {
    case check = "check-v3"
    case setEnergyLow = "set-energy-low"
    case setEnergyAutomatic = "set-energy-automatic"
    case setEnergyHigh = "set-energy-high"

    public var pmsetArguments: [String]? {
        switch self {
        case .check:
            return nil
        case .setEnergyLow:
            return ["-a", "powermode", "0"]
        case .setEnergyAutomatic:
            return ["-a", "powermode", "1"]
        case .setEnergyHigh:
            return ["-a", "powermode", "2"]
        }
    }

    public static func energyMode(_ mode: EnergyMode) -> Self {
        switch mode {
        case .lowPower: return .setEnergyLow
        case .automatic: return .setEnergyAutomatic
        case .highPower: return .setEnergyHigh
        }
    }
}
