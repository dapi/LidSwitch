import AppKit
import LidSwitchCore

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(
        title: "Start when lid opens",
        action: #selector(toggleLidStartup),
        keyEquivalent: ""
    )
    private let statusTextItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private var preference: BootPreference = .defaultBehavior

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "LidSwitch")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        toggleItem.target = self
        statusTextItem.isEnabled = false

        menu.delegate = self
        menu.addItem(toggleItem)
        menu.addItem(statusTextItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit LidSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refresh() {
        preference = readBootPreference()
        updateUI()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            toggleLidStartup()
        }
    }

    @objc private func toggleLidStartup() {
        // Re-read immediately before changing the value in case another tool
        // updated NVRAM since LidSwitch last refreshed.
        preference = readBootPreference()
        updateUI()

        guard let currentState = preference.startsWhenLidOpens else {
            showError(
                title: "Unknown BootPreference value",
                message: "LidSwitch will not overwrite a value it does not recognize."
            )
            return
        }

        guard let command = preference.command(toStartWhenLidOpens: !currentState) else {
            return
        }

        do {
            try runWithAdministratorPrivileges(command.shellCommand)
            refresh()
        } catch let error as NSError where error.code == -128 {
            // The user cancelled the administrator prompt.
        } catch {
            showError(title: "Couldn’t update the setting", message: error.localizedDescription)
        }
    }

    private func readBootPreference() -> BootPreference {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        process.arguments = ["BootPreference"]
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
            return BootPreference.parse(
                nvramOutput: output.fileHandleForReading.readDataToEndOfFile(),
                exitCode: process.terminationStatus
            )
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    private func updateUI() {
        switch preference.startsWhenLidOpens {
        case true:
            toggleItem.state = .on
            toggleItem.isEnabled = true
            statusTextItem.title = "Opening the lid starts this Mac"
            statusItem.button?.image = NSImage(
                systemSymbolName: "laptopcomputer",
                accessibilityDescription: "Startup when opening the lid is enabled"
            )
            statusItem.button?.toolTip = "LidSwitch: lid startup is on — click to turn off"
        case false:
            toggleItem.state = .off
            toggleItem.isEnabled = true
            statusTextItem.title = "Opening the lid won’t start this Mac"
            statusItem.button?.image = NSImage(
                systemSymbolName: "laptopcomputer.slash",
                accessibilityDescription: "Startup when opening the lid is disabled"
            )
            statusItem.button?.toolTip = "LidSwitch: lid startup is off — click to turn on"
        case nil:
            toggleItem.state = .mixed
            toggleItem.isEnabled = false
            statusTextItem.title = "Unknown system setting"
            statusItem.button?.image = NSImage(
                systemSymbolName: "laptopcomputer.trianglebadge.exclamationmark",
                accessibilityDescription: "Unknown lid startup setting"
            )
            statusItem.button?.toolTip = "LidSwitch: unknown setting — right-click for details"
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
                domain: "LidSwitch.AppleScript",
                code: errorInfo?[NSAppleScript.errorNumber] as? Int ?? 1,
                userInfo: [NSLocalizedDescriptionKey: errorInfo?[NSAppleScript.errorMessage] as? String ?? "Unknown error"]
            )
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.delegate = delegate
application.run()
