// swift-tools-version: 6.0
import PackageDescription

// iOS is the shipping platform. macOS is declared only so FiestaBoardAppState's
// host `swift test` can link this package; the SwiftUI renderer is exercised on
// the iOS simulator (`-only-testing:FiestaBoardRenderTests`).
let package = Package(
    name: "FiestaBoardRender",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "FiestaBoardRender", targets: ["FiestaBoardRender"])],
    targets: [
        .target(name: "FiestaBoardRender", resources: [.copy("Resources")]),
        .testTarget(name: "FiestaBoardRenderTests", dependencies: ["FiestaBoardRender"])
    ]
)
