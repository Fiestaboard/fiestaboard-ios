// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FiestaBoardEditorState",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "FiestaBoardEditorState", targets: ["FiestaBoardEditorState"])],
    dependencies: [.package(path: "../FiestaBoardDocuments"), .package(path: "../FiestaBoardKit")],
    targets: [
        .target(name: "FiestaBoardEditorState", dependencies: ["FiestaBoardDocuments", "FiestaBoardKit"]),
        .testTarget(name: "FiestaBoardEditorStateTests", dependencies: ["FiestaBoardEditorState"])
    ]
)
