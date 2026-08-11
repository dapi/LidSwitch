import Foundation

public enum BootPreference: Equatable, Sendable {
    /// No override: opening the lid and connecting power can start the Mac.
    case defaultBehavior
    /// Opening the lid does not start the Mac.
    case disableLid
    /// Connecting power does not start the Mac.
    case disablePower
    /// Neither opening the lid nor connecting power starts the Mac.
    case disableLidAndPower
    /// A value introduced by a future macOS version or another tool.
    case unknown(String)

    public var startsWhenLidOpens: Bool? {
        switch self {
        case .defaultBehavior, .disablePower:
            return true
        case .disableLid, .disableLidAndPower:
            return false
        case .unknown:
            return nil
        }
    }

    public static func parse(nvramOutput: Data?, exitCode: Int32) -> BootPreference {
        // `nvram BootPreference` exits non-zero when the variable is absent.
        guard exitCode == 0, let nvramOutput, !nvramOutput.isEmpty else {
            return .defaultBehavior
        }

        let bytes = Array(nvramOutput)
        if containsEncodedValue("%00", in: bytes) || containsRawValue(0, in: bytes) {
            return .disableLidAndPower
        }
        if containsEncodedValue("%01", in: bytes) || containsRawValue(1, in: bytes) {
            return .disableLid
        }
        if containsEncodedValue("%02", in: bytes) || containsRawValue(2, in: bytes) {
            return .disablePower
        }

        return .unknown(String(decoding: nvramOutput, as: UTF8.self))
    }

    /// Returns the command needed to change only lid behavior while preserving
    /// an existing power-connection preference.
    public func command(toStartWhenLidOpens shouldStart: Bool) -> PrivilegedCommand? {
        switch (self, shouldStart) {
        case (.defaultBehavior, true), (.disablePower, true),
             (.disableLid, false), (.disableLidAndPower, false):
            return nil
        case (.defaultBehavior, false):
            return .set(value: "%01")
        case (.disablePower, false):
            return .set(value: "%00")
        case (.disableLid, true):
            return .delete
        case (.disableLidAndPower, true):
            return .set(value: "%02")
        case (.unknown, _):
            return nil
        }
    }

    private static func containsEncodedValue(_ value: String, in bytes: [UInt8]) -> Bool {
        let needle = Array(value.utf8)
        return bytes.windows(ofCount: needle.count).contains { Array($0) == needle }
    }

    private static func containsRawValue(_ value: UInt8, in bytes: [UInt8]) -> Bool {
        guard let separator = bytes.lastIndex(where: { $0 == 9 || $0 == 32 }) else {
            return false
        }
        return bytes[(separator + 1)...].contains(value)
    }
}

public enum PrivilegedCommand: Equatable, Sendable {
    case set(value: String)
    case delete

    public var shellCommand: String {
        switch self {
        case .set(let value):
            return "/usr/sbin/nvram BootPreference=\(value)"
        case .delete:
            return "/usr/sbin/nvram -d BootPreference"
        }
    }
}

private extension Array {
    func windows(ofCount count: Int) -> AnySequence<ArraySlice<Element>> {
        guard count > 0, count <= self.count else { return AnySequence([]) }
        return AnySequence((0...(self.count - count)).lazy.map { self[$0..<($0 + count)] })
    }
}

