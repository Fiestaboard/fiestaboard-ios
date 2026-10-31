import Foundation
import CryptoKit

/// V2 scopes include a verified installation and a random, nonsecret connection UUID.
/// The legacy initializer exists only for reading/exporting unassigned v1 files.
public struct DraftIdentity: Codable, Hashable, Sendable {
    public let deploymentID: String
    public let pageID: String
    public let installationID: String?
    public let connectionID: UUID?
    public var isScoped: Bool { installationID != nil && connectionID != nil }
    public init(deploymentID: String, pageID: String) {
        self.deploymentID = deploymentID; self.pageID = pageID
        installationID = nil; connectionID = nil
    }
    public init(deploymentID: String, installationID: String, connectionID: UUID, pageID: String) {
        self.deploymentID = deploymentID; self.installationID = installationID
        self.connectionID = connectionID; self.pageID = pageID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        LosslessJSON.stringsEqual(lhs.deploymentID, rhs.deploymentID)
            && LosslessJSON.stringsEqual(lhs.pageID, rhs.pageID)
            && lhs.installationID.map(ExactUnicodeString.init) == rhs.installationID.map(ExactUnicodeString.init)
            && lhs.connectionID == rhs.connectionID
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ExactUnicodeString(deploymentID)); hasher.combine(ExactUnicodeString(pageID))
        hasher.combine(installationID.map(ExactUnicodeString.init)); hasher.combine(connectionID)
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
        schemaVersion = identity.isScoped ? 2 : 1
        self.identity = identity
        self.revision = revision
        self.baselineData = baselineData
        self.documentData = documentData
        self.savedAt = savedAt
    }

    public func validate() throws {
        guard schemaVersion == 1 || schemaVersion == 2 else { throw DraftError.unsupportedVersion(schemaVersion) }
        guard (schemaVersion == 2) == identity.isScoped,
              (identity.installationID == nil) == (identity.connectionID == nil) else { throw DraftError.identityMismatch }
        _ = try PageDocument(data: baselineData)
        _ = try PageDocument(data: documentData)
    }
}

public struct DraftCorruption: Equatable, Sendable {
    public let fileURL: URL
    public let reason: String
}

/// An explicit export inventory, including other connections, legacy files, and damaged bytes.
/// No inventory entry is an editing baseline for the active connection.
public struct DraftRecoveryEntry: Identifiable, Sendable {
    public var id: URL { fileURL }
    public let fileURL: URL
    public let snapshot: DraftSnapshot?
    public let corruptionReason: String?
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
        // Sorted JSON frames every component unambiguously and preserves exact Unicode.
        // Absent v2 fields retain the original two-key v1 encoding and filename.
        let framed = try! encoder.encode(identity)
        let hash = SHA256.hash(data: framed).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json", isDirectory: false)
    }

    /// Inventory never renames, adopts, or deletes files. Exporting the original file is local-only recovery.
    public func recoveryInventory() throws -> [DraftRecoveryEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { discoveredURL in
                let url = directory.appendingPathComponent(discoveredURL.lastPathComponent)
                do {
                    let snapshot = try JSONDecoder().decode(DraftSnapshot.self, from: Data(contentsOf: url))
                    try snapshot.validate()
                    guard fileURL(for: snapshot.identity) == url else { throw DraftError.identityMismatch }
                    return DraftRecoveryEntry(fileURL: url, snapshot: snapshot, corruptionReason: nil)
                } catch {
                    return DraftRecoveryEntry(fileURL: url, snapshot: nil, corruptionReason: error.localizedDescription)
                }
            }
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
