import Foundation
import CryptoKit
import FiestaBoardKit

/// Text is retained exactly as entered, including temporarily invalid numeric fields.
public struct CollectionDraft: Codable, Equatable, Sendable {
    public var name: String
    public var pageIDs: [String]
    public var selectionMode: String
    public var intervalText: String
    public var randomIntervalText: String
    public var hasVariableConfig: Bool
    public var hasRandomConfig: Bool
    public var rules: [CollectionRule]
    public var defaultPageID: String
    public var pollText: String

    public init(collection: PageCollection?) {
        name = collection?.name ?? ""
        pageIDs = collection?.pageIDs ?? []
        selectionMode = collection?.selectionMode ?? "time"
        intervalText = String(collection?.time.intervalSeconds ?? 30)
        randomIntervalText = String(collection?.random?.intervalSeconds ?? 30)
        hasVariableConfig = collection?.variable != nil
        hasRandomConfig = collection?.random != nil
        rules = collection?.variable?.rules ?? []
        defaultPageID = collection?.variable?.defaultPageID ?? ""
        pollText = String(collection?.variable?.pollSeconds ?? 5)
    }
    /// Swift String equality treats canonical Unicode equivalents as equal. Drafts retain
    /// the exact entered representation, so dirtiness and preservation use UTF-8 equality.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        func sameText(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
        return sameText(lhs.name, rhs.name) &&
            lhs.pageIDs.elementsEqual(rhs.pageIDs, by: sameText) &&
            sameText(lhs.selectionMode, rhs.selectionMode) &&
            sameText(lhs.intervalText, rhs.intervalText) &&
            sameText(lhs.randomIntervalText, rhs.randomIntervalText) &&
            lhs.hasVariableConfig == rhs.hasVariableConfig && lhs.hasRandomConfig == rhs.hasRandomConfig &&
            lhs.rules.elementsEqual(rhs.rules, by: { sameText($0.expression, $1.expression) && sameText($0.pageID, $1.pageID) }) &&
            sameText(lhs.defaultPageID, rhs.defaultPageID) && sameText(lhs.pollText, rhs.pollText)
    }

    public func input() throws -> CollectionInput {
        guard let mode = CollectionSelectionMode(rawValue: selectionMode), let interval = Int(intervalText) else { throw FiestaBoardError.invalidResponse }
        var variable: CollectionVariableConfig?
        var random: CollectionIntervalConfig?
        if hasVariableConfig || mode == .variable {
            guard let poll = Int(pollText) else { throw FiestaBoardError.invalidResponse }
            variable = .init(rules: rules, defaultPageID: defaultPageID, pollSeconds: poll)
        }
        if hasRandomConfig || mode == .random {
            guard let seconds = Int(randomIntervalText) else { throw FiestaBoardError.invalidResponse }
            random = .init(intervalSeconds: seconds)
        }
        let input = CollectionInput(name: name, pageIDs: pageIDs, selectionMode: mode,
            time: .init(intervalSeconds: interval), variable: variable, random: random)
        try input.validate()
        return input
    }
}

public enum CollectionEditorStatus: String, Codable, Sendable {
    case idle, saving, deleting, reading, conflict, unknownOutcome, comparison, missing, ended
}

/// A content-addressed archive version. Retiring it cannot hide a newer write to the same ID.
public struct CollectionDraftVersion: Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let fingerprint: String
    public init(id: UUID, fingerprint: String) { self.id = id; self.fingerprint = fingerprint }
}

public struct CollectionDraftCheckpoint: Codable, Sendable, Identifiable {
    public let id: UUID
    public let deploymentID: String
    public let collectionID: String?
    public let baseline: PageCollection?
    public let draft: CollectionDraft
    public let sourceSupportsEditing: Bool
    public let status: CollectionEditorStatus
    public let savedAt: Date
    /// Optional for archives written before source-version retirement was supported.
    public let sourceVersions: [CollectionDraftVersion]?
    /// Computed from the exact bytes read, never trusted from archive contents.
    public fileprivate(set) var archiveVersion: CollectionDraftVersion? = nil
    enum CodingKeys: String, CodingKey {
        case id, deploymentID, collectionID, baseline, draft, sourceSupportsEditing, status, savedAt, sourceVersions
    }
    public init(id: UUID, deploymentID: String, collectionID: String?, baseline: PageCollection?, draft: CollectionDraft, sourceSupportsEditing: Bool, status: CollectionEditorStatus, sourceVersions: [CollectionDraftVersion] = []) {
        self.id = id; self.deploymentID = deploymentID; self.collectionID = collectionID
        self.baseline = baseline; self.draft = draft; self.sourceSupportsEditing = sourceSupportsEditing; self.status = status; self.sourceVersions = sourceVersions; savedAt = Date()
    }
}

/// Each editor owns a separate file, including after recovery. A late editor cannot
/// erase another window's checkpoint; recovery sources remain separate preserved copies.
/// Deployment identity lives inside the archive and is checked before offering explicit recovery.
@MainActor public final class CollectionDraftArchive {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FiestaBoard/CollectionDrafts", isDirectory: true)
    }
    public func save(_ checkpoint: CollectionDraftCheckpoint) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(checkpoint).write(to: file(checkpoint.id), options: .atomic)
    }
    public func load(deploymentID: String, collectionID: String?) throws -> [CollectionDraftCheckpoint] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                // Damaged bytes remain untouched; no recovery action silently overwrites them.
                guard let data = try? Data(contentsOf: url), var value = try? JSONDecoder().decode(CollectionDraftCheckpoint.self, from: data),
                      value.deploymentID == deploymentID, value.collectionID == collectionID else { return nil }
                let version = CollectionDraftVersion(id: value.id, fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                guard !isRetired(version) else { return nil }
                value.archiveVersion = version
                return value
            }.sorted { $0.savedAt > $1.savedAt }
    }
    /// Independent marker files avoid compare/delete races and shared-index updates.
    /// Source files remain untouched; markers apply only to their exact SHA-256 version.
    public func retire(_ versions: [CollectionDraftVersion]) throws {
        guard !versions.isEmpty else { return }
        let retired = directory.appendingPathComponent("retired", isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        for version in Set(versions) {
            guard let url = markerFile(version) else { throw FiestaBoardError.invalidResponse }
            try JSONEncoder().encode(version).write(to: url, options: .atomic)
        }
    }
    private func isRetired(_ version: CollectionDraftVersion) -> Bool {
        guard let url = markerFile(version), let data = try? Data(contentsOf: url),
              let marker = try? JSONDecoder().decode(CollectionDraftVersion.self, from: data) else { return false }
        return marker == version
    }
    private func markerFile(_ version: CollectionDraftVersion) -> URL? {
        guard version.fingerprint.utf8.count == 64,
              version.fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return directory.appendingPathComponent("retired", isDirectory: true)
            .appendingPathComponent(version.id.uuidString + "-" + version.fingerprint).appendingPathExtension("marker")
    }
    public func remove(_ id: UUID) throws {
        let url = file(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
