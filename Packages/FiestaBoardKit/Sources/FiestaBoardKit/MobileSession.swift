import Foundation

/// The only credential accepted by the native phone transport. Browser cookies,
/// TV credentials and account passwords cannot be restored into this envelope.
public struct MobileTokenReply: Codable, Sendable, Equatable {
    public let access_token: String
    public let token_type: String
    public let expires_in: Int
    public let session_id: String
    public let scope: String

    var isValid: Bool {
        MobileCredentialValidation.token(access_token) && MobileCredentialValidation.session(session_id) &&
        token_type == "Bearer" && scope == "control" && expires_in > 0 && expires_in <= 31_536_000
    }

}

private enum MobileCredentialValidation {
    static func token(_ value: String) -> Bool {
        value.hasPrefix("fb_mob_") && (8...8192).contains(value.utf8.count) &&
        value.utf8.allSatisfy { (33...126).contains($0) && $0 != 44 && $0 != 59 }
    }
    static func session(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

struct MobileSession: Codable, Sendable {
    let accessToken: String
    let sessionID: String
    let expiresAt: Date
    init(reply: MobileTokenReply, now: Date = Date()) throws {
        guard reply.isValid else { throw FiestaBoardError.invalidResponse }
        accessToken = reply.access_token; sessionID = reply.session_id
        expiresAt = now.addingTimeInterval(TimeInterval(reply.expires_in))
    }
    var authorization: String? { expiresAt > Date() ? "Bearer " + accessToken : nil }

    private struct Stored: Codable {
        let version: Int
        let deployment: String
        let installationID: String
        let session: MobileSession
        let connectionID: UUID
        let principalID: String?
    }
    func persisted(deployment: DeploymentURL, installationID: String, connectionID: UUID, principalID: String? = nil) -> Data? {
        guard authorization != nil else { return nil }
        return try? JSONEncoder().encode(Stored(version: 4, deployment: deployment.description,
            installationID: installationID, session: self, connectionID: connectionID, principalID: principalID))
    }
    static func storedConnectionID(_ data: Data) -> UUID? { (try? JSONDecoder().decode(Stored.self, from: data))?.connectionID }
    static func storedPrincipalID(_ data: Data, deployment: DeploymentURL, installationID: String) -> String? {
        guard restore(data, deployment: deployment, installationID: installationID) != nil,
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.version == 4,
              Data(stored.installationID.utf8) == Data(installationID.utf8),
              let principal = stored.principalID, !principal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              principal.utf8.count <= 256, !principal.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        return principal
    }
    static func restore(_ data: Data, deployment: DeploymentURL, installationID: String) -> Self? {
        guard data.count <= 65_536, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              [3, 4].contains(stored.version), stored.deployment == deployment.description, stored.installationID == installationID,
              stored.session.expiresAt.timeIntervalSinceReferenceDate.isFinite, stored.session.authorization != nil,
              stored.session.expiresAt <= Date().addingTimeInterval(31_536_001),
              MobileCredentialValidation.token(stored.session.accessToken),
              MobileCredentialValidation.session(stored.session.sessionID) else { return nil }
        return stored.session
    }
}

public struct MobileClientMetadata: Sendable {
    public let deviceName: String
    public let appVersion: String
    public init(deviceName: String = "FiestaBoard iOS", appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") {
        self.deviceName = deviceName; self.appVersion = appVersion
    }
}

/// tvOS HubRequestBudget policy port: bounded FIFO, cancellation checked before
/// dispatch, exactly one request per operation (no mutation replay).
public actor HubRequestBudget {
    public let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waitingCount: Int { waiters.count }
    public init(limit: Int = 4) { precondition(limit > 0); self.limit = limit }
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        if inUse < limit { inUse += 1 }
        else { await withCheckedContinuation { waiters.append($0) } }
        defer {
            if waiters.isEmpty { inUse -= 1 }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}

actor HubRequestBudgets {
    static let shared = HubRequestBudgets()
    private var budgets: [DeploymentURL: HubRequestBudget] = [:]
    func budget(for deployment: DeploymentURL) -> HubRequestBudget {
        if let value = budgets[deployment] { return value }
        let value = HubRequestBudget(); budgets[deployment] = value; return value
    }
}
