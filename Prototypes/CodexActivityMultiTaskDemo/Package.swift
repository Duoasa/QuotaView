// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexActivityMultiTaskDemo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexActivityMultiTaskDemo",
            targets: ["CodexActivityMultiTaskDemo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexActivityMultiTaskDemo",
            path: "Sources/CodexActivityMultiTaskDemo",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CodexActivityMultiTaskDemoTests",
            dependencies: ["CodexActivityMultiTaskDemo"],
            path: "Tests/CodexActivityMultiTaskDemoTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
