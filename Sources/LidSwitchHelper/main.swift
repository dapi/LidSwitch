import Foundation

enum HelperError: Error, LocalizedError {
    case invalidArguments
    case pmsetFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Expected a supported LidSwitch helper operation."
        case .pmsetFailed(let message):
            return message
        }
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw HelperError.invalidArguments }

    switch CommandLine.arguments[1] {
    case "check-v3":
        break
    case "enable-closed-lid-work":
        try setSleepDisabled(true)
    case "disable-closed-lid-work":
        try setSleepDisabled(false)
    case "set-energy-low":
        try setEnergyMode(0)
    case "set-energy-automatic":
        try setEnergyMode(1)
    case "set-energy-high":
        try setEnergyMode(2)
    default:
        throw HelperError.invalidArguments
    }
} catch {
    fputs("LidSwitchHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private func setEnergyMode(_ mode: Int) throws {
    try runPmset(arguments: ["-a", "powermode", String(mode)])
}

private func setSleepDisabled(_ disabled: Bool) throws {
    try runPmset(arguments: ["-a", "disablesleep", disabled ? "1" : "0"])
}

private func runPmset(arguments: [String]) throws {
    let process = Process()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw HelperError.pmsetFailed(error.localizedDescription)
    }

    guard process.terminationStatus == 0 else {
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw HelperError.pmsetFailed(
            message.isEmpty ? "pmset exited with status \(process.terminationStatus)." : message
        )
    }
}
