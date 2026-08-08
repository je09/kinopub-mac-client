// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "KinoPubDomain",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "KinoPubDomain", targets: ["KinoPubDomain"])
  ],
  targets: [
    .target(name: "KinoPubDomain"),
    .testTarget(name: "KinoPubDomainTests", dependencies: ["KinoPubDomain"])
  ]
)
