// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaView",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuotaViewCore", targets: ["QuotaViewCore"]),
        .executable(name: "QuotaView", targets: ["QuotaView"]),
        .executable(name: "QuotaViewProbe", targets: ["QuotaViewProbe"])
    ],
    targets: [
        .target(
            name: "QuotaViewCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuotaView",
            dependencies: ["QuotaViewCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuotaViewProbe",
            dependencies: ["QuotaViewCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuotaViewCoreTests",
            dependencies: ["QuotaViewCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
