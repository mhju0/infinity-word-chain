// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WordChainKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WordChainKit", targets: ["WordChainKit"])],
    targets: [
        .target(name: "WordChainKit"),
        .testTarget(name: "WordChainKitTests", dependencies: ["WordChainKit"])
    ]
)
