import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import LidSwitchDaemonCore
import LidSwitchDaemonProtocol

private let sleepWarningDuration: TimeInterval = 15
private let feedbackDeadline: TimeInterval = sleepWarningDuration + 1
private let leaseDeadline: TimeInterval = 15

private final class PowerEffects {
    @discardableResult
    func setSleepDisabled(_ disabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            fputs("LidSwitchDaemon: pmset failed: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    func requestSystemSleep() {
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else {
            fputs("LidSwitchDaemon: IOPMFindPowerManagement failed\n", stderr)
            return
        }
        defer { IOServiceClose(connection) }
        let result = IOPMSleepSystem(connection)
        if result != kIOReturnSuccess {
            fputs("LidSwitchDaemon: IOPMSleepSystem failed: \(result)\n", stderr)
        }
    }
}

private final class ManagedLidRuntime {
    private let queue = DispatchQueue(label: "me.dapi.LidSwitch.Daemon.state")
    private let effects = PowerEffects()
    private var machine = ManagedLidStateMachine()
    private var client: LidSwitchAppXPCProtocol?
    private var currentGeneration: String?
    private var leaseTimer: DispatchWorkItem?
    private var feedbackTimer: DispatchWorkItem?

    init() {
        // A daemon restart must never inherit an unattended keep-awake state.
        _ = effects.setSleepDisabled(false)
    }

    func activate(
        policyRaw: Int,
        protocolVersion: String,
        generation: String,
        client: LidSwitchAppXPCProtocol?,
        reply: @escaping (Bool, Int, String) -> Void
    ) {
        queue.async {
            guard protocolVersion == LidSwitchDaemonConstants.protocolVersion else {
                reply(false, 0, "Incompatible LidSwitch protocol.")
                return
            }
            guard let policy = ManagedLidPolicy(rawValue: policyRaw), let client else {
                reply(false, 0, "Invalid managed lid policy or callback interface.")
                return
            }

            if let oldGeneration = self.currentGeneration {
                self.apply(self.machine.leaseExpired(generation: oldGeneration))
            }
            self.client = client
            self.currentGeneration = generation
            let actions = self.machine.activate(policy: policy, generation: generation)
            guard self.apply(actions) else {
                self.apply(self.machine.deactivate())
                self.client = nil
                self.currentGeneration = nil
                reply(false, 0, "Could not enable managed lid control.")
                return
            }
            reply(true, policy.rawValue, "Managed lid control active.")
        }
    }

    func heartbeat(generation: String, reply: @escaping (Bool) -> Void) {
        queue.async {
            let actions = self.machine.heartbeat(generation: generation)
            guard !actions.isEmpty else {
                reply(false)
                return
            }
            _ = self.apply(actions)
            reply(true)
        }
    }

    func feedbackFinished(
        eventID: String,
        generation: String,
        reply: @escaping (Bool) -> Void
    ) {
        queue.async {
            let actions = self.machine.feedbackFinished(eventID: eventID, generation: generation)
            guard !actions.isEmpty else {
                reply(false)
                return
            }
            self.currentGeneration = nil
            self.client = nil
            _ = self.apply(actions)
            reply(true)
        }
    }

    func connectionLost(generation: String) {
        queue.async {
            let actions = self.machine.leaseExpired(generation: generation)
            guard !actions.isEmpty else { return }
            self.currentGeneration = nil
            self.client = nil
            _ = self.apply(actions)
        }
    }

    func observeLid(isClosed: Bool?) {
        queue.async {
            _ = self.apply(self.machine.observeLid(isClosed: isClosed) { UUID().uuidString })
        }
    }

    @discardableResult
    private func apply(_ actions: [ManagedLidAction]) -> Bool {
        var succeeded = true
        for action in actions {
            switch action {
            case .setSleepDisabled(let disabled):
                succeeded = effects.setSleepDisabled(disabled) && succeeded
            case .notifyLidClosed(let eventID, let policy):
                client?.lidDidClose(eventID: eventID, policyRaw: policy.rawValue)
            case .notifySleepCancelled(let eventID):
                client?.sleepCancelled(eventID: eventID)
            case .armLeaseDeadline(let generation):
                leaseTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        let actions = self.machine.leaseExpired(generation: generation)
                        guard !actions.isEmpty else { return }
                        self.currentGeneration = nil
                        self.client = nil
                        _ = self.apply(actions)
                    }
                }
                leaseTimer = timer
                queue.asyncAfter(deadline: .now() + leaseDeadline, execute: timer)
            case .armFeedbackDeadline(let eventID):
                feedbackTimer?.cancel()
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        let actions = self.machine.feedbackDeadlineExpired(eventID: eventID)
                        guard !actions.isEmpty else { return }
                        self.currentGeneration = nil
                        self.client = nil
                        _ = self.apply(actions)
                    }
                }
                feedbackTimer = timer
                queue.asyncAfter(deadline: .now() + feedbackDeadline, execute: timer)
            case .cancelFeedbackDeadline:
                feedbackTimer?.cancel()
                feedbackTimer = nil
            case .requestSystemSleep:
                effects.requestSystemSleep()
            }
        }
        return succeeded
    }
}

private final class ClamshellObserver {
    // IOPM.h: iokit_family_msg(sub_iokit_powermanagement, 0x100).
    private static let messageType: UInt32 = 0xe0034100
    private let runtime: ManagedLidRuntime
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(runtime: ManagedLidRuntime) {
        self.runtime = runtime
    }

    func start() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else {
            fputs("LidSwitchDaemon: could not observe IOPMrootDomain\n", stderr)
            return
        }
        defer { IOObjectRelease(service) }
        notificationPort = port
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { context, _, messageType, _ in
                guard messageType == ClamshellObserver.messageType, let context else { return }
                Unmanaged<ClamshellObserver>.fromOpaque(context).takeUnretainedValue().publishCurrentState()
            },
            context,
            &notifier
        )
        guard result == kIOReturnSuccess,
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            fputs("LidSwitchDaemon: clamshell notification registration failed: \(result)\n", stderr)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        publishCurrentState()
    }

    private func publishCurrentState() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            runtime.observeLid(isClosed: nil)
            return
        }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber
        runtime.observeLid(isClosed: value?.boolValue)
    }

    deinit {
        if notifier != 0 { IOObjectRelease(notifier) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
    }
}

private final class DaemonService: NSObject, LidSwitchDaemonXPCProtocol {
    private let runtime: ManagedLidRuntime
    private let generation: String
    private weak var connection: NSXPCConnection?

    init(runtime: ManagedLidRuntime, generation: String, connection: NSXPCConnection) {
        self.runtime = runtime
        self.generation = generation
        self.connection = connection
    }

    func checkVersion(withReply reply: @escaping (String) -> Void) {
        reply("\(LidSwitchDaemonConstants.protocolVersion);euid=\(geteuid())")
    }

    func activate(
        policyRaw: Int,
        protocolVersion: String,
        withReply reply: @escaping (Bool, Int, String) -> Void
    ) {
        let client = connection?.remoteObjectProxyWithErrorHandler { error in
            fputs("LidSwitchDaemon: app callback unavailable: \(error.localizedDescription)\n", stderr)
        } as? LidSwitchAppXPCProtocol
        runtime.activate(
            policyRaw: policyRaw,
            protocolVersion: protocolVersion,
            generation: generation,
            client: client,
            reply: reply
        )
    }

    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        runtime.heartbeat(generation: generation, reply: reply)
    }

    func feedbackDidFinish(eventID: String, withReply reply: @escaping (Bool) -> Void) {
        runtime.feedbackFinished(eventID: eventID, generation: generation, reply: reply)
    }
}

private final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let runtime: ManagedLidRuntime

    init(runtime: ManagedLidRuntime) {
        self.runtime = runtime
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let generation = UUID().uuidString
        let service = DaemonService(runtime: runtime, generation: generation, connection: newConnection)
        newConnection.exportedInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: LidSwitchAppXPCProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.runtime.connectionLost(generation: generation)
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.runtime.connectionLost(generation: generation)
        }
        newConnection.activate()
        return true
    }
}

private let runtime = ManagedLidRuntime()
private let observer = ClamshellObserver(runtime: runtime)
private let clientRequirement = PeerCodeSigningRequirement.forPeer(
    identifier: LidSwitchDaemonConstants.appIdentifier
)
private let delegate = DaemonListenerDelegate(runtime: runtime)
private let listener = NSXPCListener(machServiceName: LidSwitchDaemonConstants.machServiceName)

listener.setConnectionCodeSigningRequirement(clientRequirement.value)
listener.delegate = delegate
listener.activate()
observer.start()
RunLoop.main.run()
