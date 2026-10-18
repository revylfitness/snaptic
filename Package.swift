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

#if os(macOS)
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
        dependencies: ["SnapticKit", "SnapticShims"],
        path: "Sources/Snaptic",
        // Awake (0.3): audio state (AudioMonitor, BluetoothPresence), network state (NetworkMonitor) and volume
        // facts for Drive Alive (VolumeMonitor). All public frameworks.
        linkerSettings: [
            .linkedFramework("CoreAudio"),
            .linkedFramework("SystemConfiguration"),
            .linkedFramework("DiskArbitration"),
        ]
    ),
]
#endif

let package = Package(
    name: "Snaptic",
    platforms: [.macOS(.v14)],
    targets: targets
)
