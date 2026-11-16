// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mechanify",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MechanifyCore"),
        .executableTarget(name: "Mechanify", dependencies: ["MechanifyCore"]),
        .testTarget(name: "MechanifyCoreTests", dependencies: ["MechanifyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
