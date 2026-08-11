// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LidSwitch",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LidSwitch", targets: ["LidSwitch"]),
        .executable(name: "LidSwitchHelper", targets: ["LidSwitchHelper"]),
        .executable(name: "LidSwitchDaemon", targets: ["LidSwitchDaemon"]),
        .executable(name: "LidSwitchUnauthorizedProbe", targets: ["LidSwitchUnauthorizedProbe"])
    ],
    targets: [
        .target(name: "LidSwitchCore"),
        .target(name: "LidSwitchDaemonProtocol"),
        .executableTarget(
            name: "LidSwitch",
            dependencies: [
                "LidSwitchCore",
                "LidSwitchAuthorizationShim",
                "LidSwitchDaemonProtocol"
            ]
        ),
        .target(name: "LidSwitchAuthorizationShim"),
        .executableTarget(
            name: "LidSwitchHelper",
            dependencies: ["LidSwitchCore"]
        ),
        .executableTarget(
            name: "LidSwitchDaemon",
            dependencies: ["LidSwitchDaemonProtocol"]
        ),
        .executableTarget(
            name: "LidSwitchUnauthorizedProbe",
            dependencies: ["LidSwitchDaemonProtocol"]
        ),
        .executableTarget(
            name: "LidSwitchCoreChecks",
            dependencies: ["LidSwitchCore"],
            path: "Tests/LidSwitchCoreChecks"
        ),
        .executableTarget(
            name: "LidSwitchDaemonProtocolChecks",
            dependencies: ["LidSwitchDaemonProtocol"],
            path: "Tests/LidSwitchDaemonProtocolChecks"
        )
    ],
    swiftLanguageModes: [.v5]
)
