// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPulseCore", targets: ["CodexPulseCore"]),
        .executable(name: "CodexPulse", targets: ["CodexPulse"]),
        .executable(name: "CodexPulseProbe", targets: ["CodexPulseProbe"])
    ],
    targets: [
        .target(
            name: "CodexPulseCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodexPulse",
            dependencies: ["CodexPulseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CodexPulseProbe",
            dependencies: ["CodexPulseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CodexPulseCoreTests",
            dependencies: ["CodexPulseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
