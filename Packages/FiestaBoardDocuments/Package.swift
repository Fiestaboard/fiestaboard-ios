// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FiestaBoardDocuments",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FiestaBoardDocuments", targets: ["FiestaBoardDocuments"])],
    targets: [
        .target(name: "FiestaBoardDocuments"),
        .testTarget(name: "FiestaBoardDocumentsTests", dependencies: ["FiestaBoardDocuments"], resources: [.copy("Fixtures")])
    ]
)
