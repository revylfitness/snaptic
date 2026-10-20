// swift-tools-version:5.9
import PackageDescription

// SnapticKit is Foundation-only pure logic. It builds and is tested on Linux
// as well as macOS, so CI can check it in about a minute. The app and the
// Objective-C shims need AppKit and private macOS frameworks, so they only
// exist when the manifest is evaluated on a Mac.
var targets: [Target] = [
    .target(name: "SnapticKit", path: "Sources/SnapticKit"),
    .testTarget(name: "SnapticKitTests", dependencies: ["SnapticKit"], path: "Tests/SnapticKitTests"),
]
var dependencies: [Package.Dependency] = []

#if os(macOS)
// The one third-party dependency (PLAN 0.3.1 E4, E6; lint L19): Sparkle for in-app updates, pinned exactly (SwiftPM
// checks the artifact's checksum; Package.resolved is committed). Linux never fetches it.
dependencies += [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
]
targets += [
    .target(
        name: "SnapticShims",
        path: "Sources/SnapticShims",
        linkerSettings: [
            .linkedFramework("Foundation"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("IOKit"),
            .linkedFramework("ColorSync"),
            .linkedFramework("Security"),
        ]
    ),
    .executableTarget(
        name: "Snaptic",
        dependencies: ["SnapticKit", "SnapticShims", .product(name: "Sparkle", package: "Sparkle")],
        path: "Sources/Snaptic",
        // Sparkle is weak-linked (E4): builds without the framework (ad hoc, from source) launch and never touch it.
        // Swift's own autolink entry would link it strongly, so it is turned off and the framework named once, weak.
        swiftSettings: [
            .unsafeFlags(["-Xfrontend", "-disable-autolink-framework", "-Xfrontend", "Sparkle"]),
        ],
        // Awake (0.3): audio state (AudioMonitor, BluetoothPresence), network state (NetworkMonitor) and volume
        // facts for Drive Alive (VolumeMonitor). All public frameworks.
        linkerSettings: [
            .linkedFramework("CoreAudio"),
            .linkedFramework("SystemConfiguration"),
            .linkedFramework("DiskArbitration"),
            .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Sparkle"]),
        ]
    ),
]
#endif

let package = Package(
    name: "Snaptic",
    platforms: [.macOS(.v14)],
    dependencies: dependencies,
    targets: targets
)
