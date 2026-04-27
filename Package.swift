// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hopet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Hopet", targets: ["Hopet"]),
        .executable(name: "hopet-emit", targets: ["hopet-emit"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Hopet",
            path: "Sources/Hopet",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("Network"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "hopet-emit",
            path: "Sources/hopet-emit"
        )
    ]
)
