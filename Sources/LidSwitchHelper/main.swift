import Foundation

enum HelperError: Error, LocalizedError {
    case invalidArguments
    case pmsetFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Expected one of: check-v2, enable-closed-lid-work, disable-closed-lid-work."
        case .pmsetFailed(let message):
            return message
        }
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw HelperError.invalidArguments }

    switch CommandLine.arguments[1] {
    case "check-v2":
        break
    case "enable-closed-lid-work":
        try setSleepDisabled(true)
    case "disable-closed-lid-work":
        try setSleepDisabled(false)
    default:
        throw HelperError.invalidArguments
    }
} catch {
    fputs("LidSwitchHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private func setSleepDisabled(_ disabled: Bool) throws {
    let process = Process()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
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
