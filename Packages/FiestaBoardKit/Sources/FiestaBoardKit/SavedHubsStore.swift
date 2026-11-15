import Foundation

public struct SavedHub: Codable, Sendable, Equatable {
    public let deployment: DeploymentURL
    public let name: String
    public let installationID: String
    public init(deployment: DeploymentURL, name: String, installationID: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !installationID.isEmpty, installationID.count <= 256,
              !(name + installationID).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw FiestaBoardError.invalidResponse
        }
        self.deployment = deployment; self.name = name; self.installationID = installationID
    }
}

public struct SavedHubsSnapshot: Codable, Sendable, Equatable {
    public var hubs: [SavedHub]
    public var activeDeployment: DeploymentURL?
    public var activeHub: SavedHub? { hubs.first { $0.deployment == activeDeployment } }
}

/// Nonsecret metadata only. Credentials stay in the per-deployment Keychain
/// vault, with its independent ownership queue. File writes replace atomically.
public actor SavedHubsStore {
    private let file: URL
    public init(file: URL) { self.file = file }
    public func snapshot() throws -> SavedHubsSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return .init(hubs: [], activeDeployment: nil) }
        let data = try Data(contentsOf: file)
        guard data.count <= 262_144 else { throw FiestaBoardError.invalidResponse }
        let value = try JSONDecoder().decode(SavedHubsSnapshot.self, from: data)
        guard value.hubs.count <= 100,
              Set(value.hubs.map(\.deployment)).count == value.hubs.count,
              value.activeDeployment == nil || value.activeHub != nil else { throw FiestaBoardError.invalidResponse }
        // Codable synthesized initializers must not bypass URL or string validation.
        for hub in value.hubs {
            _ = try DeploymentURL(hub.deployment.description, allowLocalHTTP: hub.deployment.allowsLocalHTTP)
            _ = try SavedHub(deployment: hub.deployment, name: hub.name, installationID: hub.installationID)
        }
        return value
    }
    public func save(_ hub: SavedHub, makeActive: Bool = false) throws {
        var value = try snapshot()
        value.hubs.removeAll { $0.deployment == hub.deployment }
        value.hubs.append(hub)
        if makeActive { value.activeDeployment = hub.deployment }
        try write(value)
    }
    public func activate(_ deployment: DeploymentURL) throws {
        var value = try snapshot()
        guard value.hubs.contains(where: { $0.deployment == deployment }) else { throw FiestaBoardError.invalidDeployment }
        value.activeDeployment = deployment
        try write(value)
    }
    public func remove(_ deployment: DeploymentURL) throws {
        var value = try snapshot()
        value.hubs.removeAll { $0.deployment == deployment }
        if value.activeDeployment == deployment { value.activeDeployment = nil }
        try write(value)
    }
    private func write(_ value: SavedHubsSnapshot) throws {
        guard value.hubs.count <= 100 else { throw FiestaBoardError.invalidResponse }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
