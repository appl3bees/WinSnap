// swift-tools-version:5.9
// Used for `swift build` and `swift test`; build.sh still produces the signed WinSnap.app.
import PackageDescription

let package = Package(
    name: "WinSnap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WinSnap", path: "Sources/WinSnap"),
        .testTarget(name: "WinSnapTests", dependencies: ["WinSnap"], path: "Tests/WinSnapTests"),
    ]
)
