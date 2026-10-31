// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SongAmbient",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SongAmbient", targets: ["SongAmbient"]),
        .executable(name: "SongAmbientChecks", targets: ["SongAmbientChecks"])
    ],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "AmbientCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "SongAmbient", dependencies: ["AmbientCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "SongAmbientChecks", dependencies: ["AmbientCore"], path: "Checks")
    ]
)
