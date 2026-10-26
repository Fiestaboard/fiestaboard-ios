import Foundation
// The Xcode framework compiles the same sources as SwiftPM. SwiftPM generates its own Bundle.module.
private final class ResourceAnchor: NSObject {}
extension Bundle {
    static var module: Bundle { Bundle(for: ResourceAnchor.self) }
}
