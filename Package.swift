// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FileSinki",
    platforms: [
        .macOS(.v10_14), .iOS(.v12), .tvOS(.v13),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "FileSinki",
            targets: ["FileSinki"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FileSinki",
            dependencies: [],
            path: "FileSinki")],
    swiftLanguageVersions: [.v5]
)
