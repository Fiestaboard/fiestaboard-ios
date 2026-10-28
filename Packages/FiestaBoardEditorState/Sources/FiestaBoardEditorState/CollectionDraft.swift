import Foundation
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

public struct CollectionDraftCheckpoint: Codable, Sendable, Identifiable {
    public let id: UUID
    public let deploymentID: String
    public let collectionID: String?
    public let baseline: PageCollection?
    public let draft: CollectionDraft
    public let sourceSupportsEditing: Bool
    public let status: CollectionEditorStatus
    public let savedAt: Date
    public init(id: UUID, deploymentID: String, collectionID: String?, baseline: PageCollection?, draft: CollectionDraft, sourceSupportsEditing: Bool, status: CollectionEditorStatus) {
        self.id = id; self.deploymentID = deploymentID; self.collectionID = collectionID
        self.baseline = baseline; self.draft = draft; self.sourceSupportsEditing = sourceSupportsEditing; self.status = status; savedAt = Date()
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
                guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(CollectionDraftCheckpoint.self, from: data),
                      value.deploymentID == deploymentID, value.collectionID == collectionID else { return nil }
                return value
            }.sorted { $0.savedAt > $1.savedAt }
    }
    public func remove(_ id: UUID) throws {
        let url = file(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
