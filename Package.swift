// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RelayConsole",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "RelayConsole", targets: ["RelayConsole"])
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
        .testTarget(
            name: "RelayConsoleTests",
            dependencies: ["RelayConsole"],
            path: "Tests/RelayConsoleTests"
        )
    ]
)

