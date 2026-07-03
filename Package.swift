// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Cue3",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Cue3", targets: ["Cue3"])
    ],
    targets: [
        .executableTarget(
            name: "Cue3"
        ),
        .testTarget(
            name: "Cue3Tests",
            dependencies: ["Cue3"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
