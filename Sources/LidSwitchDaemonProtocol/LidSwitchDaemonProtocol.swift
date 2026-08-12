import Foundation
import Security

public enum DaemonLidPolicy: Int, CaseIterable, Equatable, Sendable {
    case work = 1
    case sleep = 2
}

@objc public protocol LidSwitchDaemonXPCProtocol {
    func checkVersion(withReply reply: @escaping (String) -> Void)
    func activate(
        policyRaw: Int,
        protocolVersion: String,
        withReply reply: @escaping (Bool, Int, String) -> Void
    )
    func heartbeat(withReply reply: @escaping (Bool) -> Void)
    func feedbackDidFinish(eventID: String, withReply reply: @escaping (Bool) -> Void)
}

@objc public protocol LidSwitchAppXPCProtocol {
    func lidDidClose(eventID: String, policyRaw: Int)
    func sleepCancelled(eventID: String)
}

public enum LidSwitchDaemonConstants {
    public static let appIdentifier = "me.dapi.LidSwitch"
    public static let daemonIdentifier = "me.dapi.LidSwitch.Daemon"
    public static let machServiceName = "me.dapi.LidSwitch.Daemon.XPC"
    public static let plistName = "me.dapi.LidSwitch.Daemon.plist"
    public static let protocolVersion = "managed-lid-v2"
}

public struct PeerCodeSigningRequirement: Sendable {
    public let value: String
    public let teamIdentifier: String?

    public var isProductionGrade: Bool { teamIdentifier != nil }

    public static func forPeer(identifier: String) -> PeerCodeSigningRequirement {
        forPeer(identifier: identifier, teamIdentifier: currentTeamIdentifier())
    }

    package static func forPeer(
        identifier: String,
        teamIdentifier: String?
    ) -> PeerCodeSigningRequirement {
        let checkedIdentifier = checkedRequirementLiteral(identifier)
        guard let teamIdentifier, !teamIdentifier.isEmpty else {
            // Ad-hoc signatures have no Team ID. This fallback is useful for
            // local protocol tests, but another ad-hoc binary can claim the
            // same identifier, so callers must not treat it as production auth.
            return PeerCodeSigningRequirement(
                value: "identifier \"\(checkedIdentifier)\"",
                teamIdentifier: nil
            )
        }

        let checkedTeamIdentifier = checkedRequirementLiteral(teamIdentifier)
        return PeerCodeSigningRequirement(
            value: "anchor apple generic and identifier \"\(checkedIdentifier)\" "
                + "and certificate leaf[subject.OU] = \"\(checkedTeamIdentifier)\"",
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

    private static func checkedRequirementLiteral(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        precondition(
            !value.isEmpty && value.unicodeScalars.allSatisfy(allowed.contains),
            "Invalid code-signing requirement literal"
        )
        return value
    }
}
