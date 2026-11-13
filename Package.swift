// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "APPICHours",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "APPICHours", targets: ["APPICHours"]),
    ],
    targets: [
        // Database, AAPI rollup, batch import, Excel export. No UI, no dependencies.
        .target(
            name: "TrackerCore",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("compression")]
        ),
        // The SwiftUI app.
        .executableTarget(name: "APPICHours", dependencies: ["TrackerCore"]),
        // `swift run SelfTest` — the Command Line Tools ship without XCTest/Testing.
        .executableTarget(name: "SelfTest", dependencies: ["TrackerCore"]),
    ],
    swiftLanguageModes: [.v5]
)
