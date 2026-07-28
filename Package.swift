// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaView",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuotaViewCore", targets: ["QuotaViewCore"]),
        .library(
            name: "QuotaViewWidgetContract",
            targets: ["QuotaViewWidgetContract"]
        ),
        .library(
            name: "QuotaViewFutureContracts",
            targets: ["QuotaViewFutureContracts"]
        ),
        .executable(name: "QuotaView", targets: ["QuotaView"]),
        .executable(name: "QuotaViewProbe", targets: ["QuotaViewProbe"])
    ],
    targets: [
        .target(
            name: "QuotaViewCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "QuotaViewWidgetContract",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "QuotaViewFutureContracts",
            dependencies: ["QuotaViewCore"],
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
            dependencies: [
                "QuotaViewCore",
                "QuotaViewWidgetContract",
                "QuotaViewFutureContracts",
                "QuotaView"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
