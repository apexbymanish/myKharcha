// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KharchaKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KharchaKit", targets: ["KharchaKit"])
    ],
    targets: [
        .target(name: "KharchaKit", resources: [.process("Resources")]),
        .testTarget(name: "KharchaKitTests", dependencies: ["KharchaKit"])
    ]
)
