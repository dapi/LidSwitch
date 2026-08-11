import Foundation
import LidSwitchCore

check(
    BootPreference.parse(nvramOutput: Data(), exitCode: 1) == .defaultBehavior,
    "An absent preference should use default behavior"
)

check(parse("BootPreference\t%00\n") == .disableLidAndPower, "Should parse %00")
check(parse("BootPreference\t%01\n") == .disableLid, "Should parse %01")
check(parse("BootPreference\t%02\n") == .disablePower, "Should parse %02")

check(
    BootPreference.parse(
        nvramOutput: Data("BootPreference\t".utf8) + Data([1, 10]),
        exitCode: 0
    ) == .disableLid,
    "Should parse a raw byte value"
)

check(
    BootPreference.defaultBehavior.command(toStartWhenLidOpens: false) == .set(value: "%01"),
    "Disabling lid startup from defaults should set %01"
)
check(
    BootPreference.disablePower.command(toStartWhenLidOpens: false) == .set(value: "%00"),
    "Disabling lid startup should preserve disabled power startup"
)
check(
    BootPreference.disableLid.command(toStartWhenLidOpens: true) == .delete,
    "Enabling lid startup should restore defaults when power startup is enabled"
)
check(
    BootPreference.disableLidAndPower.command(toStartWhenLidOpens: true) == .set(value: "%02"),
    "Enabling lid startup should preserve disabled power startup"
)

print("All LidSwitchCore checks passed")

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

private func parse(_ string: String) -> BootPreference {
    BootPreference.parse(nvramOutput: Data(string.utf8), exitCode: 0)
}
