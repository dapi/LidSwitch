import AppKit
import Foundation
import LidSwitchAuthorizationShim
import LidSwitchCore
import Security

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
        var authorization: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw authorizationError(status)
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        status = kAuthorizationRightExecute.withCString { rightName in
            var right = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &right) { rightPointer in
                var rights = AuthorizationRights(count: 1, items: rightPointer)
                return AuthorizationCopyRights(
                    authorization,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            throw authorizationError(status)
        }

        let arguments = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 3)
        arguments.initialize(repeating: nil, count: 3)
        arguments[0] = strdup("-c")
        arguments[1] = strdup(shellCommand)
        defer {
            free(arguments[0])
            free(arguments[1])
            arguments.deinitialize(count: 3)
            arguments.deallocate()
        }

        var communicationsPipe: UnsafeMutablePointer<FILE>?
        status = "/bin/sh".withCString { executablePath in
            LidSwitchExecuteWithPrivileges(
                authorization,
                executablePath,
                UnsafePointer(arguments),
                &communicationsPipe
            )
        }
        guard status == errAuthorizationSuccess else {
            throw authorizationError(status)
        }

        // Reading to EOF also waits for the one-time installer to finish before
        // validating the newly installed helper and sudoers rule.
        if let communicationsPipe {
            _ = FileHandle(
                fileDescriptor: fileno(communicationsPipe),
                closeOnDealloc: false
            ).readDataToEndOfFile()
            fclose(communicationsPipe)
        }
    }

    private func authorizationError(_ status: OSStatus) -> NSError {
        let wasCancelled = status == errAuthorizationCanceled
        let message = SecCopyErrorMessageString(status, nil) as String?
        return NSError(
            domain: "LidSwitch.Authorization",
            code: wasCancelled ? -128 : Int(status),
            userInfo: [NSLocalizedDescriptionKey: message ?? "Authorization failed (\(status))."]
        )
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
