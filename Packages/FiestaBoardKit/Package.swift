// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FiestaBoardKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "FiestaBoardKit", targets: ["FiestaBoardKit"])],
    targets: [
        .target(name: "FiestaBoardKit", resources: [.copy("DemoFixtures")]),
        .testTarget(name: "FiestaBoardKitTests", dependencies: ["FiestaBoardKit"], resources: [.copy("Fixtures")])
    ]
)
