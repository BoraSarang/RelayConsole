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
            dependencies: ["RelayWidgetCore"],
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
                .linkedFramework("UserNotifications"),
                .linkedFramework("WidgetKit")
            ]
        ),
        .target(
            name: "RelayMcpCore",
            path: "Sources/RelayMcpCore"
        ),
        // 위젯 공유 — 모델·App Group 저장소만 (앱·위젯 양쪽에서 각각 컴파일 · PLAN_widget)
        .target(
            name: "RelayWidgetCore",
            path: "Sources/RelayWidgetCore"
        ),
        .executableTarget(
            name: "RelayMcp",
            dependencies: ["RelayMcpCore"],
            path: "Sources/RelayMcp"
        ),
        .testTarget(
            name: "RelayConsoleTests",
            dependencies: ["RelayConsole", "RelayMcpCore", "RelayWidgetCore"],
            path: "Tests/RelayConsoleTests"
        )
    ]
)

