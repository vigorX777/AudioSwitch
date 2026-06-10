// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioSwitch",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "AudioSwitchCore", targets: ["AudioSwitchCore"]),
        .executable(name: "AudioSwitch", targets: ["AudioSwitch"]),
        .executable(name: "AudioSwitchCoreChecks", targets: ["AudioSwitchCoreChecks"]),
    ],
    targets: [
        .target(
            name: "AudioSwitchCore",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
            ]
        ),
        .executableTarget(
            name: "AudioSwitch",
            dependencies: ["AudioSwitchCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "AudioSwitchCoreChecks",
            dependencies: ["AudioSwitchCore"],
            path: "Checks/AudioSwitchCoreChecks"
        ),
    ],
    swiftLanguageModes: [.v6]
)
