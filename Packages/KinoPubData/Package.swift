// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "KinoPubData",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "KinoPubData", targets: ["KinoPubData"])
  ],
  dependencies: [
    .package(name: "KinoPubDomain", path: "../KinoPubDomain"),
    .package(name: "KinoPubBackend", path: "../KinoPubBackend")
  ],
  targets: [
    .target(
      name: "KinoPubData",
      dependencies: ["KinoPubDomain", "KinoPubBackend"]
    ),
    .testTarget(
      name: "KinoPubDataTests",
      dependencies: ["KinoPubData", "KinoPubDomain", "KinoPubBackend"]
    )
  ]
)
