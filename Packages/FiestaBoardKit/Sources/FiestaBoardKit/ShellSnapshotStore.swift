import Foundation

/// Read-only presentation data. Sessions, account fields and credentials are deliberately absent.
public struct ShellSnapshot: Codable, Sendable {
    public struct PageSummary: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public let version: Int
    public let hubID: UUID
    public let deployment: DeploymentURL
    public let installationID: String
    public let capturedAt: Date
    public let board: BoardDetail?
    public let displayName: String
    public let pages: [PageSummary]
    public init(hub: SavedServer, capturedAt: Date, board: BoardDetail?, displayName: String, pages: [PageSummary]) {
        version = 1; hubID = hub.id; deployment = hub.deployment; installationID = hub.installationID ?? ""
        self.capturedAt = capturedAt; self.board = board; self.displayName = displayName; self.pages = pages
    }
}

/// An authenticated model obtains a new lease once per session. Removal invalidates queued old writes.
public struct ShellSnapshotLease: Sendable, Equatable {
    fileprivate let hubID: UUID
    fileprivate let deployment: DeploymentURL
    fileprivate let installationID: String
    fileprivate let token: UUID
}

public actor ShellSnapshotStore {
    private let directory: URL
    private var active: [UUID: UUID] = [:]
    private let maximumBytes = 2_097_152
    public init(directory: URL) { self.directory = directory }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    public func beginSession(for hub: SavedServer) throws -> ShellSnapshotLease {
        guard let identity = hub.installationID, !identity.isEmpty else { throw FiestaBoardError.invalidResponse }
        let token = UUID(); active[hub.id] = token
        return ShellSnapshotLease(hubID: hub.id, deployment: hub.deployment, installationID: identity, token: token)
    }
    @discardableResult public func write(_ snapshot: ShellSnapshot, lease: ShellSnapshotLease) throws -> Bool {
        guard active[lease.hubID] == lease.token else { return false }
        guard snapshot.version == 1, snapshot.hubID == lease.hubID, snapshot.deployment == lease.deployment,
              snapshot.installationID == lease.installationID else { throw FiestaBoardError.invalidResponse }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumBytes else { throw FiestaBoardError.invalidResponse }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: file(lease.hubID), options: options)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(lease.hubID).path)
        return true
    }
    public func read(for hub: SavedServer, at now: Date) throws -> ShellSnapshot? {
        guard let identity = hub.installationID, !identity.isEmpty,
              FileManager.default.fileExists(atPath: file(hub.id).path) else { return nil }
        let handle = try FileHandle(forReadingFrom: file(hub.id))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes, let snapshot = try? JSONDecoder().decode(ShellSnapshot.self, from: data),
              snapshot.version == 1, snapshot.hubID == hub.id, snapshot.deployment == hub.deployment,
              snapshot.installationID == identity, now >= snapshot.capturedAt,
              now.timeIntervalSince(snapshot.capturedAt) < 600 else { return nil }
        return snapshot
    }
    public func revoke(_ lease: ShellSnapshotLease) throws {
        guard active[lease.hubID] == lease.token else { return }
        active[lease.hubID] = nil
        if FileManager.default.fileExists(atPath: file(lease.hubID).path) { try FileManager.default.removeItem(at: file(lease.hubID)) }
    }
    public func remove(_ hub: SavedServer) throws {
        active[hub.id] = nil
        if FileManager.default.fileExists(atPath: file(hub.id).path) { try FileManager.default.removeItem(at: file(hub.id)) }
    }
}
