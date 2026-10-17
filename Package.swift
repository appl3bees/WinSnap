// swift-tools-version:5.9
// Used for `swift test`; build.sh still builds the app bundle.
import PackageDescription

let package = Package(
    name: "WinSnap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WinSnap", path: "Sources/WinSnap"),
        .testTarget(name: "WinSnapTests", dependencies: ["WinSnap"], path: "Tests/WinSnapTests"),
    ]
)
