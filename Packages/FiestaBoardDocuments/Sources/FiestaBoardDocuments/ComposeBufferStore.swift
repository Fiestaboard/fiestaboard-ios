import Foundation
import CryptoKit

/// Unsent text belongs to a verified hub installation and principal, never a fake Page.
/// Session UUIDs rotate on unremembered sign-in; they do not rename the user's buffer.
public struct ComposeBufferIdentity: Codable, Hashable, Sendable {
    public let deploymentID: String
    public let installationID: String
    public let principalID: String
    public init(deploymentID: String, installationID: String, principalID: String) {
        self.deploymentID = deploymentID; self.installationID = installationID; self.principalID = principalID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        Data(lhs.deploymentID.utf8) == Data(rhs.deploymentID.utf8)
            && Data(lhs.installationID.utf8) == Data(rhs.installationID.utf8)
            && Data(lhs.principalID.utf8) == Data(rhs.principalID.utf8)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Data(deploymentID.utf8)); hasher.combine(Data(installationID.utf8)); hasher.combine(Data(principalID.utf8))
    }
    fileprivate func validate() throws {
        guard [deploymentID, installationID, principalID].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains("\0") }) else {
            throw ComposeBufferError.invalidContent
        }
    }
}
public enum ComposeBufferDuration: Codable, Equatable, Sendable {
    case minutes(Int), until(Date), untilCancel
}
public struct ComposeBufferSelection: Codable, Equatable, Sendable {
    public let lowerUTF16: Int
    public let upperUTF16: Int
    public init(lowerUTF16: Int, upperUTF16: Int) { self.lowerUTF16 = lowerUTF16; self.upperUTF16 = upperUTF16 }
}
public struct ComposeBufferLine: Codable, Equatable, Sendable {
    public var alignment: String
    public var wrap: Bool
    public init(alignment: String = "left", wrap: Bool = false) { self.alignment = alignment; self.wrap = wrap }
}
/// Exact last-known server evidence. Its consumer must decode it before display and
/// label it stale after input changes; no variable values or formula results are invented.
public struct ComposeBufferPreview: Codable, Equatable, Sendable {
    public let targetID: String
    public let inputDigest: String
    public let responseData: Data
    public let capturedAt: Date
    public init(targetID: String, inputDigest: String, responseData: Data, capturedAt: Date = Date()) {
        self.targetID = targetID; self.inputDigest = inputDigest; self.responseData = responseData; self.capturedAt = capturedAt
    }
}
public struct ComposeBufferSnapshot: Codable, Equatable, Sendable {
    public let identity: ComposeBufferIdentity
    public let revision: UInt64
    public let text: String
    public let targetID: String?
    public let selection: ComposeBufferSelection
    public let lineMetadata: [ComposeBufferLine]
    public let duration: ComposeBufferDuration
    public let preview: ComposeBufferPreview?
    public init(identity: ComposeBufferIdentity, revision: UInt64, text: String, targetID: String? = nil,
                selection: ComposeBufferSelection = .init(lowerUTF16: 0, upperUTF16: 0),
                lineMetadata: [ComposeBufferLine] = [], duration: ComposeBufferDuration = .minutes(60),
                preview: ComposeBufferPreview? = nil) {
        self.identity = identity; self.revision = revision; self.text = text; self.targetID = targetID
        self.selection = selection; self.lineMetadata = lineMetadata; self.duration = duration; self.preview = preview
    }
    fileprivate func validate() throws {
        try identity.validate()
        guard revision > 0, text.utf8.count <= 65536, selection.lowerUTF16 >= 0,
              selection.upperUTF16 >= selection.lowerUTF16, selection.upperUTF16 <= text.utf16.count,
              targetID.map({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains("\0") }) ?? true,
              lineMetadata.isEmpty || lineMetadata.count == text.components(separatedBy: "\n").count,
              lineMetadata.allSatisfy({ ["left", "center", "right"].contains($0.alignment) }) else {
            throw ComposeBufferError.invalidContent
        }
        switch duration {
        case .minutes(let value): guard (1...480).contains(value) else { throw ComposeBufferError.invalidContent }
        case .until(let end): guard end.timeIntervalSince1970.isFinite else { throw ComposeBufferError.invalidContent }
        case .untilCancel: break
        }
        if let preview {
            guard preview.responseData.count <= 3 * 1024 * 1024, preview.inputDigest.utf8.count <= 256,
                  preview.capturedAt.timeIntervalSince1970.isFinite else { throw ComposeBufferError.invalidContent }
        }
    }
}
public struct ComposeBufferLease: Sendable {
    public let identity: ComposeBufferIdentity
    fileprivate let epoch: UUID
}
public enum ComposeBufferError: Error, Equatable, Sendable {
    case unsupportedVersion, identityMismatch, corrupt, invalidContent
}

/// Shared by Compose surfaces on the device. Atomic file epochs also reject a stale
/// writer from another store instance; tombstones stop removed drafts being resurrected.
public actor ComposeBufferStore {
    public let directory: URL
    private static let maximumBytes = 6 * 1024 * 1024
    // Actor instances share this tiny filesystem transaction. A second scene
    // cannot race the epoch/revision check with another instance's replacement.
    private static let filesystemLock = NSRecursiveLock()
    private struct Envelope: Codable {
        var schemaVersion = 1
        let identity: ComposeBufferIdentity
        let epoch: UUID
        let snapshot: ComposeBufferSnapshot?
    }
    public init(directory: URL) { self.directory = directory }
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FiestaBoard/Compose", isDirectory: true)
    }
    public func fileURL(for identity: ComposeBufferIdentity) -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try! encoder.encode(identity)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
    public func open(_ identity: ComposeBufferIdentity) throws -> ComposeBufferLease {
        return try Self.filesystemLock.withLock {
            try identity.validate()
            let previous = try read(identity)
            let epoch = UUID()
            try write(Envelope(identity: identity, epoch: epoch, snapshot: previous?.snapshot))
            return ComposeBufferLease(identity: identity, epoch: epoch)
        }
    }
    public func load(_ identity: ComposeBufferIdentity) throws -> ComposeBufferSnapshot? {
        return try Self.filesystemLock.withLock {
            try identity.validate()
            return try read(identity)?.snapshot
        }
    }
    @discardableResult public func save(_ snapshot: ComposeBufferSnapshot, using lease: ComposeBufferLease) throws -> Bool {
        return try Self.filesystemLock.withLock {
            try snapshot.validate()
            guard snapshot.identity == lease.identity else { throw ComposeBufferError.identityMismatch }
            guard let current = try read(lease.identity), current.epoch == lease.epoch else { return false }
            guard snapshot.revision > (current.snapshot?.revision ?? 0) else { return false }
            try write(Envelope(identity: snapshot.identity, epoch: lease.epoch, snapshot: snapshot))
            return true
        }
    }
    @discardableResult public func remove(using lease: ComposeBufferLease, matchingRevision: UInt64? = nil) throws -> Bool {
        return try Self.filesystemLock.withLock {
            guard let current = try read(lease.identity), current.epoch == lease.epoch else { return false }
            if let matchingRevision, current.snapshot?.revision != matchingRevision { return false }
            try write(Envelope(identity: lease.identity, epoch: UUID(), snapshot: nil))
            return true
        }
    }
    private func read(_ identity: ComposeBufferIdentity) throws -> Envelope? {
        let url = fileURL(for: identity)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.maximumBytes else { throw ComposeBufferError.corrupt }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= Self.maximumBytes else { throw ComposeBufferError.corrupt }
        let value: Envelope
        do { value = try JSONDecoder().decode(Envelope.self, from: bytes) }
        catch { throw ComposeBufferError.corrupt }
        guard value.schemaVersion == 1 else { throw ComposeBufferError.unsupportedVersion }
        guard value.identity == identity, value.snapshot.map({ $0.identity == identity }) ?? true else {
            throw ComposeBufferError.identityMismatch
        }
        try value.snapshot?.validate()
        return value
    }
    private func write(_ envelope: Envelope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= Self.maximumBytes else { throw ComposeBufferError.invalidContent }
        try bytes.write(to: fileURL(for: envelope.identity), options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: fileURL(for: envelope.identity).path)
        #endif
    }
}
