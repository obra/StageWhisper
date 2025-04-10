// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "StageWhisper",
    platforms: [
        .macOS("13.3")
    ],
    products: [
        .executable(name: "StageWhisper", targets: ["StageWhisper"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "StageWhisper",
            dependencies: [
                "HotKey",
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ])
    ]
)
