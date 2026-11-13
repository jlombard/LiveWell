// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LiveWellCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LiveWellCore", targets: ["LiveWellCore"])],
    targets: [
        .target(name: "LiveWellCore"),
        .testTarget(name: "LiveWellCoreTests", dependencies: ["LiveWellCore"]),
    ]
)
