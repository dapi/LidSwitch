import AppKit
import IOKit
import LidSwitchCore
import LidSwitchDaemonProtocol

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
    private let m2DaemonHeader = NSMenuItem(title: "Managed lid control", action: nil, keyEquivalent: "")
    private let m2DaemonStatusItem = NSMenuItem(title: "Status: Checking…", action: nil, keyEquivalent: "")
    private let m2DaemonRegisterItem = NSMenuItem(
        title: "Set up managed lid control…",
        action: #selector(registerM2Daemon),
        keyEquivalent: ""
    )
    private let m2DaemonCheckItem = NSMenuItem(
        title: "Check managed daemon version",
        action: #selector(checkM2DaemonVersion),
        keyEquivalent: ""
    )
    private let m2DaemonUnregisterItem = NSMenuItem(
        title: "Remove managed lid control…",
        action: #selector(unregisterM2Daemon),
        keyEquivalent: ""
    )
    private let helperManager = PrivilegedHelperManager()
    private let serviceManagedDaemonManager = ServiceManagedDaemonManager()
    private let outcomeSoundPlayer = LidOutcomeSoundPlayer()
    private let forecastController = ClosedLidForecastController()
    private var keepsWorkingWithLidClosed: Bool?
    private var energyMode: EnergyMode?
    private var batterySnapshot: BatterySnapshot?
    private var closedLidEstimate: ActiveClosedLidEstimate?
    private var confirmationPopover: NSPopover?
    private var hoverPopover: NSPopover?
    private var hoverWorkItem: DispatchWorkItem?
    private let desiredPolicyKey = "managedClosedLidWork"

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

        m2DaemonHeader.isEnabled = false
        m2DaemonStatusItem.isEnabled = false
        for item in [m2DaemonRegisterItem, m2DaemonCheckItem, m2DaemonUnregisterItem] {
            item.target = self
        }
        menu.addItem(m2DaemonHeader)
        menu.addItem(m2DaemonStatusItem)
        menu.addItem(m2DaemonRegisterItem)
        menu.addItem(m2DaemonCheckItem)
        menu.addItem(m2DaemonUnregisterItem)
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

        serviceManagedDaemonManager.didChange = { [weak self] in
            guard let self else { return }
            self.keepsWorkingWithLidClosed = self.serviceManagedDaemonManager.effectivePolicy.map { $0 == .work }
            self.updateUI()
        }
        serviceManagedDaemonManager.didCloseLid = { [weak self] eventID, policy in
            guard let self else { return }
            if policy == .sleep {
                self.outcomeSoundPlayer.play(policy: policy) { [weak self] in
                    self?.serviceManagedDaemonManager.feedbackDidFinish(eventID: eventID)
                }
            } else {
                self.outcomeSoundPlayer.play(policy: policy)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if UserDefaults.standard.object(forKey: desiredPolicyKey) == nil {
            UserDefaults.standard.set(readSleepDisabled() ?? false, forKey: desiredPolicyKey)
        }

        refresh()
        forecastController.start()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refresh() {
        keepsWorkingWithLidClosed = serviceManagedDaemonManager.effectivePolicy.map { $0 == .work }
        energyMode = readEnergyMode()
        if serviceManagedDaemonManager.status == .enabled,
           serviceManagedDaemonManager.effectivePolicy == nil {
            activateDesiredPolicy()
        }
        updateUI()
    }

    @objc private func systemDidWake() {
        activateDesiredPolicy()
    }

    private func activateDesiredPolicy(completion: ((Bool, String) -> Void)? = nil) {
        let work = UserDefaults.standard.bool(forKey: desiredPolicyKey)
        serviceManagedDaemonManager.activate(policy: work ? .work : .sleep, completion: completion)
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
        guard serviceManagedDaemonManager.status == .enabled else {
            showError(
                title: "Managed lid control isn’t ready",
                message: "Set up and approve the LidSwitch daemon before changing the closed-lid policy."
            )
            return
        }
        let current = serviceManagedDaemonManager.effectivePolicy == .work
        let newState = !current
        serviceManagedDaemonManager.activate(policy: newState ? .work : .sleep) { [weak self] accepted, message in
            guard let self else { return }
            guard accepted else {
                self.showError(title: "Couldn’t update the setting", message: message)
                return
            }
            UserDefaults.standard.set(newState, forKey: self.desiredPolicyKey)
            self.keepsWorkingWithLidClosed = newState
            self.updateUI()
            self.showConfirmation(newState
                ? "Mac will keep working when the lid is closed"
                : "Mac will play a sound, then sleep")
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

    @objc private func registerM2Daemon() {
        if serviceManagedDaemonManager.status == .requiresApproval {
            serviceManagedDaemonManager.openApprovalSettings()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Set up managed lid control?"
        alert.informativeText = "This registers the embedded LidSwitch daemon. It safely holds lid sleep until feedback finishes and restores native sleep if the app disconnects. macOS may require approval in Login Items."
        alert.addButton(withTitle: "Set Up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try serviceManagedDaemonManager.register()
            updateM2DaemonUI()
            if serviceManagedDaemonManager.status == .requiresApproval {
                serviceManagedDaemonManager.openApprovalSettings()
            } else {
                activateDesiredPolicy()
                showConfirmation("Managed lid control registration requested")
            }
        } catch {
            updateM2DaemonUI()
            if serviceManagedDaemonManager.status == .requiresApproval {
                serviceManagedDaemonManager.openApprovalSettings()
            } else {
                showError(title: "Couldn’t set up managed lid control", message: error.localizedDescription)
            }
        }
    }

    @objc private func checkM2DaemonVersion() {
        m2DaemonCheckItem.isEnabled = false
        m2DaemonCheckItem.title = "Checking managed daemon…"
        serviceManagedDaemonManager.checkVersion { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateM2DaemonUI()
                switch result {
                case .success(let response):
                    let expected = "\(LidSwitchDaemonConstants.protocolVersion);euid=0"
                    let isExpected = response == expected
                    if isExpected {
                        self.showConfirmation("Managed daemon replied: \(response)")
                    } else {
                        self.showError(
                            title: "Unexpected managed daemon response",
                            message: response
                        )
                    }
                case .failure(let error):
                    self.showError(
                        title: "Couldn’t contact the managed daemon",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    @objc private func unregisterM2Daemon() {
        let alert = NSAlert()
        alert.messageText = "Remove managed lid control?"
        alert.informativeText = "This unregisters the daemon and restores native lid sleep. The energy-mode helper is unchanged."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try serviceManagedDaemonManager.unregister()
            updateM2DaemonUI()
            keepsWorkingWithLidClosed = nil
            showConfirmation("Managed lid control removed")
        } catch {
            updateM2DaemonUI()
            showError(title: "Couldn’t remove managed lid control", message: error.localizedDescription)
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
        case .some(true):
            toggleItem.title = "Allow sleep when lid closes"
            toggleItem.state = .on
            toggleItem.isEnabled = true
            statusTextItem.title = "Closed-lid work: Enabled"
        case .some(false):
            toggleItem.title = "Keep working when lid closes"
            toggleItem.state = .off
            toggleItem.isEnabled = true
            statusTextItem.title = "Closed-lid work: Disabled"
        case .none:
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
        updateM2DaemonUI()
    }

    private func updateM2DaemonUI() {
        let status = serviceManagedDaemonManager.status
        m2DaemonStatusItem.title = "Status: \(status.rawValue); auth: \(serviceManagedDaemonManager.peerAuthenticationDescription)"

        switch status {
        case .notRegistered:
            m2DaemonRegisterItem.title = "Set up managed lid control…"
            m2DaemonRegisterItem.isEnabled = true
            m2DaemonCheckItem.isEnabled = false
            m2DaemonUnregisterItem.isEnabled = false
        case .requiresApproval:
            m2DaemonRegisterItem.title = "Open approval settings…"
            m2DaemonRegisterItem.isEnabled = true
            m2DaemonCheckItem.isEnabled = false
            m2DaemonUnregisterItem.isEnabled = true
        case .enabled:
            m2DaemonRegisterItem.title = "Managed lid control enabled"
            m2DaemonRegisterItem.isEnabled = false
            m2DaemonCheckItem.isEnabled = true
            m2DaemonUnregisterItem.isEnabled = true
        case .notFound, .unknown:
            m2DaemonRegisterItem.title = "Set up managed lid control…"
            m2DaemonRegisterItem.isEnabled = false
            m2DaemonCheckItem.isEnabled = false
            m2DaemonUnregisterItem.isEnabled = false
        }
        m2DaemonCheckItem.title = "Check managed daemon version"
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
                forecastHours: keepsWorkingWithLidClosed == true
                    ? closedLidEstimate.hours
                    : nil
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

private func runM2CommandLineModeIfRequested() {
    let arguments = CommandLine.arguments.dropFirst()
    let supportedArguments = [
        "--m2-daemon-status",
        "--m2-protocol-version",
        "--m2-check-version",
        "--m2-register",
        "--m2-unregister",
        "--m2-open-approval-settings"
    ]
    guard supportedArguments.contains(where: arguments.contains) else {
        return
    }

    let manager = ServiceManagedDaemonManager()
    if arguments.contains("--m2-protocol-version") {
        print(LidSwitchDaemonConstants.protocolVersion)
        exit(0)
    }

    if arguments.contains("--m2-daemon-status") {
        print("\(manager.status.rawValue); auth: \(manager.peerAuthenticationDescription); bundle: \(Bundle.main.bundlePath)")
        exit(0)
    }

    if arguments.contains("--m2-open-approval-settings") {
        manager.openApprovalSettings()
        exit(0)
    }

    if arguments.contains("--m2-register") || arguments.contains("--m2-unregister") {
        do {
            if arguments.contains("--m2-register") {
                try manager.register()
            } else {
                try manager.unregister()
            }
            print(manager.status.rawValue)
            exit(0)
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }

    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 1
    manager.checkVersion { result in
        switch result {
        case .success(let response):
            print(response)
            let expected = "\(LidSwitchDaemonConstants.protocolVersion);euid=0"
            exitCode = response == expected ? 0 : 1
        case .failure(let error):
            fputs(error.localizedDescription + "\n", stderr)
            exitCode = 1
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 7)
    exit(exitCode)
}

runM2CommandLineModeIfRequested()

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.delegate = delegate
application.run()
