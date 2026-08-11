import AppKit
import Foundation
import LidSwitchCore

struct PrivilegedHelperManager {
    static let installedHelperPath = "/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper"
    // sudo ignores files in an @includedir when their names contain a dot.
    static let sudoersPath = "/etc/sudoers.d/lidswitch"
    static let legacySudoersPath = "/etc/sudoers.d/me.dapi.LidSwitch"

    var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: Self.installedHelperPath) else {
            return false
        }
        return run(arguments: ["-n", Self.installedHelperPath, "check-v3"]).exitCode == 0
    }

    func install() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw managerError("LidSwitch cannot locate its app bundle.")
        }
        let bundledHelper = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Library/LaunchServices/LidSwitchHelper")
        guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw managerError("The bundled privileged helper is missing.")
        }

        let username = NSUserName()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-$"))
        guard !username.isEmpty,
              username.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw managerError("The current account name cannot be represented safely in sudoers.")
        }

        let temporarySudoersPath = Self.sudoersPath + ".tmp"
        let rule = "\(username) ALL=(root) NOPASSWD: \(Self.installedHelperPath)"
        let commands = [
            "/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuote(bundledHelper.path)) \(shellQuote(Self.installedHelperPath))",
            "/usr/bin/printf '%s\\n' \(shellQuote(rule)) > \(shellQuote(temporarySudoersPath))",
            "/usr/sbin/chown root:wheel \(shellQuote(temporarySudoersPath))",
            "/bin/chmod 440 \(shellQuote(temporarySudoersPath))",
            "/usr/sbin/visudo -cf \(shellQuote(temporarySudoersPath))",
            "/bin/mv -f \(shellQuote(temporarySudoersPath)) \(shellQuote(Self.sudoersPath))",
            "/bin/rm -f \(shellQuote(Self.legacySudoersPath))"
        ]

        try runWithAdministratorPrivileges(commands.joined(separator: " && "))
        guard isInstalled else {
            throw managerError("The helper was installed, but its passwordless permission did not validate.")
        }
    }

    func uninstall() throws {
        let command = [
            "/bin/rm -f",
            shellQuote(Self.sudoersPath),
            shellQuote(Self.legacySudoersPath),
            shellQuote(Self.installedHelperPath)
        ].joined(separator: " ")
        try runWithAdministratorPrivileges(command)
    }

    func setKeepsWorkingWithLidClosed(_ shouldKeepWorking: Bool) throws {
        let action = shouldKeepWorking ? "enable-closed-lid-work" : "disable-closed-lid-work"
        let result = run(arguments: ["-n", Self.installedHelperPath, action])
        guard result.exitCode == 0 else {
            let message = String(decoding: result.error, as: UTF8.self)
            throw managerError(message.isEmpty ? "The privileged helper failed." : message)
        }
    }

    func setEnergyMode(_ mode: EnergyMode) throws {
        let action: String
        switch mode {
        case .lowPower: action = "set-energy-low"
        case .automatic: action = "set-energy-automatic"
        case .highPower: action = "set-energy-high"
        }
        let result = run(arguments: ["-n", Self.installedHelperPath, action])
        guard result.exitCode == 0 else {
            let message = String(decoding: result.error, as: UTF8.self)
            throw managerError(message.isEmpty ? "The privileged helper failed." : message)
        }
    }

    private func run(arguments: [String]) -> (output: Data, error: Data, exitCode: Int32) {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
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

    private func runWithAdministratorPrivileges(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if result == nil || errorInfo != nil {
            throw NSError(
                domain: "LidSwitch.Authorization",
                code: errorInfo?[NSAppleScript.errorNumber] as? Int ?? 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        errorInfo?[NSAppleScript.errorMessage] as? String ?? "Unknown authorization error"
                ]
            )
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func managerError(_ message: String) -> NSError {
        NSError(
            domain: "LidSwitch.PrivilegedHelper",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
