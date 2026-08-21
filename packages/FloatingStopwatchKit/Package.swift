// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "FloatingStopwatchKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "FloatingStopwatchKit",
      targets: ["FloatingStopwatchKit"]
    ),
  ],
  targets: [
    .target(name: "FloatingStopwatchKit"),
  ]
)
