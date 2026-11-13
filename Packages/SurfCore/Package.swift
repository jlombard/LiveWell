// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurfCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SurfCore", targets: ["SurfCore"])],
    targets: [
        .target(name: "SurfCore"),
        .testTarget(name: "SurfCoreTests", dependencies: ["SurfCore"]),
    ]
)
