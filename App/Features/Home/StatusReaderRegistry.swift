import Foundation
import FiestaBoardKit

/// Remembers the live service the connection factory last made for each
/// deployment, so Home's status reads use the same authenticated session the
/// store does (the store keeps its service private). Demo has no reader.
final class StatusReaderRegistry: @unchecked Sendable {
    static let shared = StatusReaderRegistry()
    private let lock = NSLock()
    private var readers: [String: any BoardStatusReading] = [:]

    func register(_ service: any FiestaBoardService) {
        guard let reader = service as? any BoardStatusReading else { return }
        lock.lock(); defer { lock.unlock() }
        readers[service.deployment.description] = reader
    }

    func reader(for label: String) -> (any BoardStatusReading)? {
        lock.lock(); defer { lock.unlock() }
        return readers[label]
    }

    /// The same live service, for page thumbnails (`/pages/preview/batch`).
    func previewReader(for label: String) -> (any PagePreviewReading)? {
        reader(for: label) as? any PagePreviewReading
    }
}
