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

final class ServiceManagedDaemonManager {
    private let service = SMAppService.daemon(plistName: LidSwitchDaemonConstants.plistName)

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
        let requirement = PeerCodeSigningRequirement.forPeer(
            identifier: LidSwitchDaemonConstants.daemonIdentifier
        )
        if let teamIdentifier = requirement.teamIdentifier {
            return "Bundle ID + Team ID \(teamIdentifier)"
        }
        return "Bundle ID only (ad-hoc development build; not production-safe)"
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func checkVersion(
        timeout: TimeInterval = 5,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let connection = NSXPCConnection(
            machServiceName: LidSwitchDaemonConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)

        let daemonRequirement = PeerCodeSigningRequirement.forPeer(
            identifier: LidSwitchDaemonConstants.daemonIdentifier
        )
        connection.setCodeSigningRequirement(daemonRequirement.value)

        let lock = NSLock()
        var hasFinished = false
        let finish: (Result<String, Error>) -> Void = { result in
            lock.lock()
            guard !hasFinished else {
                lock.unlock()
                return
            }
            hasFinished = true
            lock.unlock()
            connection.invalidate()
            completion(result)
        }

        connection.invalidationHandler = {
            finish(.failure(Self.error("The daemon connection was invalidated.")))
        }
        connection.interruptionHandler = {
            finish(.failure(Self.error("The daemon connection was interrupted.")))
        }
        connection.activate()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            finish(.failure(error))
        }) as? LidSwitchDaemonXPCProtocol else {
            finish(.failure(Self.error("The daemon did not expose the expected XPC interface.")))
            return
        }

        proxy.checkVersion { version in
            finish(.success(version))
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            finish(.failure(Self.error("Timed out waiting for the daemon.")))
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "LidSwitch.ServiceManagedDaemon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
