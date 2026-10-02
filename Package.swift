// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "spaces",
  platforms: [.macOS("27.0")],
  targets: [
    .target(name: "SpacesCore"),
    .executableTarget(name: "spaces", dependencies: ["SpacesCore"]),
    .testTarget(name: "SpacesCoreTests", dependencies: ["SpacesCore"]),
  ]
)
