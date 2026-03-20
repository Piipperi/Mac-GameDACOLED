// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GameDACOLED",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GameDACOLED",
            targets: ["GameDACOLED"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GameDACOLED",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AppIntents"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
    ]
)
