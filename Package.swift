// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LidSwitch",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LidSwitch", targets: ["LidSwitch"])
    ],
    targets: [
        .target(name: "LidSwitchCore"),
        .executableTarget(
            name: "LidSwitch",
            dependencies: ["LidSwitchCore"]
        ),
        .executableTarget(
            name: "LidSwitchCoreChecks",
            dependencies: ["LidSwitchCore"],
            path: "Tests/LidSwitchCoreChecks"
        )
    ],
    swiftLanguageModes: [.v5]
)
