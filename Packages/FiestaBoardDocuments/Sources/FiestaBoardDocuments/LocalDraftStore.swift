import Foundation
import CryptoKit

/// Use the deployment's immutable canonical identity, never its display name or a credential.
/// Both components participate in the SHA-256 filename through unambiguous JSON framing.
public struct DraftIdentity: Codable, Hashable, Sendable {
    public let deploymentID: String
    public let pageID: String
    public init(deploymentID: String, pageID: String) {
        self.deploymentID = deploymentID
        self.pageID = pageID
    }
}

public struct DraftSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identity: DraftIdentity
    public let revision: UInt64
    public let baselineData: Data
    public let documentData: Data
    public let savedAt: Date

    public init(identity: DraftIdentity, revision: UInt64, baselineData: Data, documentData: Data, savedAt: Date = Date()) {
        schemaVersion = 1
        self.identity = identity
        self.revision = revision
        self.baselineData = baselineData
        self.documentData = documentData
        self.savedAt = savedAt
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw DraftError.unsupportedVersion(schemaVersion) }
        _ = try PageDocument(data: baselineData)
        _ = try PageDocument(data: documentData)
    }
}

public struct DraftCorruption: Equatable, Sendable {
    public let fileURL: URL
    public let reason: String
}

public enum DraftLoadResult: Equatable, Sendable {
    case absent
    case recovered(DraftSnapshot)
    /// The original file is left untouched for explicit recovery/quarantine.
    case corrupt(DraftCorruption)
}

public enum DraftError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int)
    case identityMismatch
    case corruptExistingDraft
    case notCorrupt
    case revisionExhausted
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Local draft version \(version) is unsupported."
        case .identityMismatch: "The local draft belongs to a different deployment or page."
        case .corruptExistingDraft: "A damaged draft exists. Preserve it before saving a new draft."
        case .notCorrupt: "There is no damaged draft to preserve."
        case .revisionExhausted: "The local revision limit has been reached."
        }
    }
}

/// One actor should be shared by all editors for a deployment. Files use atomic replacement.
/// Local revisions are local bookkeeping only; this makes no server concurrency claims.
public actor LocalDraftStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FiestaBoard/LocalDrafts", isDirectory: true)
    }

    public func fileURL(for identity: DraftIdentity) -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding this fixed string-only value cannot fail.
        let framed = try! encoder.encode(identity)
        let hash = SHA256.hash(data: framed).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json", isDirectory: false)
    }

    public func load(_ identity: DraftIdentity) throws -> DraftLoadResult {
        let url = fileURL(for: identity)
        let bytes: Data
        do { bytes = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .absent
        }
        // I/O failures (permissions, volume unavailable) propagate, distinct from corrupt content.
        do {
            let snapshot = try JSONDecoder().decode(DraftSnapshot.self, from: bytes)
            guard snapshot.identity == identity else { throw DraftError.identityMismatch }
            try snapshot.validate()
            return .recovered(snapshot)
        } catch {
            return .corrupt(DraftCorruption(fileURL: url, reason: error.localizedDescription))
        }
    }

    public func save(_ snapshot: DraftSnapshot) throws {
        try snapshot.validate()
        if case .corrupt = try load(snapshot.identity) { throw DraftError.corruptExistingDraft }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        try bytes.write(to: fileURL(for: snapshot.identity), options: .atomic)
    }

    /// Explicit user action preserves damaged bytes under a unique filename before new writes.
    @discardableResult
    public func quarantineCorruptDraft(_ identity: DraftIdentity) throws -> URL {
        guard case .corrupt = try load(identity) else { throw DraftError.notCorrupt }
        let url = fileURL(for: identity)
        let preserved = directory.appendingPathComponent(url.lastPathComponent + ".corrupt-" + UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: preserved)
        return preserved
    }
}
