import Foundation
import LidSwitchCore

enum HelperError: Error, LocalizedError {
    case invalidArguments
    case unknownPreference
    case nvramFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Expected one of: check, enable-lid-startup, disable-lid-startup."
        case .unknownPreference:
            return "Refusing to overwrite an unknown BootPreference value."
        case .nvramFailed(let message):
            return message
        }
    }
}

do {
    guard CommandLine.arguments.count == 2 else { throw HelperError.invalidArguments }

    switch CommandLine.arguments[1] {
    case "check":
        break
    case "enable-lid-startup":
        try setStartsWhenLidOpens(true)
    case "disable-lid-startup":
        try setStartsWhenLidOpens(false)
    default:
        throw HelperError.invalidArguments
    }
} catch {
    fputs("LidSwitchHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private func setStartsWhenLidOpens(_ shouldStart: Bool) throws {
    let current = runNvram(arguments: ["BootPreference"])
    let preference = BootPreference.parse(nvramOutput: current.output, exitCode: current.exitCode)

    guard case .unknown = preference else {
        guard let command = preference.command(toStartWhenLidOpens: shouldStart) else { return }

        let arguments: [String]
        switch command {
        case .set(let value):
            arguments = ["BootPreference=\(value)"]
        case .delete:
            arguments = ["-d", "BootPreference"]
        }

        let result = runNvram(arguments: arguments)
        guard result.exitCode == 0 else {
            let message = String(decoding: result.error, as: UTF8.self)
            throw HelperError.nvramFailed(
                message.isEmpty ? "nvram exited with status \(result.exitCode)." : message
            )
        }
        return
    }

    throw HelperError.unknownPreference
}

private func runNvram(arguments: [String]) -> (output: Data, error: Data, exitCode: Int32) {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors

    do {
        try process.run()
        process.waitUntilExit()
        return (
            output.fileHandleForReading.readDataToEndOfFile(),
            errors.fileHandleForReading.readDataToEndOfFile(),
            process.terminationStatus
        )
    } catch {
        return (Data(), Data(error.localizedDescription.utf8), 1)
    }
}

