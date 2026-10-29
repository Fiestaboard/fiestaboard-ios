import Foundation

/// User-selected server metadata only. Credentials belong to the account vault.
public struct SavedServer: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var deployment: DeploymentURL
    public var alias: String
    public var installationID: String?
    public var preferredBoardID: String?
    public init(id: UUID = UUID(), deployment: DeploymentURL, alias: String,
                installationID: String? = nil, preferredBoardID: String? = nil) {
        self.id = id; self.deployment = deployment; self.alias = alias
        self.installationID = installationID; self.preferredBoardID = preferredBoardID
    }
}

public enum ServerCatalogError: Error, Sendable, Equatable, LocalizedError {
    case corrupt
    case storage
    case identityChanged(existing: SavedServer, proposed: SavedServer)
    public var errorDescription: String? {
        switch self {
        case .corrupt: "The saved server file could not be read. Restore or remove the damaged file before saving servers."
        case .storage: "Saved servers could not be accessed. Check available storage and file access, then try again."
        case .identityChanged: "This address identifies a different FiestaBoard installation. Confirm its identity before associating it again."
        }
    }
}

/// Serializes atomic writes. Browsing never writes to this catalog.
public actor ServerCatalog {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("servers.json") }
    public init(directory: URL) { self.directory = directory }

    public func list() async throws -> [SavedServer] { try read() }

    @discardableResult
    public func upsert(_ record: SavedServer) async throws -> SavedServer {
        var records = try read()
        let addressIndex = records.firstIndex { $0.deployment == record.deployment }
        let idIndex = records.firstIndex { $0.id == record.id }
        // An address already in the catalog retains its stable identity, even when an edit moves another entry to it.
        let index = addressIndex ?? idIndex
        var canonical = record
        if let index {
            let existing = records[index]
            let knownID = existing.installationID.flatMap { $0.isEmpty ? nil : $0 }
            let proposedID = record.installationID.flatMap { $0.isEmpty ? nil : $0 }
            if let knownID, let proposedID, knownID != proposedID {
                throw ServerCatalogError.identityChanged(existing: existing, proposed: record)
            }
            canonical.id = existing.id
            canonical.installationID = proposedID ?? knownID
            records[index] = canonical
            if let idIndex, idIndex != index { records.remove(at: idIndex) }
        } else {
            canonical.installationID = record.installationID.flatMap { $0.isEmpty ? nil : $0 }
            records.append(canonical)
        }
        try write(records)
        return canonical
    }

    public func remove(id: UUID) async throws {
        var records = try read()
        records.removeAll { $0.id == id }
        try write(records)
    }

    private func read() throws -> [SavedServer] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data: Data
        do { data = try Data(contentsOf: file) } catch { throw ServerCatalogError.storage }
        do {
            let records = try JSONDecoder().decode([SavedServer].self, from: data)
            guard Set(records.map(\.id)).count == records.count,
                  Set(records.map(\.deployment)).count == records.count else { throw ServerCatalogError.corrupt }
            return records
        } catch { throw ServerCatalogError.corrupt }
    }

    private func write(_ records: [SavedServer]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: file, options: .atomic)
        } catch { throw ServerCatalogError.storage }
    }
}
