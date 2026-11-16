// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardSounds",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeyboardSoundsCore"),
        .executableTarget(name: "KeyboardSounds", dependencies: ["KeyboardSoundsCore"]),
        .testTarget(name: "KeyboardSoundsCoreTests", dependencies: ["KeyboardSoundsCore"]),
    ],
    swiftLanguageModes: [.v5]
)
