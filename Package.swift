// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CaravayAudio",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "caravay-audio", targets: ["CaravayAudio"])
  ],
  targets: [
    .executableTarget(name: "CaravayAudio"),
    .testTarget(name: "CaravayAudioTests", dependencies: ["CaravayAudio"]),
  ],
  swiftLanguageModes: [.v5]
)
