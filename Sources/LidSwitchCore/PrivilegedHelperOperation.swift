public enum PrivilegedHelperOperation: String, CaseIterable, Equatable, Sendable {
    case check = "check-v3"
    case enableClosedLidWork = "enable-closed-lid-work"
    case disableClosedLidWork = "disable-closed-lid-work"
    case setEnergyLow = "set-energy-low"
    case setEnergyAutomatic = "set-energy-automatic"
    case setEnergyHigh = "set-energy-high"

    public var pmsetArguments: [String]? {
        switch self {
        case .check:
            return nil
        case .enableClosedLidWork:
            return ["-a", "disablesleep", "1"]
        case .disableClosedLidWork:
            return ["-a", "disablesleep", "0"]
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
