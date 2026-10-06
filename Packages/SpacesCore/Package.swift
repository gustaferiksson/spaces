// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SpacesCore",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "SpacesCore", targets: ["SpacesCore"])
  ],
  targets: [
    .target(name: "SpacesCore"),
    .testTarget(name: "SpacesCoreTests", dependencies: ["SpacesCore"]),
  ]
)
