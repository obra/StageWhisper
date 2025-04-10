// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "swift-insert",
    platforms: [
        .macOS("13.3")
    ],
    products: [
        .executable(name: "swift-insert", targets: ["swift-insert"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "swift-insert",
            dependencies: [
                "HotKey",
                .product(name: "WhisperKit", package: "WhisperKit")
            ])
    ]
)
