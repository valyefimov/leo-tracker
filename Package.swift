// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LeoTracker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LeoTracker", targets: ["LeoTracker"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "LeoTracker",
            dependencies: ["CSQLite"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "LeoTrackerTests", dependencies: ["LeoTracker"])
    ]
)
