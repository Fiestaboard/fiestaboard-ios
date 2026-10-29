import Foundation
import Combine
import FiestaBoardKit

/// App-owned metadata persistence shared by every scene. Copying this value retains one serialized catalog writer.
/// Constructing it performs no storage, network, or vault access.
public struct ConnectionPersistence: Sendable {
    public let catalog: ServerCatalog
    public init(directory: URL) { catalog = ServerCatalog(directory: directory) }
}

public enum ConnectionPhase: Sendable, Equatable {
    case picker, checking, authentication(BootstrapPhase), connected, demo
}

/// One window's onboarding intent. Secrets never enter the catalog or preferences.
@MainActor public final class ConnectionModel: ObservableObject {
    @Published public private(set) var phase: ConnectionPhase = .picker
    @Published public private(set) var snapshot: BootstrapSnapshot?
    @Published public private(set) var savedServers: [SavedServer] = []
    @Published public private(set) var discoveredServers: [DiscoveredServer] = []
    @Published public private(set) var searching = false
    @Published public private(set) var discoveryMessage: String?
    @Published public private(set) var message: String?
    @Published public private(set) var busy = false
    @Published public private(set) var requiresStateCheck = false
    @Published public private(set) var requiresSetupProof = false
    @Published public private(set) var validationFields: [ValidationField] = []
    @Published public private(set) var persistence = SessionPersistenceState()
    @Published public var address = ""
    @Published public var allowLocalHTTP = false
    @Published public var username = ""
    @Published public var password = ""
    @Published public var setupToken = ""
    @Published public var rememberMe = false
    @Published public var alias = ""
    public private(set) var demoService: DemoFiestaBoardService?
    private let store: BoardStore
    private let catalog: ServerCatalog
    private let discovery: any ServerDiscovering
    private let preferences: UserDefaults
    private let factory: @Sendable (DeploymentURL) -> any FiestaBoardService
    private var service: (any FiestaBoardService)?
    private var selected: SavedServer?
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var handedToStore = false
    private let selectedKey = "FiestaBoard.selectedServerID"

    public init(store: BoardStore, catalog: ServerCatalog, discovery: any ServerDiscovering,
                preferences: UserDefaults, serviceFactory: @escaping @Sendable (DeploymentURL) -> any FiestaBoardService) {
        self.store = store; self.catalog = catalog; self.discovery = discovery
        self.preferences = preferences; factory = serviceFactory
    }
    @discardableResult public func start(demo: Bool = false) -> Task<Void, Never> {
        if demo { return startDemo() }
        return Task { await reloadCatalog() }
    }
    public func findServers() {
        stopDiscovery(); searching = true; discoveryMessage = nil; discoveredServers = []
        let token = generation
        discoveryTask = Task { [weak self, discovery] in
            do {
                for try await results in discovery.snapshots() {
                    guard let self, generation == token, !Task.isCancelled else { return }
                    discoveredServers = results
                }
                guard let self, generation == token, !Task.isCancelled else { return }
                searching = false
                discoveryMessage = discoveredServers.isEmpty ? "No servers found. Check Wi-Fi or enter an address manually." : nil
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                searching = false; discoveryMessage = "Discovery could not finish. Check Wi-Fi and Local Network settings, or enter an address manually."
            }
        }
    }
    public func stopDiscovery() { discoveryTask?.cancel(); discoveryTask = nil; searching = false }
    /// Selecting discovery fills the address; local HTTP still requires the user's explicit choice.
    public func useDiscovered(_ server: DiscoveredServer) { address = server.deployment.description; alias = server.displayName; allowLocalHTTP = false }
    @discardableResult public func connectAddress() -> Task<Void, Never> {
        do {
            let deployment = try ServerAddress.parse(address, allowLocalHTTP: allowLocalHTTP)
            let existing = savedServers.first { $0.deployment == deployment }
            return select(deployment, record: existing)
        } catch { message = safe(error); return Task {} }
    }
    @discardableResult public func selectSaved(_ server: SavedServer) -> Task<Void, Never> {
        address = server.deployment.description
        // Saved HTTP consent was given when this record was explicitly associated.
        allowLocalHTTP = server.deployment.description.hasPrefix("http://")
        alias = server.alias
        return select(server.deployment, record: server)
    }
    private func select(_ deployment: DeploymentURL, record: SavedServer?) -> Task<Void, Never> {
        cancel(); selected = record; phase = .checking; busy = true
        let token = generation, cleanup = cleanupTask
        let next = factory(deployment); service = next
        let task = Task { [weak self] in
            await cleanup?.value
            guard let self, valid(token) else { return }
            await store.waitForSessionCleanup()
            guard valid(token) else { return }
            do {
                let result = try await next.bootstrap()
                guard valid(token) else { return }
                let records = try await catalog.list()
                guard valid(token) else { return }
                let knownRecord = record ?? records.first { $0.deployment == deployment }
                selected = knownRecord
                if let knownRecord, let known = knownRecord.installationID, known != result.identity.installationID {
                    throw ServerCatalogError.identityChanged(existing: knownRecord, proposed: SavedServer(deployment: deployment, alias: alias, installationID: result.identity.installationID))
                }
                snapshot = result
                let restored = try await next.restoreRememberedSession(observedInstallationID: result.identity.installationID)
                guard valid(token) else { return }
                persistence = await next.sessionPersistenceState()
                guard valid(token) else { return }
                if restored {
                    let fresh = try await next.bootstrap()
                    guard valid(token) else { return }
                    guard fresh.identity.installationID == result.identity.installationID else { throw FiestaBoardError.staleSession }
                    snapshot = fresh
                }
                try await associate(next, token: token)
                guard valid(token) else { return }
                await route(next, token: token)
            } catch {
                guard valid(token) else { return }
                phase = .picker; snapshot = nil; message = safe(error)
            }
            if valid(token) { busy = false }
        }
        operation = task; return task
    }
    @discardableResult public func checkServerState() -> Task<Void, Never> {
        guard let service, !busy else { return Task {} }
        return run { [weak self] token in
            guard let self else { return }
            let result = try await service.bootstrap()
            guard valid(token) else { return }
            if let known = selected?.installationID, known != result.identity.installationID {
                cancel()
                message = "This address identifies a different FiestaBoard installation. Remove the saved server and forget its sign-in before adding it again."
                return
            }
            snapshot = result; requiresStateCheck = false
            await route(service, token: token)
        }
    }
    @discardableResult public func signIn() -> Task<Void, Never> {
        let secret = password; password = ""; setupToken = ""
        guard let service, !busy, !requiresStateCheck, !username.isEmpty, !secret.isEmpty else { return Task {} }
        let user = username, remember = rememberMe
        return authenticate { try await service.login(username: user, password: secret, rememberMe: remember) }
    }
    @discardableResult public func setAuthentication(enabled: Bool) -> Task<Void, Never> {
        let proof = setupToken; setupToken = ""; password = ""
        guard let service, !busy, !requiresStateCheck else { return Task {} }
        return authenticate { try await service.setAuthenticationPreference(enabled: enabled, setupToken: proof.isEmpty ? nil : proof) }
    }
    @discardableResult public func setupAdministrator() -> Task<Void, Never> {
        let secret = password, proof = setupToken; password = ""; setupToken = ""
        guard let service, !busy, !requiresStateCheck, !username.isEmpty, !secret.isEmpty else { return Task {} }
        let user = username, remember = rememberMe, identity = snapshot?.identity.installationID
        return authenticate {
            await service.configureSessionPersistence(rememberMe: remember, installationID: identity)
            try Task.checkCancellation()
            return try await service.setupAdministrator(username: user, password: secret, setupToken: proof.isEmpty ? nil : proof)
        }
    }
    private func authenticate(_ action: @escaping @Sendable () async throws -> AuthStatus) -> Task<Void, Never> {
        guard let service else { return Task {} }
        return run { [weak self] token in
            guard let self else { return }
            let auth = try await action()
            guard valid(token), let old = snapshot else { return }
            snapshot = BootstrapSnapshot(deployment: old.deployment, health: old.health, identity: old.identity, auth: auth)
            persistence = await service.sessionPersistenceState()
            guard valid(token) else { return }
            await route(service, token: token)
        }
    }
    private func run(_ action: @escaping @MainActor (UUID) async throws -> Void) -> Task<Void, Never> {
        busy = true; message = nil; validationFields = []
        let token = generation
        let task = Task { [weak self] in
            do {
                await self?.store.waitForSessionCleanup()
                guard let self, valid(token) else { return }
                try await action(token)
            }
            catch {
                guard let self, valid(token) else { return }
                message = safe(error)
                if (error as? FiestaBoardError) == .setupProofRequired { requiresSetupProof = true }
                if let known = error as? FiestaBoardError {
                    if case .validation(let fields) = known { validationFields = fields }
                    switch known {
                    case .unknownMutationOutcome, .networkUnavailable, .conflict, .onboardingConflict, .staleSession: requiresStateCheck = true
                    default: break
                    }
                } else { requiresStateCheck = true }
            }
            guard let self, valid(token) else { return }; busy = false
        }
        operation = task; return task
    }
    private func route(_ next: any FiestaBoardService, token: UUID) async {
        guard valid(token), let snapshot else { return }
        if snapshot.phase != .ready { phase = .authentication(snapshot.phase); return }
        if handedToStore && store.hasRetainedService {
            // A required shell read may fail after authentication succeeded. Retry that retained actor without retiring its cookie.
            await store.reconnect(allowCandidateWrites: false, preferredBoardID: selected?.preferredBoardID).value
        } else {
            handedToStore = true
            await store.connect(next, preferredBoardID: selected?.preferredBoardID).value
        }
        guard valid(token) else { return }
        if store.status != nil { phase = .connected }
        else { message = store.message; phase = .authentication(.signIn) }
    }
    private func associate(_ next: any FiestaBoardService, token: UUID) async throws {
        guard let snapshot, valid(token) else { return }
        var record = selected ?? SavedServer(deployment: next.deployment, alias: alias.isEmpty ? snapshot.identity.name : alias)
        record.installationID = snapshot.identity.installationID
        let saved = try await catalog.upsert(record)
        guard valid(token) else { return }
        selected = saved; preferences.set(saved.id.uuidString, forKey: selectedKey)
        await reloadCatalog()
    }
    @discardableResult public func startDemo() -> Task<Void, Never> {
        cancel()
        do {
            let demo = try DemoFiestaBoardService(); demoService = demo; phase = .demo
            return store.connect(demo)
        } catch { message = "Demo could not start."; return Task {} }
    }
    public func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil; stopDiscovery()
        let old = service, ownedByStore = handedToStore, previous = cleanupTask
        store.disconnect()
        if let old, !ownedByStore { cleanupTask = Task { await previous?.value; await old.disconnect() } }
        service = nil; handedToStore = false; demoService = nil; snapshot = nil
        busy = false; phase = .picker; password = ""; setupToken = ""; rememberMe = false
        requiresStateCheck = false; requiresSetupProof = false; validationFields = []; persistence = .init(); message = nil
    }
    public func disconnect() { cancel() }
    public func storeConnectionChanged() {
        guard phase == .connected, !store.connecting, store.status == nil else { return }
        phase = .authentication(.signIn); message = store.message
    }
    @discardableResult public func logout() -> Task<Void, Never> {
        generation = UUID(); operation?.cancel(); operation = nil; stopDiscovery()
        service = nil; handedToStore = false; snapshot = nil; phase = .picker
        busy = false; password = ""; setupToken = ""; rememberMe = false; persistence = .init()
        return store.logout()
    }
    public func forgetSignIn() async {
        guard let service else { return }
        let token = generation
        await service.forgetRememberedSession()
        let state = await service.sessionPersistenceState()
        guard valid(token) else { return }; persistence = state
    }
    public func removeServer(_ server: SavedServer) async {
        // Prefer this window's captured lease. For an unselected server, confirmation starts a new forget intent.
        let next: any FiestaBoardService
        if let service, service.deployment == server.deployment { next = service }
        else { next = factory(server.deployment) }
        await next.forgetRememberedSession()
        let state = await next.sessionPersistenceState()
        guard !state.cleanupPending else { message = "Saved sign-in could not be removed. Try again before removing this server."; return }
        do {
            try await catalog.remove(id: server.id)
            if preferences.string(forKey: selectedKey) == server.id.uuidString { preferences.removeObject(forKey: selectedKey) }
            await reloadCatalog()
        } catch { message = safe(error) }
    }
    public func renameServer(_ server: SavedServer, alias: String) async {
        var record = server; record.alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try await catalog.upsert(record); await reloadCatalog() } catch { message = safe(error) }
    }
    public func persistPreferredBoard(_ id: String) async {
        guard phase == .connected, !busy, id == store.selectedBoardID, var record = selected, store.boards.contains(where: { $0.id == id }) else { return }
        record.preferredBoardID = id
        let token = generation
        do {
            let saved = try await catalog.upsert(record)
            guard valid(token) else { return }; selected = saved; await reloadCatalog()
        } catch { if valid(token) { message = safe(error) } }
    }
    private func reloadCatalog() async {
        do {
            let records = try await catalog.list(), last = preferences.string(forKey: selectedKey)
            savedServers = records.sorted { ($0.id.uuidString == last ? 0 : 1, $0.alias) < ($1.id.uuidString == last ? 0 : 1, $1.alias) }
        } catch { message = safe(error) }
    }
    private func valid(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }
    private func safe(_ error: any Error) -> String {
        if let known = error as? FiestaBoardError {
            if case .rateLimited(let seconds) = known, let seconds { return "Too many attempts. Wait \(seconds) seconds before trying again." }
            if case .validation(let fields) = known, !fields.isEmpty { return "Check these fields: " + fields.map(\.rawValue).joined(separator: ", ") + "." }
            return known.localizedDescription
        }
        if let known = error as? ServerCatalogError { return known.localizedDescription }
        return "The server could not complete this request. Check its address and connection, then check server state before trying again."
    }
}
