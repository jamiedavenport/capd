// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cap",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CapKit", targets: ["CapKit"]),
        .executable(name: "cap", targets: ["CapCLI"]),
        .executable(name: "cap-agent", targets: ["CapAgent"]),
        .executable(name: "CapApp", targets: ["CapApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.13.7"),
    ],
    targets: [
        .target(
            name: "CapKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "SwiftSoup",
            ],
            resources: [.copy("Resources/Readability.js")]
        ),
        .executableTarget(
            name: "CapCLI",
            dependencies: [
                "CapKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "CapAgent",
            dependencies: ["CapKit"]
        ),
        .executableTarget(
            name: "CapApp",
            dependencies: [
                "CapKit",
                "KeyboardShortcuts",
            ]
        ),
        .testTarget(
            name: "CapKitTests",
            dependencies: [
                "CapKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapAppTests",
            dependencies: ["CapApp"]
        ),
        .testTarget(
            name: "CapCLITests",
            dependencies: [
                "CapCLI",
                "CapKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
