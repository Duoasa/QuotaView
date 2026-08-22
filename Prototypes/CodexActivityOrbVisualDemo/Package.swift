// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexActivityOrbVisualDemo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexActivityOrbVisualDemo",
            targets: ["CodexActivityOrbVisualDemo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexActivityOrbVisualDemo",
            path: "Sources/CodexActivityOrbVisualDemo",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CodexActivityOrbVisualDemoTests",
            dependencies: ["CodexActivityOrbVisualDemo"],
            path: "Tests/CodexActivityOrbVisualDemoTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
