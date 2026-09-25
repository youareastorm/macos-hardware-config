// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileTidy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FileTidy",
            path: "Sources/FileTidy"
        )
    ]
)
