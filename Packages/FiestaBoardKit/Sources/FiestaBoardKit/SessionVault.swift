import Foundation
import Security

/// Stores only opaque, versioned session material. Never accepts a password.
public protocol SessionVault: AnyObject, Sendable {
    /// Implementations addressing the same underlying store must share this namespace.
    var coordinationID: String { get }
    func load(for deployment: DeploymentURL) async throws -> Data?
    func save(_ data: Data, for deployment: DeploymentURL) async throws
    func remove(for deployment: DeploymentURL) async throws
}
public extension SessionVault {
    var coordinationID: String { "object:\(ObjectIdentifier(self))" }
}

public enum SessionPersistenceWarning: String, Sendable, Equatable {
    case unavailable, invalidStoredSession, noPersistentCookie, identityRequired, remoteRevocationPending
}
public struct SessionPersistenceState: Sendable, Equatable {
    public var rememberMe: Bool
    public var restored: Bool
    public var warning: SessionPersistenceWarning?
    public var cleanupPending: Bool
    public init(rememberMe: Bool = false, restored: Bool = false, warning: SessionPersistenceWarning? = nil, cleanupPending: Bool = false) {
        self.rememberMe = rememberMe; self.restored = restored; self.warning = warning; self.cleanupPending = cleanupPending
    }
}

/// The injectable call boundary keeps unit tests away from the host's actual Keychain.
struct SessionSecurity: Sendable {
    let copy: @Sendable ([String: Any]) -> (OSStatus, Data?)
    let add: @Sendable ([String: Any]) -> OSStatus
    let update: @Sendable ([String: Any], [String: Any]) -> OSStatus
    let delete: @Sendable ([String: Any]) -> OSStatus
    static let system = Self(copy: { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }, add: { SecItemAdd($0 as CFDictionary, nil) },
       update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
       delete: { SecItemDelete($0 as CFDictionary) })
}

public actor KeychainSessionVault: SessionVault {
    public nonisolated let coordinationID: String
    private let service: String
    private let security: SessionSecurity
    public init(service: String = "com.fiestaboard.native.remembered-session.v1") {
        self.service = service; security = .system; coordinationID = "keychain:" + service
    }
    init(service: String, security: SessionSecurity) {
        self.service = service; self.security = security; coordinationID = "keychain:" + service
    }
    private func query(_ deployment: DeploymentURL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: deployment.description,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    public func load(for deployment: DeploymentURL) throws -> Data? {
        var query = query(deployment)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = security.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw VaultError.unavailable }
        return data
    }
    public func save(_ data: Data, for deployment: DeploymentURL) throws {
        guard data.count <= 65_536 else { throw VaultError.unavailable }
        let query = query(deployment)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = security.update(query, attributes)
        if status == errSecItemNotFound {
            var item = query; item.merge(attributes) { _, new in new }
            guard security.add(item) == errSecSuccess else { throw VaultError.unavailable }
        } else if status != errSecSuccess { throw VaultError.unavailable }
    }
    public func remove(for deployment: DeploymentURL) throws {
        let status = security.delete(query(deployment))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.unavailable }
    }
    private enum VaultError: Error { case unavailable }
}

/// Process-wide owner leases and an I/O queue shared by all windows and vault wrappers.
/// A lease changes before I/O awaits. Every enqueued operation follows the preceding
/// operation to completion, so a suspended old save cannot finish after a newer clear.
actor SessionVaultCoordinator {
    static let shared = SessionVaultCoordinator()
    struct Lease: Sendable, Equatable { let key: String; let owner: UUID }
    private struct Slot {
        let vault: any SessionVault // Retain identity-backed stores to avoid ObjectIdentifier reuse.
        var owner: UUID
        var tail: Task<Void, Never>?
    }
    private var slots: [String: Slot] = [:]
    func claim(_ vault: any SessionVault, for deployment: DeploymentURL, replacing: Bool) -> Lease {
        let key = vault.coordinationID + "\n" + deployment.description
        if slots[key] == nil { slots[key] = Slot(vault: vault, owner: UUID()) }
        if replacing { slots[key]!.owner = UUID() }
        return Lease(key: key, owner: slots[key]!.owner)
    }
    func retire(_ lease: Lease) -> Lease? {
        guard isCurrent(lease) else { return nil }
        let owner = UUID()
        slots[lease.key]!.owner = owner
        return Lease(key: lease.key, owner: owner)
    }
    func isCurrent(_ lease: Lease) -> Bool { slots[lease.key]?.owner == lease.owner }
    func perform(_ lease: Lease, operation: @escaping @Sendable () async throws -> Data?) async throws -> Data? {
        guard isCurrent(lease), var slot = slots[lease.key] else { return nil }
        let previous = slot.tail
        let result = Task { () throws -> Data? in
            await previous?.value
            guard self.isCurrent(lease) else { return nil }
            return try await operation()
        }
        slot.tail = Task { _ = try? await result.value }
        slots[lease.key] = slot
        return try await result.value
    }
}

public extension FiestaBoardService {
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {}
    func restoreRememberedSession(observedInstallationID: String) async throws -> Bool { false }
    func forgetRememberedSession() async {}
    func disconnect() async {}
    func sessionPersistenceState() async -> SessionPersistenceState { .init() }
}
