// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "FloatingSpreadsheetKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "FloatingSpreadsheetKit",
      targets: ["FloatingSpreadsheetKit"]
    ),
  ],
  targets: [
    .target(name: "FloatingSpreadsheetKit"),
    .testTarget(
      name: "FloatingSpreadsheetKitTests",
      dependencies: ["FloatingSpreadsheetKit"]
    ),
  ]
)
