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
    try require(methodCount == 1, "XPC protocol surface must contain exactly one operation")
    guard let methodName = methodDescriptions.pointee.name else {
        throw CheckFailure.failed("XPC operation has no Objective-C selector")
    }
    try require(
        NSStringFromSelector(methodName) == "checkVersionWithReply:",
        "Unexpected XPC operation"
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
        "EnableTransactions"
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
    try require(
        ["m2-spike-v1", "m2-spike-v2"].contains(LidSwitchDaemonConstants.protocolVersion),
        "Unknown M2 protocol fixture version"
    )

    print("All LidSwitchDaemonProtocol checks passed")
} catch {
    fputs("LidSwitchDaemonProtocol check failed: \(error)\n", stderr)
    exit(1)
}
