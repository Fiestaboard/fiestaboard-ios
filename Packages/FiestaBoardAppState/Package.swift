// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FiestaBoardAppState", platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "FiestaBoardAppState", targets: ["FiestaBoardAppState"])],
    dependencies: [.package(path: "../FiestaBoardKit")],
    targets: [.target(name: "FiestaBoardAppState", dependencies: ["FiestaBoardKit"]),
              .testTarget(name: "FiestaBoardAppStateTests", dependencies: ["FiestaBoardAppState", "FiestaBoardKit"])])
