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
    private let helperAccessItem = NSMenuItem(
        title: "Set up passwordless switching…",
        action: #selector(manageHelperAccess),
        keyEquivalent: ""
    )
    private let helperManager = PrivilegedHelperManager()
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

        helperAccessItem.target = self
        menu.addItem(helperAccessItem)
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

        guard preference.command(toStartWhenLidOpens: !currentState) != nil else {
            return
        }

        do {
            if !helperManager.isInstalled {
                let alert = NSAlert()
                alert.messageText = "Set up passwordless switching?"
                alert.informativeText = "macOS will ask for your administrator password once to install LidSwitch’s narrowly scoped helper. Future switches won’t ask again."
                alert.addButton(withTitle: "Set Up")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try helperManager.install()
            }

            // The root-owned helper independently derives the exact command
            // from the requested state and the current NVRAM value.
            try helperManager.setStartsWhenLidOpens(!currentState)
            refresh()
        } catch let error as NSError where error.code == -128 {
            // The user cancelled the one-time administrator prompt.
        } catch {
            showError(title: "Couldn’t update the setting", message: error.localizedDescription)
        }
    }

    @objc private func manageHelperAccess() {
        if helperManager.isInstalled {
            let alert = NSAlert()
            alert.messageText = "Remove passwordless switching?"
            alert.informativeText = "macOS will ask for your administrator password to remove the helper and its permission."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            do {
                try helperManager.uninstall()
                updateUI()
            } catch let error as NSError where error.code == -128 {
                // The user cancelled the administrator prompt.
            } catch {
                showError(title: "Couldn’t remove helper", message: error.localizedDescription)
            }
        } else {
            do {
                try helperManager.install()
                updateUI()
            } catch let error as NSError where error.code == -128 {
                // The user cancelled the administrator prompt.
            } catch {
                showError(title: "Couldn’t set up passwordless switching", message: error.localizedDescription)
            }
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

        if helperManager.isInstalled {
            helperAccessItem.title = "Remove passwordless switching…"
        } else {
            helperAccessItem.title = "Set up passwordless switching…"
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
