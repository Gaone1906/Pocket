// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pocket",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pocket", path: "Sources/Pocket", linkerSettings: [.linkedLibrary("sqlite3")]),
    ]
)
