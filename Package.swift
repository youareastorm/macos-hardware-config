// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudioSwitch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StudioSwitchCore", targets: ["StudioSwitchCore"]),
        .executable(name: "StudioSwitchApp", targets: ["StudioSwitchApp"])
    ],
    targets: [
        .target(name: "StudioSwitchCore"),
        .executableTarget(name: "StudioSwitchApp", dependencies: ["StudioSwitchCore"]),
        .testTarget(name: "StudioSwitchCoreTests", dependencies: ["StudioSwitchCore"])
    ]
)
