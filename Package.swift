// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RemoteEmulator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RemoteEmulator",
            path: "Sources/RemoteEmulator"
        ),
        .testTarget(
            name: "RemoteEmulatorTests",
            dependencies: ["RemoteEmulator"],
            path: "Tests/RemoteEmulatorTests"
        ),
    ]
)
