import Foundation
import Security

@objc public protocol LidSwitchDaemonXPCProtocol {
    func checkVersion(withReply reply: @escaping (String) -> Void)
}

public enum LidSwitchDaemonConstants {
    public static let appIdentifier = "me.dapi.LidSwitch"
    public static let daemonIdentifier = "me.dapi.LidSwitch.Daemon"
    public static let machServiceName = "me.dapi.LidSwitch.Daemon.XPC"
    public static let plistName = "me.dapi.LidSwitch.Daemon.plist"
    public static let protocolVersion = "m2-spike-v1"
}

public struct PeerCodeSigningRequirement: Sendable {
    public let value: String
    public let teamIdentifier: String?

    public var isProductionGrade: Bool { teamIdentifier != nil }

    public static func forPeer(identifier: String) -> PeerCodeSigningRequirement {
        let escapedIdentifier = escapeRequirementLiteral(identifier)
        guard let teamIdentifier = currentTeamIdentifier() else {
            // Ad-hoc signatures have no Team ID. This fallback is useful for
            // local protocol tests, but another ad-hoc binary can claim the
            // same identifier, so callers must not treat it as production auth.
            return PeerCodeSigningRequirement(
                value: "identifier \"\(escapedIdentifier)\"",
                teamIdentifier: nil
            )
        }

        let escapedTeamIdentifier = escapeRequirementLiteral(teamIdentifier)
        return PeerCodeSigningRequirement(
            value: "anchor apple generic and identifier \"\(escapedIdentifier)\" "
                + "and certificate leaf[subject.OU] = \"\(escapedTeamIdentifier)\"",
            teamIdentifier: teamIdentifier
        )
    }

    private static func currentTeamIdentifier() -> String? {
        var currentCode: SecCode?
        guard SecCodeCopySelf([], &currentCode) == errSecSuccess,
              let currentCode else {
            return nil
        }

        var currentStaticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(currentCode, [], &currentStaticCode) == errSecSuccess,
              let currentStaticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            currentStaticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [CFString: Any],
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return teamIdentifier
    }

    private static func escapeRequirementLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
