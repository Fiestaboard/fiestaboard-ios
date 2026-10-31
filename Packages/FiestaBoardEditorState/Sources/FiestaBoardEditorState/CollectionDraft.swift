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

/// Immutable, nonsecret ownership copied from one verified connection result.
public struct CollectionDraftIdentity: Codable, Hashable, Sendable {
    public let deploymentID: String
    public let installationID: String
    public let connectionID: UUID
    public let collectionID: String?
    public init(scope: VerifiedConnectionScope, collectionID: String?) {
        self.init(deploymentID: scope.deployment.description, installationID: scope.installationID, connectionID: scope.connectionID, collectionID: collectionID)
    }
    public init(deploymentID: String, installationID: String, connectionID: UUID, collectionID: String?) {
        self.deploymentID = deploymentID; self.installationID = installationID
        self.connectionID = connectionID; self.collectionID = collectionID
    }
    public func assigningCollectionID(_ id: String) -> Self {
        Self(deploymentID: deploymentID, installationID: installationID, connectionID: connectionID, collectionID: id)
    }
    public func validate() throws {
        guard (try? DeploymentURL(deploymentID, allowLocalHTTP: true)) != nil,
              !installationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              collectionID.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else { throw FiestaBoardError.invalidResponse }
    }
    public static func exact(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) { case (nil, nil): true; case (.some(let a), .some(let b)): a.utf8.elementsEqual(b.utf8); default: false }
    }
    public static func == (a: Self, b: Self) -> Bool {
        exact(a.deploymentID, b.deploymentID) && exact(a.installationID, b.installationID) && a.connectionID == b.connectionID && exact(a.collectionID, b.collectionID)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Data(deploymentID.utf8)); hasher.combine(Data(installationID.utf8)); hasher.combine(connectionID)
        hasher.combine(collectionID.map { Data($0.utf8) })
    }
}

public struct CollectionDraftCheckpoint: Codable, Sendable, Identifiable {
    public let id: UUID
    public let formatVersion: Int?
    public let identity: CollectionDraftIdentity?
    public let deploymentID: String
    public let collectionID: String?
    public let baseline: PageCollection?
    public let draft: CollectionDraft
    public let sourceSupportsEditing: Bool
    public let status: CollectionEditorStatus
    public let savedAt: Date
    public let sourceVersions: [CollectionDraftVersion]?
    /// Computed from bytes read, never accepted from serialized metadata.
    public fileprivate(set) var archiveVersion: CollectionDraftVersion? = nil
    enum CodingKeys: String, CodingKey {
        case id, formatVersion, identity, deploymentID, collectionID, baseline, draft, sourceSupportsEditing, status, savedAt, sourceVersions
    }
    /// Legacy/unassigned representation for original-file inspection. Never active recovery.
    public init(id: UUID, deploymentID: String, collectionID: String?, baseline: PageCollection?, draft: CollectionDraft, sourceSupportsEditing: Bool, status: CollectionEditorStatus, sourceVersions: [CollectionDraftVersion] = []) {
        self.id = id; self.deploymentID = deploymentID; self.collectionID = collectionID
        identity = nil; formatVersion = nil
        self.baseline = baseline; self.draft = draft
        self.sourceSupportsEditing = sourceSupportsEditing && (baseline?.supportsEditing ?? true)
        self.status = status; self.sourceVersions = sourceVersions; savedAt = Date()
    }
    public init(id: UUID, identity: CollectionDraftIdentity, baseline: PageCollection?, draft: CollectionDraft, sourceSupportsEditing: Bool, status: CollectionEditorStatus, sourceVersions: [CollectionDraftVersion] = []) {
        self.id = id; self.identity = identity; formatVersion = 2
        deploymentID = identity.deploymentID; collectionID = identity.collectionID
        self.baseline = baseline; self.draft = draft
        self.sourceSupportsEditing = sourceSupportsEditing && (baseline?.supportsEditing ?? true)
        self.status = status; self.sourceVersions = sourceVersions; savedAt = Date()
    }
    fileprivate func belongs(to expected: CollectionDraftIdentity) -> Bool {
        formatVersion == 2 && identity == expected && (try? expected.validate()) != nil &&
            CollectionDraftIdentity.exact(deploymentID, expected.deploymentID) &&
            CollectionDraftIdentity.exact(collectionID, expected.collectionID) &&
            CollectionDraftIdentity.exact(baseline?.id, expected.collectionID)
    }
}

/// Independent per-editor files; retirement never deletes original archive bytes.
@MainActor public final class CollectionDraftArchive {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FiestaBoard/CollectionDrafts", isDirectory: true)
    }
    @discardableResult public func save(_ checkpoint: CollectionDraftCheckpoint) throws -> CollectionDraftVersion {
        let url = file(checkpoint.id)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let identity = checkpoint.identity, let prior = read(url), prior.belongs(to: identity) else { throw FiestaBoardError.invalidResponse }
        }
        if let identity = checkpoint.identity { guard checkpoint.belongs(to: identity) else { throw FiestaBoardError.invalidResponse } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: url, options: .atomic)
        return version(checkpoint.id, data)
    }
    public func load(identity: CollectionDraftIdentity) throws -> [CollectionDraftCheckpoint] {
        try identity.validate()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let value = read(url), value.belongs(to: identity), let version = value.archiveVersion, !isRetired(version) else { return nil }
                return value
            }.sorted { $0.savedAt > $1.savedAt }
    }
    /// Every serialized lineage entry is checked against current exact bytes and ownership.
    public func eligibleVersions(_ versions: [CollectionDraftVersion], identity: CollectionDraftIdentity) -> [CollectionDraftVersion] {
        Array(Set(versions)).filter { version in
            guard markerFile(version) != nil, let value = read(file(version.id)) else { return false }
            return value.belongs(to: identity) && value.archiveVersion == version
        }
    }
    public func retire(_ versions: [CollectionDraftVersion], identity: CollectionDraftIdentity) throws {
        let eligible = eligibleVersions(versions, identity: identity)
        guard !eligible.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("retired", isDirectory: true), withIntermediateDirectories: true)
        for version in eligible {
            // Recheck before each marker; never trust historical lineage metadata alone.
            guard eligibleVersions([version], identity: identity) == [version], let url = markerFile(version) else { continue }
            try JSONEncoder().encode(version).write(to: url, options: .atomic)
        }
    }
    private func version(_ id: UUID, _ data: Data) -> CollectionDraftVersion {
        CollectionDraftVersion(id: id, fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
    private func read(_ url: URL) -> CollectionDraftCheckpoint? {
        guard let data = try? Data(contentsOf: url), var value = try? JSONDecoder().decode(CollectionDraftCheckpoint.self, from: data),
              url.lastPathComponent == value.id.uuidString + ".json" else { return nil }
        value.archiveVersion = version(value.id, data)
        return value
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
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
