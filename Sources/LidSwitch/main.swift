import AppKit
import IOKit
import LidSwitchCore

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(
        title: "Allow work with lid closed",
        action: #selector(toggleClosedLidWork),
        keyEquivalent: ""
    )
    private let statusTextItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let forecastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let energyModeHeader = NSMenuItem(title: "Режим энергии", action: nil, keyEquivalent: "")
    private let lowPowerItem = NSMenuItem(title: "Энергосбережение", action: #selector(selectLowPowerMode), keyEquivalent: "")
    private let automaticPowerItem = NSMenuItem(title: "Автоматически", action: #selector(selectAutomaticPowerMode), keyEquivalent: "")
    private let highPowerItem = NSMenuItem(title: "Высокая производительность", action: #selector(selectHighPowerMode), keyEquivalent: "")
    private let helperAccessItem = NSMenuItem(
        title: "Set up passwordless switching…",
        action: #selector(manageHelperAccess),
        keyEquivalent: ""
    )
    private let helperManager = PrivilegedHelperManager()
    private let forecastController = ClosedLidForecastController()
    private var keepsWorkingWithLidClosed: Bool?
    private var energyMode: EnergyMode?
    private var batterySnapshot: BatterySnapshot?
    private var closedLidEstimate: ActiveClosedLidEstimate?
    private var confirmationPopover: NSPopover?
    private var hoverPopover: NSPopover?
    private var hoverWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = StatusIconRenderer.image(keepsWorking: nil, forecastHours: nil)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        toggleItem.target = self
        statusTextItem.isEnabled = false
        forecastItem.isEnabled = false
        energyModeHeader.isEnabled = false
        for item in [lowPowerItem, automaticPowerItem, highPowerItem] {
            item.target = self
        }

        menu.delegate = self
        menu.addItem(toggleItem)
        menu.addItem(statusTextItem)
        menu.addItem(forecastItem)
        menu.addItem(.separator())
        menu.addItem(energyModeHeader)
        menu.addItem(lowPowerItem)
        menu.addItem(automaticPowerItem)
        menu.addItem(highPowerItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        helperAccessItem.target = self
        menu.addItem(helperAccessItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit LidSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        forecastController.didUpdate = { [weak self] battery, estimate in
            self?.batterySnapshot = battery
            self?.closedLidEstimate = estimate
            self?.updateUI()
        }

        refresh()
        forecastController.start()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refresh() {
        keepsWorkingWithLidClosed = readSleepDisabled()
        energyMode = readEnergyMode()
        updateUI()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        closeHoverPopover()
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else {
            toggleClosedLidWork()
        }
    }

    @objc func mouseEntered(with event: NSEvent) {
        hoverWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.showHoverPopover() }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @objc func mouseExited(with event: NSEvent) {
        closeHoverPopover()
    }

    private func showHoverPopover() {
        guard confirmationPopover?.isShown != true,
              hoverPopover?.isShown != true,
              let button = statusItem.button else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = HoverStatusViewController(model: HoverStatusModel(
            keepsWorking: keepsWorkingWithLidClosed,
            hours: closedLidEstimate?.hours,
            source: batterySnapshot?.forecastSource
        ))
        hoverPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closeHoverPopover() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hoverPopover?.close()
        hoverPopover = nil
    }

    @objc private func toggleClosedLidWork() {
        keepsWorkingWithLidClosed = readSleepDisabled()
        updateUI()

        guard let currentState = keepsWorkingWithLidClosed else {
            showError(
                title: "Couldn’t read the setting",
                message: "macOS did not report whether system sleep is disabled."
            )
            return
        }

        do {
            guard try ensureHelperInstalled() else { return }

            let newState = !currentState
            try helperManager.setKeepsWorkingWithLidClosed(newState)
            keepsWorkingWithLidClosed = readSleepDisabled()
            guard keepsWorkingWithLidClosed == newState else {
                throw NSError(
                    domain: "LidSwitch.PowerManagement",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "macOS did not apply the requested sleep setting."]
                )
            }
            updateUI()
            showConfirmation(newState
                ? "Mac will keep working when the lid is closed"
                : "Mac will sleep when the lid is closed")
        } catch let error as NSError where error.code == -128 {
            // The user cancelled the one-time administrator prompt.
        } catch {
            showError(title: "Couldn’t update the setting", message: error.localizedDescription)
        }
    }

    @objc private func selectLowPowerMode() {
        selectEnergyMode(.lowPower)
    }

    @objc private func selectAutomaticPowerMode() {
        selectEnergyMode(.automatic)
    }

    @objc private func selectHighPowerMode() {
        selectEnergyMode(.highPower)
    }

    private func selectEnergyMode(_ mode: EnergyMode) {
        guard energyMode != mode else { return }
        do {
            guard try ensureHelperInstalled() else { return }
            try helperManager.setEnergyMode(mode)
            energyMode = readEnergyMode()
            guard energyMode == mode else {
                throw NSError(
                    domain: "LidSwitch.PowerManagement",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "macOS did not apply the requested energy mode."]
                )
            }
            updateUI()
            let title: String
            switch mode {
            case .lowPower: title = "Включён режим энергосбережения"
            case .automatic: title = "Включён автоматический режим"
            case .highPower: title = "Включена высокая производительность"
            }
            showConfirmation(title)
        } catch let error as NSError where error.code == -128 {
            // The user cancelled the one-time administrator prompt.
        } catch {
            showError(title: "Не удалось изменить режим энергии", message: error.localizedDescription)
        }
    }

    private func ensureHelperInstalled() throws -> Bool {
        guard !helperManager.isInstalled else { return true }
        let alert = NSAlert()
        alert.messageText = "Set up passwordless switching?"
        alert.informativeText = "macOS will ask once for Touch ID or an administrator password to install LidSwitch’s narrowly scoped helper. Future switches won’t ask again."
        alert.addButton(withTitle: "Set Up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        try helperManager.install()
        return true
    }

    private func showConfirmation(_ message: String) {
        guard let button = statusItem.button else { return }

        confirmationPopover?.close()
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 54))
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
        ])

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = controller.view.frame.size
        popover.contentViewController = controller
        confirmationPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak popover] in
            popover?.close()
            if self?.confirmationPopover === popover {
                self?.confirmationPopover = nil
            }
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

    private func readSleepDisabled() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        return value.boolValue
    }

    private func readEnergyMode() -> EnergyMode? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return EnergyMode.parse(pmsetOutput: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ))
        } catch {
            return nil
        }
    }

    private func updateUI() {
        switch keepsWorkingWithLidClosed {
        case true:
            toggleItem.title = "Allow sleep when lid closes"
            toggleItem.state = .on
            toggleItem.isEnabled = true
            statusTextItem.title = "Closed-lid work: Enabled"
        case false:
            toggleItem.title = "Keep working when lid closes"
            toggleItem.state = .off
            toggleItem.isEnabled = true
            statusTextItem.title = "Closed-lid work: Disabled"
        case nil:
            toggleItem.title = "Closed-lid work"
            toggleItem.state = .mixed
            toggleItem.isEnabled = false
            statusTextItem.title = "Closed-lid work: Unknown"
        }

        lowPowerItem.state = energyMode == .lowPower ? .on : .off
        automaticPowerItem.state = energyMode == .automatic ? .on : .off
        highPowerItem.state = energyMode == .highPower ? .on : .off

        updateForecastUI()
        helperAccessItem.title = helperManager.isInstalled
            ? "Remove passwordless switching…"
            : "Set up passwordless switching…"
    }

    private func updateForecastUI() {
        guard let batterySnapshot else {
            forecastItem.isHidden = false
            forecastItem.title = "Closed-lid estimate: learning…"
            statusItem.button?.image = StatusIconRenderer.image(
                keepsWorking: keepsWorkingWithLidClosed,
                forecastHours: nil
            )
            statusItem.button?.toolTip = nil
            return
        }

        forecastItem.isHidden = false
        if let closedLidEstimate {
            let basis: String
            switch batterySnapshot.forecastSource {
            case .measuredClosed: basis = "расход измерен с закрытой крышкой"
            case .modeledDisplayOff: basis = "текущий расход без энергопотребления экрана"
            case .learnedOnAC: basis = "последний расход, изученный при работе от батареи"
            case .baselineOnAC(let watts): basis = "предварительная модель \(watts) Вт, пока нет истории"
            }
            forecastItem.title = "Active with lid closed: ≈ \(closedLidEstimate.hours) h (\(basis))"
            statusItem.button?.image = StatusIconRenderer.image(
                keepsWorking: keepsWorkingWithLidClosed,
                forecastHours: closedLidEstimate.hours
            )
            statusItem.button?.toolTip = nil
        } else {
            forecastItem.title = "Closed-lid estimate: learning…"
            statusItem.button?.image = StatusIconRenderer.image(
                keepsWorking: keepsWorkingWithLidClosed,
                forecastHours: nil
            )
            statusItem.button?.toolTip = nil
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
