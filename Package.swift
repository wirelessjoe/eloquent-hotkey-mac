// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EloquentHotkey",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "EloquentHotkey",
            targets: ["EloquentHotkey"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "EloquentHotkey",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
