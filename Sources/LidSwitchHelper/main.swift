import Foundation
import LidSwitchCore

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
    guard CommandLine.arguments.count == 2,
          let operation = PrivilegedHelperOperation(rawValue: CommandLine.arguments[1]) else {
        throw HelperError.invalidArguments
    }
    if let arguments = operation.pmsetArguments {
        try runPmset(arguments: arguments)
    }
} catch {
    fputs("LidSwitchHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
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
