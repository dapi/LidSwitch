import Foundation

enum LidSwitchDiagnostics {
    static let enabledKey = "lidSwitchDebugLogging"
    static let logURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent("LidSwitch.log")
    }()

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func log(_ message: String) {
        guard enabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL)
            }
        } catch {
            NSLog("LidSwitch diagnostics log failed: %@", error.localizedDescription)
        }
    }
}
