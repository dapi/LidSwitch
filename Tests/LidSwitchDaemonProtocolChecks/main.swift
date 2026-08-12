import Foundation
import LidSwitchDaemonProtocol
import ObjectiveC
import Security

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

func requireValidRequirement(_ value: String) throws {
    var requirement: SecRequirement?
    let status = SecRequirementCreateWithString(value as CFString, [], &requirement)
    try require(status == errSecSuccess && requirement != nil, "Invalid requirement: \(value)")
}

do {
    var methodCount: UInt32 = 0
    guard let methodDescriptions = protocol_copyMethodDescriptionList(
        LidSwitchDaemonXPCProtocol.self,
        true,
        true,
        &methodCount
    ) else {
        throw CheckFailure.failed("XPC protocol exposes no required instance method")
    }
    defer { free(methodDescriptions) }
    try require(methodCount == 4, "Daemon XPC protocol surface must contain exactly four operations")
    let daemonSelectors = Set((0..<Int(methodCount)).compactMap { index -> String? in
        guard let name = methodDescriptions[index].name else { return nil }
        return NSStringFromSelector(name)
    })
    try require(daemonSelectors == [
        "checkVersionWithReply:",
        "activateWithPolicyRaw:protocolVersion:withReply:",
        "heartbeatWithReply:",
        "feedbackDidFinishWithEventID:withReply:"
    ], "Unexpected daemon XPC operations: \(daemonSelectors)")

    var callbackMethodCount: UInt32 = 0
    guard let callbackDescriptions = protocol_copyMethodDescriptionList(
        LidSwitchAppXPCProtocol.self,
        true,
        true,
        &callbackMethodCount
    ) else {
        throw CheckFailure.failed("App callback protocol exposes no required instance method")
    }
    defer { free(callbackDescriptions) }
    try require(callbackMethodCount == 1, "App callback protocol must contain exactly one operation")
    let callbackSelector = callbackDescriptions.pointee.name.map(NSStringFromSelector)
    try require(callbackSelector == "lidDidCloseWithEventID:policyRaw:", "Unexpected app callback operation")
    try require(
        DaemonLidPolicy.allCases.map(\.rawValue) == [1, 2],
        "Managed policy transport values must remain work=1 and sleep=2"
    )

    let adHoc = PeerCodeSigningRequirement.forPeer(
        identifier: LidSwitchDaemonConstants.appIdentifier,
        teamIdentifier: nil
    )
    try require(
        adHoc.value == "identifier \"me.dapi.LidSwitch\"",
        "Ad-hoc requirement must constrain the exact app identifier"
    )
    try require(!adHoc.isProductionGrade, "Ad-hoc requirement must not be production-grade")
    try requireValidRequirement(adHoc.value)

    let production = PeerCodeSigningRequirement.forPeer(
        identifier: LidSwitchDaemonConstants.daemonIdentifier,
        teamIdentifier: "ABCDE12345"
    )
    try require(
        production.value == "anchor apple generic and identifier \"me.dapi.LidSwitch.Daemon\" "
            + "and certificate leaf[subject.OU] = \"ABCDE12345\"",
        "Production requirement must constrain anchor, identifier, and Team ID"
    )
    try require(production.isProductionGrade, "Team-bound requirement must be production-grade")
    try requireValidRequirement(production.value)

    let sourceURL = URL(fileURLWithPath: #filePath)
    let repoURL = sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let plistURL = repoURL.appendingPathComponent(
        "Resources/me.dapi.LidSwitch.Daemon.plist"
    )
    let plistData = try Data(contentsOf: plistURL)
    guard let plist = try PropertyListSerialization.propertyList(
        from: plistData,
        format: nil
    ) as? [String: Any] else {
        throw CheckFailure.failed("Launch daemon plist is not a dictionary")
    }

    let allowedKeys: Set<String> = [
        "Label",
        "BundleProgram",
        "AssociatedBundleIdentifiers",
        "MachServices",
        "EnableTransactions",
        "KeepAlive"
    ]
    try require(Set(plist.keys) == allowedKeys, "Launch daemon plist surface changed")
    try require(
        plist["Label"] as? String == LidSwitchDaemonConstants.daemonIdentifier,
        "Unexpected launch daemon label"
    )
    try require(
        plist["BundleProgram"] as? String == "Contents/MacOS/LidSwitchDaemon",
        "Unexpected daemon executable path"
    )
    try require(
        plist["AssociatedBundleIdentifiers"] as? [String]
            == [LidSwitchDaemonConstants.appIdentifier],
        "Unexpected associated bundle identifiers"
    )
    try require(
        plist["MachServices"] as? [String: Bool]
            == [LidSwitchDaemonConstants.machServiceName: true],
        "Unexpected Mach service surface"
    )
    try require(plist["EnableTransactions"] as? Bool == true, "Transactions must be enabled")
    try require(plist["KeepAlive"] as? Bool == true, "Daemon must restart to restore native sleep after a crash")
    try require(LidSwitchDaemonConstants.protocolVersion == "managed-lid-v1", "Unexpected managed-lid protocol version")

    print("All LidSwitchDaemonProtocol checks passed")
} catch {
    fputs("LidSwitchDaemonProtocol check failed: \(error)\n", stderr)
    exit(1)
}
