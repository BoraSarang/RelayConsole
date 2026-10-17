// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RelayConsole",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "RelayConsole", targets: ["RelayConsole"]),
        .executable(name: "relay-mcp", targets: ["RelayMcp"]),
        .library(name: "RelayMcpCore", targets: ["RelayMcpCore"])
    ],
    targets: [
        .executableTarget(
            name: "RelayConsole",
            path: "Sources/RelayConsole",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .target(
            name: "RelayMcpCore",
            path: "Sources/RelayMcpCore"
        ),
        .executableTarget(
            name: "RelayMcp",
            dependencies: ["RelayMcpCore"],
            path: "Sources/RelayMcp"
        ),
        .testTarget(
            name: "RelayConsoleTests",
            dependencies: ["RelayConsole", "RelayMcpCore"],
            path: "Tests/RelayConsoleTests"
        )
    ]
)

