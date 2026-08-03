// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cap",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CapKit", targets: ["CapKit"]),
        .library(name: "CapAppUI", targets: ["CapAppUI"]),
        .executable(name: "cap", targets: ["CapCLI"]),
        .executable(name: "cap-agent", targets: ["CapAgent"]),
        .executable(name: "CapApp", targets: ["CapApp"]),
        .executable(name: "CapShareExtension", targets: ["CapShareExtension"]),
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
            dependencies: ["CapKit"],
            resources: [.copy("Resources/dev.jxd.cap.agent.plist")]
        ),
        .target(
            name: "CapAppUI",
            dependencies: [
                "CapKit",
                "KeyboardShortcuts",
            ]
        ),
        .target(name: "CapHandoff"),
        .executableTarget(
            name: "CapApp",
            dependencies: [
                "CapKit",
                "CapAppUI",
                "CapHandoff",
                "KeyboardShortcuts",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CapShareExtension",
            dependencies: ["CapHandoff"],
            linkerSettings: [
                // App extensions enter at NSExtensionMain, not main; this is the
                // flag Xcode passes when linking an .appex binary.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .executableTarget(
            name: "CapTestHost",
            dependencies: ["CapKit"],
            path: "Tests/CapTestHost"
        ),
        .testTarget(
            name: "CapKitTests",
            dependencies: [
                "CapKit",
                "CapTestHost",
                .product(name: "GRDB", package: "GRDB.swift"),
                "SwiftSoup",
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapAppTests",
            dependencies: [
                "CapApp",
                "CapAppUI",
                "CapHandoff",
                "CapKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "CapCLITests",
            dependencies: [
                "CapCLI",
                "CapKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CapAgentTests",
            dependencies: [
                "CapAgent",
                "CapKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
