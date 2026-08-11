import Darwin
import Foundation
import LidSwitchDaemonProtocol

private final class DaemonService: NSObject, LidSwitchDaemonXPCProtocol {
    func checkVersion(withReply reply: @escaping (String) -> Void) {
        reply("\(LidSwitchDaemonConstants.protocolVersion);euid=\(geteuid())")
    }
}

private final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = DaemonService()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: LidSwitchDaemonXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.activate()
        return true
    }
}

private let clientRequirement = PeerCodeSigningRequirement.forPeer(
    identifier: LidSwitchDaemonConstants.appIdentifier
)
private let delegate = DaemonListenerDelegate()
private let listener = NSXPCListener(machServiceName: LidSwitchDaemonConstants.machServiceName)

// The listener rejects a mismatched peer before its delegate sees a connection.
listener.setConnectionCodeSigningRequirement(clientRequirement.value)
listener.delegate = delegate
listener.activate()
RunLoop.main.run()
