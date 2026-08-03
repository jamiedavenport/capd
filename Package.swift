// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "capd",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CapdKit", targets: ["CapdKit"]),
        .library(name: "CapdAppUI", targets: ["CapdAppUI"]),
        .executable(name: "capd", targets: ["CapdCLI"]),
        .executable(name: "capd-agent", targets: ["CapdAgent"]),
        .executable(name: "CapdApp", targets: ["CapdApp"]),
        .executable(name: "CapdShareExtension", targets: ["CapdShareExtension"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.13.7"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .target(
            name: "CapdKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "SwiftSoup",
            ],
            resources: [.copy("Resources/Readability.js")]
        ),
        .executableTarget(
            name: "CapdCLI",
            dependencies: [
                "CapdKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .executableTarget(
            name: "CapdAgent",
            dependencies: ["CapdKit"],
            resources: [.copy("Resources/dev.jxd.capd.agent.plist")]
        ),
        .target(
            name: "CapdAppUI",
            dependencies: [
                "CapdKit",
                "KeyboardShortcuts",
            ]
        ),
        .target(name: "CapdHandoff"),
        .executableTarget(
            name: "CapdApp",
            dependencies: [
                "CapdKit",
                "CapdAppUI",
                "CapdHandoff",
                "KeyboardShortcuts",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CapdShareExtension",
            dependencies: ["CapdHandoff"],
            linkerSettings: [
                // App extensions enter at NSExtensionMain, not main; this is the
                // flag Xcode passes when linking an .appex binary.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .executableTarget(
            name: "CapdTestHost",
            dependencies: ["CapdKit"],
            path: "Tests/CapdTestHost"
        ),
        .testTarget(
            name: "CapdKitTests",
            dependencies: [
                "CapdKit",
                "CapdTestHost",
                .product(name: "GRDB", package: "GRDB.swift"),
                "SwiftSoup",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapdAppTests",
            dependencies: [
                "CapdApp",
                "CapdAppUI",
                "CapdHandoff",
                "CapdKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "CapdCLITests",
            dependencies: [
                "CapdCLI",
                "CapdKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapdAgentTests",
            dependencies: [
                "CapdAgent",
                "CapdKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
