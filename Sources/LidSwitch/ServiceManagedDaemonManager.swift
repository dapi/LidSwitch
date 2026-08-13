import Foundation
import LidSwitchDaemonProtocol
import ServiceManagement

enum ServiceManagedDaemonStatus: String {
    case notRegistered = "Not registered"
    case enabled = "Enabled"
    case requiresApproval = "Requires approval"
    case notFound = "Not found in app bundle"
    case unknown = "Unknown"
}

final class ServiceManagedDaemonManager: NSObject, LidSwitchAppXPCProtocol {
    private let service = SMAppService.daemon(plistName: LidSwitchDaemonConstants.plistName)
    private var connection: NSXPCConnection?
    private var heartbeatTimer: Timer?
    private(set) var effectivePolicy: DaemonLidPolicy?
    private(set) var lastError: String?

    var didChange: (() -> Void)?
    var didCloseLid: ((String, DaemonLidPolicy) -> Void)?
    var didCancelSleep: ((String) -> Void)?

    var status: ServiceManagedDaemonStatus {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    var peerAuthenticationDescription: String {
        let requirement = PeerCodeSigningRequirement.forPeer(identifier: LidSwitchDaemonConstants.daemonIdentifier)
        if let teamIdentifier = requirement.teamIdentifier {
            return "Bundle ID + Team ID \(teamIdentifier)"
        }
        return "Bundle ID only (ad-hoc development build; not production-safe)"
    }

    func register() throws { try service.register() }

    func unregister() throws {
        disconnect()
        try service.unregister()
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    func activate(policy: DaemonLidPolicy, completion: ((Bool, String) -> Void)? = nil) {
        disconnect(markUnavailable: false)
        guard status == .enabled else {
            effectivePolicy = nil
            lastError = "Managed lid control requires the daemon to be enabled."
            didChange?()
            completion?(false, lastError!)
            return
        }

        let newConnection = NSXPCConnection(
            machServiceName: LidSwitchDaemonConstants.machServiceName,
            options: .privileged
        )
        newConnection.remoteObjectInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: LidSwitchAppXPCProtocol.self)
        newConnection.exportedObject = self
        let requirement = PeerCodeSigningRequirement.forPeer(identifier: LidSwitchDaemonConstants.daemonIdentifier)
        newConnection.setCodeSigningRequirement(requirement.value)
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            DispatchQueue.main.async {
                guard self?.connection === newConnection else { return }
                self?.connection = nil
                self?.heartbeatTimer?.invalidate()
                self?.heartbeatTimer = nil
                self?.effectivePolicy = nil
                self?.lastError = "Managed lid connection was invalidated."
                self?.didChange?()
            }
        }
        newConnection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.effectivePolicy = nil
                self?.lastError = "Managed lid connection was interrupted."
                self?.didChange?()
            }
        }
        connection = newConnection
        newConnection.activate()

        guard let proxy = daemonProxy(errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.effectivePolicy = nil
                self?.lastError = error.localizedDescription
                self?.didChange?()
                completion?(false, error.localizedDescription)
            }
        }) else {
            completion?(false, "Daemon did not expose the expected interface.")
            return
        }
        proxy.activate(
            policyRaw: policy.rawValue,
            protocolVersion: LidSwitchDaemonConstants.protocolVersion
        ) { [weak self] accepted, effectiveRaw, message in
            DispatchQueue.main.async {
                guard let self, self.connection === newConnection else { return }
                self.effectivePolicy = accepted ? DaemonLidPolicy(rawValue: effectiveRaw) : nil
                self.lastError = accepted ? nil : message
                if accepted { self.startHeartbeat() }
                self.didChange?()
                completion?(accepted, message)
            }
        }
    }

    func reactivate(policy: DaemonLidPolicy) {
        activate(policy: policy)
    }

    func feedbackDidFinish(eventID: String) {
        daemonProxy(errorHandler: { _ in })?.feedbackDidFinish(eventID: eventID) { _ in }
    }

    func lidDidClose(eventID: String, policyRaw: Int) {
        guard let policy = DaemonLidPolicy(rawValue: policyRaw) else { return }
        LidSwitchDiagnostics.log("daemon lidDidClose event=\(eventID) policy=\(policy)")
        DispatchQueue.main.async { [weak self] in self?.didCloseLid?(eventID, policy) }
    }

    func sleepCancelled(eventID: String) {
        LidSwitchDiagnostics.log("daemon sleepCancelled event=\(eventID)")
        DispatchQueue.main.async { [weak self] in self?.didCancelSleep?(eventID) }
    }

    func checkVersion(
        timeout: TimeInterval = 5,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let probe = NSXPCConnection(
            machServiceName: LidSwitchDaemonConstants.machServiceName,
            options: .privileged
        )
        probe.remoteObjectInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)
        let requirement = PeerCodeSigningRequirement.forPeer(identifier: LidSwitchDaemonConstants.daemonIdentifier)
        probe.setCodeSigningRequirement(requirement.value)
        let lock = NSLock()
        var finished = false
        let finish: (Result<String, Error>) -> Void = { result in
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            probe.invalidate()
            completion(result)
        }
        probe.invalidationHandler = { finish(.failure(Self.error("The daemon connection was invalidated."))) }
        probe.interruptionHandler = { finish(.failure(Self.error("The daemon connection was interrupted."))) }
        probe.activate()
        guard let proxy = probe.remoteObjectProxyWithErrorHandler({ finish(.failure($0)) }) as? LidSwitchDaemonXPCProtocol else {
            finish(.failure(Self.error("The daemon did not expose the expected XPC interface.")))
            return
        }
        proxy.checkVersion { finish(.success($0)) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            finish(.failure(Self.error("Timed out waiting for the daemon.")))
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.daemonProxy(errorHandler: { _ in })?.heartbeat { accepted in
                guard !accepted else { return }
                DispatchQueue.main.async {
                    self.effectivePolicy = nil
                    self.lastError = "Managed lid lease was not renewed."
                    self.didChange?()
                }
            }
        }
    }

    private func daemonProxy(errorHandler: @escaping (Error) -> Void) -> LidSwitchDaemonXPCProtocol? {
        connection?.remoteObjectProxyWithErrorHandler(errorHandler) as? LidSwitchDaemonXPCProtocol
    }

    private func disconnect(markUnavailable: Bool = true) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connection?.invalidate()
        connection = nil
        if markUnavailable { effectivePolicy = nil }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "LidSwitch.ServiceManagedDaemon", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
