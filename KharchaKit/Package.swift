// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KharchaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KharchaKit", targets: ["KharchaKit"])
    ],
    targets: [
        .target(name: "KharchaKit"),
        .testTarget(name: "KharchaKitTests", dependencies: ["KharchaKit"])
    ]
)
