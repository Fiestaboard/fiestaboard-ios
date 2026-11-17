import Foundation
import Combine
import FiestaBoardKit

/// App-owned metadata persistence shared by every scene. Copying this value retains one serialized catalog writer.
/// Constructing it performs no storage, network, or vault access.
public struct ConnectionPersistence: Sendable {
    public let catalog: ServerCatalog
    public let snapshots: ShellSnapshotStore
    public init(directory: URL) {
        catalog = ServerCatalog(directory: directory)
        snapshots = ShellSnapshotStore(directory: directory.appendingPathComponent("Snapshots", isDirectory: true))
    }
}

public enum ConnectionPhase: Sendable, Equatable {
    case picker, checking, unreachable, authentication(BootstrapPhase), connected
}

public enum WebSetupReturn: Sendable, Equatable {
    case none, awaitingReturn, checking, incomplete, finished, unconfirmed
}

/// One window's onboarding intent. Secrets never enter the catalog or preferences.
@MainActor public final class ConnectionModel: ObservableObject {
    @Published public private(set) var phase: ConnectionPhase = .picker
    @Published public private(set) var snapshot: BootstrapSnapshot?
    @Published public private(set) var savedServers: [SavedServer] = []
    @Published public private(set) var discoveredServers: [DiscoveredServer] = []
    @Published public private(set) var searching = false
    @Published public private(set) var discoveryMessage: String?
    @Published public private(set) var hubDiscoveryFlow = HubDiscoveryFlow()
    @Published public private(set) var message: String?
    @Published public private(set) var loginRetryDeadline: LoginRetryDeadline?
    @Published public private(set) var signInPasswordRejected = false
    @Published public private(set) var setupWebReturn: WebSetupReturn = .none
    @Published public private(set) var busy = false
    @Published public private(set) var requiresStateCheck = false
    @Published public private(set) var requiresSetupProof = false
    @Published public private(set) var validationFields: [ValidationField] = []
    @Published public private(set) var persistence = SessionPersistenceState()
    @Published public private(set) var snapshotLease: ShellSnapshotLease?
    /// Presentation authority for one identity's local unsent buffer. Offline
    /// proof is deliberately separate from transport authentication/control.
    @Published public private(set) var composePrincipal: ComposePrincipalProof?
    private let snapshots: ShellSnapshotStore?
    private var snapshotConsentEpoch: UInt64 = 0
    @Published public var address = ""
    @Published public var allowLocalHTTP = false
    @Published public var username = ""
    @Published public var password = ""
    @Published public var setupToken = ""
    @Published public var rememberMe = false
    @Published public var alias = ""
    @Published public private(set) var passwordResetFlow: PasswordResetFlow?
    @Published public var resetCode = ""
    @Published public var resetNewPassword = ""
    @Published public var resetConfirmation = ""
    private var resetIntent = UUID()
    private let store: BoardStore
    private let catalog: ServerCatalog
    private let discovery: any ServerDiscovering
    private let now: @MainActor () -> Date
    private var loginDeadlines: [DeploymentURL: LoginRetryDeadline] = [:]
    private let preferences: UserDefaults
    private let factory: @Sendable (DeploymentURL) -> any FiestaBoardService
    private var service: (any FiestaBoardService)?
    private var selected: SavedServer?
    public var selectedSavedHub: SavedServer? { selected }
    private var generation = UUID()
    // Presentation ownership survives hub selection, independently of request generation.
    @Published private var onboardingPresentationID: UUID?
    /// The root keeps user enrollment mounted while its own bootstrap runs.
    /// A cold saved-hub restore has no presentation owner and retains the shell.
    public var shouldPresentOnboarding: Bool {
        guard phase != .connected else { return false }
        if onboardingPresentationID != nil { return true }
        return store.status == nil && phase != .checking && phase != .unreachable
    }
    /// Reattach the current host without replacing its intent or clearing its hub.
    @discardableResult public func attachOnboardingPresentation() -> UUID {
        onboardingPresentationID ?? beginOnboardingPresentation()
    }
    /// Start one native presentation; replacing an unfinished form clears its secrets.
    @discardableResult public func beginOnboardingPresentation() -> UUID {
        if onboardingPresentationID != nil, phase != .connected { cancel() }
        let intent = UUID()
        onboardingPresentationID = intent
        return intent
    }
    public func dismissOnboardingPresentation(_ intent: UUID) {
        guard onboardingPresentationID == intent else { return }
        onboardingPresentationID = nil
        // A completed handoff retires the form without revoking the shell's service.
        guard phase != .connected else { return }
        cancelConnection()
    }
    private var operation: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var handedToStore = false
    private var removingServers: Set<UUID> = []
    private let selectedKey = "FiestaBoard.selectedServerID"

    public init(store: BoardStore, catalog: ServerCatalog, discovery: any ServerDiscovering,
                preferences: UserDefaults, snapshots: ShellSnapshotStore? = nil, now: @escaping @MainActor () -> Date = { Date() }, serviceFactory: @escaping @Sendable (DeploymentURL) -> any FiestaBoardService) {
        self.store = store; self.catalog = catalog; self.discovery = discovery
        self.preferences = preferences; self.snapshots = snapshots; self.now = now; factory = serviceFactory
    }
    @discardableResult public func start() -> Task<Void, Never> {
        return Task { await reloadCatalog() }
    }
    @discardableResult public func findServers() -> Task<Void, Never> {
        guard snapshot == nil, !busy else { return Task {} }
        stopDiscovery(); discoveryMessage = nil; discoveredServers = []
        hubDiscoveryFlow.requestDiscovery()
        guard hubDiscoveryFlow.mayBrowse else { return Task {} }
        return browseServers()
    }
    @discardableResult public func continueDiscoveryAfterExplanation() -> Task<Void, Never> {
        guard snapshot == nil, !busy, hubDiscoveryFlow.phase == .localNetworkExplanation else { return Task {} }
        hubDiscoveryFlow.continueAfterExplanation()
        return browseServers()
    }
    public func enterManualAddress() {
        stopDiscovery(); hubDiscoveryFlow.enterAddress()
    }
    private func browseServers() -> Task<Void, Never> {
        discoveryTask?.cancel(); searching = true; discoveryMessage = nil; discoveredServers = []
        let token = generation
        let task = Task { [weak self, discovery] in
            do {
                for try await results in discovery.snapshots() {
                    guard let self, generation == token, !Task.isCancelled else { return }
                    discoveredServers = results
                }
                guard let self, generation == token, !Task.isCancelled else { return }
                searching = false
                hubDiscoveryFlow.stopSearching()
                discoveryMessage = discoveredServers.isEmpty ? "No hubs found. Check Wi-Fi or enter an address manually." : nil
            } catch {
                guard let self, generation == token, !Task.isCancelled else { return }
                searching = false; hubDiscoveryFlow.stopSearching()
                discoveryMessage = "Discovery could not finish. Check Wi-Fi and Local Network settings, or enter an address manually."
            }
        }
        discoveryTask = task; return task
    }
    public func stopDiscovery() {
        discoveryTask?.cancel(); discoveryTask = nil; searching = false; hubDiscoveryFlow.stopSearching()
    }
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
        cancelConnection(); selected = record; phase = .checking; busy = true
        let token = generation, cleanup = cleanupTask
        let next = factory(deployment); service = next
        loginDeadlines = loginDeadlines.filter { $0.value.remainingSeconds(at: now()) > 0 }
        loginRetryDeadline = loginDeadlines[deployment]
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
                if case .identityChanged = error as? ServerCatalogError {
                    invalidateSnapshotSession(); await removeSnapshot(for: selected)
                    guard valid(token) else { return }
                }
                phase = knownRecordCanRetry(error) ? .unreachable : .picker
                snapshot = nil; message = safe(error)
                if phase == .unreachable { await publishComposePrincipal(next, token: token, offline: true) }
            }
            if valid(token) { busy = false }
        }
        operation = task; return task
    }
    private func knownRecordCanRetry(_ error: any Error) -> Bool {
        selected != nil && (error as? FiestaBoardError) == .networkUnavailable
    }
    @discardableResult public func retrySavedHub() -> Task<Void, Never> {
        guard phase == .unreachable, let selected else { return Task {} }
        return selectSaved(selected)
    }
    @discardableResult public func checkServerState() -> Task<Void, Never> {
        guard let service, !busy else { return Task {} }
        return run { [weak self] token in
            guard let self else { return }
            let result = try await service.bootstrap()
            guard valid(token) else { return }
            if let known = selected?.installationID, known != result.identity.installationID {
                invalidateSnapshotSession(); await removeSnapshot(for: selected)
                guard valid(token) else { return }
                cancelConnection()
                message = "This address identifies a different FiestaBoard installation. Remove the saved server and forget its sign-in before adding it again."
                return
            }
            snapshot = result; requiresStateCheck = false
            if setupWebReturn == .checking {
                setupWebReturn = result.phase == .ready || result.phase == .signIn ? .finished : .incomplete
            }
            await route(service, token: token)
        }
    }
    public func beginWebSetup() -> URL? {
        guard !busy, !requiresStateCheck,
              phase == .authentication(.chooseAuthentication) || phase == .authentication(.setupAdministrator),
              let snapshot, let url = URL(string: snapshot.deployment.description) else { return nil }
        setupWebReturn = .awaitingReturn
        return url
    }
    @discardableResult public func returnFromWebSetup() -> Task<Void, Never> {
        guard setupWebReturn == .awaitingReturn, !busy, service != nil else { return Task {} }
        setupWebReturn = .checking
        return checkServerState()
    }
    @discardableResult public func signIn() -> Task<Void, Never> {
        let secret = password; password = ""; setupToken = ""
        guard let service, !busy, !requiresStateCheck,
              (loginRetryDeadline?.remainingSeconds(at: now()) ?? 0) == 0,
              !username.isEmpty, !secret.isEmpty else { return Task {} }
        let user = username, remember = rememberMe
        return authenticate { try await service.login(username: user, password: secret, rememberMe: remember) }
    }
    public func beginPasswordReset() {
        guard phase == .authentication(.signIn), !busy, !requiresStateCheck else { return }
        clearResetSecrets(); password = ""; setupToken = ""
        resetIntent = UUID(); passwordResetFlow = PasswordResetFlow(); message = nil; validationFields = []; signInPasswordRejected = false
    }
    public func enterPasswordResetCode() { passwordResetFlow?.enterCode() }
    @discardableResult public func submitPasswordReset() -> Task<Void, Never> {
        let code = resetCode, secret = resetNewPassword, confirmation = resetConfirmation
        clearResetSecrets(); password = ""; setupToken = ""
        guard phase == .authentication(.signIn), let service, !busy, !requiresStateCheck,
              (loginRetryDeadline?.remainingSeconds(at: now()) ?? 0) == 0,
              let attempt = passwordResetFlow?.prepare(code: code, newPassword: secret, confirmation: confirmation) else { return Task {} }
        let intent = resetIntent
        return run { [weak self] token in
            guard let self else { return }
            do {
                try await service.resetPassword(code: attempt.code, newPassword: attempt.newPassword)
                guard valid(token), resetIntent == intent else { return }
                invalidateSnapshotSession(); await removeSnapshot(for: selected)
                guard valid(token), resetIntent == intent else { return }
                persistence = await service.sessionPersistenceState()
                guard valid(token), resetIntent == intent else { return }
                passwordResetFlow?.receive(.changed, for: attempt.id)
            } catch {
                guard valid(token), resetIntent == intent else { return }
                let result: PasswordResetFlow.Result
                switch error as? FiestaBoardError {
                case .invalidResetCode: result = .invalidCode
                case .validation(let fields): result = .rejectedFields(fields.contains(.newPassword) ? [.newPassword] : [])
                case .rateLimited: result = .rejectedFields([])
                default: result = .unknownOutcome; requiresStateCheck = true
                }
                passwordResetFlow?.receive(result, for: attempt.id)
                throw error
            }
        }
    }
    public func cancelPasswordReset() {
        if passwordResetFlow?.phase == .submitting {
            operation?.cancel(); operation = nil; busy = false; requiresStateCheck = true
        }
        resetIntent = UUID(); passwordResetFlow = nil; clearResetSecrets()
    }
    public func finishPasswordReset() {
        guard passwordResetFlow?.phase == .passwordChanged else { return }
        cancelPasswordReset()
    }
    private func clearResetSecrets() { resetCode = ""; resetNewPassword = ""; resetConfirmation = "" }
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
        busy = true; message = nil; validationFields = []; signInPasswordRejected = false
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
                if setupWebReturn == .checking { setupWebReturn = .unconfirmed }
                if (error as? FiestaBoardError) == .setupProofRequired { requiresSetupProof = true }
                if let known = error as? FiestaBoardError {
                    if known == .invalidCredentials { signInPasswordRejected = true }
                    if case .rateLimited(let seconds) = known,
                       let deployment = service?.deployment,
                       let deadline = LoginRetryDeadline(retryAfterSeconds: seconds, receivedAt: now()) {
                        loginDeadlines = loginDeadlines.filter { $0.value.remainingSeconds(at: now()) > 0 }
                        let retained = loginDeadlines[deployment]
                        let effective = retained.map { $0.endsAt > deadline.endsAt ? $0 : deadline } ?? deadline
                        loginDeadlines[deployment] = effective; loginRetryDeadline = effective
                    }
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
        if snapshot.phase != .ready {
            invalidateSnapshotSession(); await removeSnapshot(for: selected)
            guard valid(token) else { return }
            phase = .authentication(snapshot.phase); return
        }
        if handedToStore && store.hasRetainedService {
            // A required shell read may fail after authentication succeeded. Retry that retained actor without retiring its cookie.
            await store.reconnect(allowCandidateWrites: true, preferredBoardID: selected?.preferredBoardID).value
        } else {
            handedToStore = true
            await store.connect(next, allowCandidateWrites: true, preferredBoardID: selected?.preferredBoardID).value
        }
        guard valid(token) else { return }
        if store.status != nil {
            phase = .connected
            onboardingPresentationID = nil
            await publishComposePrincipal(next, token: token, offline: false)
            guard valid(token) else { return }
            await beginSnapshotSession(token: token)
        } else {
            message = store.message
            phase = selected != nil && store.hubReachable == false ? .unreachable : .authentication(.signIn)
            if phase != .unreachable { invalidateSnapshotSession(); await removeSnapshot(for: selected) }
        }
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
    public func cancel() {
        onboardingPresentationID = nil
        cancelConnection()
    }
    private func cancelConnection() {
        cancelPasswordReset()
        invalidateSnapshotSession()
        generation = UUID(); operation?.cancel(); operation = nil; stopDiscovery()
        let old = service, ownedByStore = handedToStore, previous = cleanupTask
        store.disconnect()
        if let old, !ownedByStore { cleanupTask = Task { await previous?.value; await old.disconnect() } }
        service = nil; handedToStore = false; snapshot = nil
        loginRetryDeadline = nil
        signInPasswordRejected = false; setupWebReturn = .none
        busy = false; phase = .picker; password = ""; setupToken = ""; rememberMe = false
        requiresStateCheck = false; requiresSetupProof = false; validationFields = []; persistence = .init(); message = nil
    }
    public func disconnect() { cancel() }
    @discardableResult public func storeConnectionChanged() -> Task<Void, Never> {
        guard phase == .connected, !store.connecting, store.status == nil else { return Task {} }
        let hub = selected
        invalidateSnapshotSession()
        phase = .authentication(.signIn); message = store.message
        return Task { await removeSnapshot(for: hub) }
    }
    @discardableResult public func logout() -> Task<Void, Never> {
        cancelPasswordReset()
        let hub = selected
        invalidateSnapshotSession()
        generation = UUID(); operation?.cancel(); operation = nil; stopDiscovery()
        service = nil; handedToStore = false; snapshot = nil; phase = .picker
        loginRetryDeadline = nil
        signInPasswordRejected = false; setupWebReturn = .none
        busy = false; password = ""; setupToken = ""; rememberMe = false; persistence = .init()
        let logout = store.logout()
        return Task { await removeSnapshot(for: hub); await logout.value }
    }
    public func forgetSignIn() async {
        guard let service else { return }
        let token = generation, hub = selected
        invalidateSnapshotSession(); await removeSnapshot(for: hub)
        guard valid(token) else { return }
        await service.forgetRememberedSession()
        let state = await service.sessionPersistenceState()
        guard valid(token) else { return }; persistence = state
    }
    public func removeServer(_ server: SavedServer) async {
        guard removingServers.insert(server.id).inserted else { return }
        defer { removingServers.remove(server.id) }
        let active = selected?.id == server.id
        let existing = service?.deployment == server.deployment ? service : nil
        let ownedByStore = active && handedToStore
        // Prefer this window's captured lease. For an unselected server, confirmation starts a new forget intent.
        let next = existing ?? factory(server.deployment)
        // Retire the active window synchronously so pending reads/writes cannot revive it.
        let retirement = active ? logout() : nil
        let noticeID = ownedByStore ? store.logoutNotices.last?.id : nil
        let token = generation
        if active { busy = true }
        await removeSnapshot(for: server)
        var remoteConfirmed = false
        if let retirement {
            await retirement.value
            if let noticeID {
                remoteConfirmed = store.logoutNotices.first { $0.id == noticeID }?.state == .succeeded
            }
        }
        if !ownedByStore {
            do {
                if existing == nil {
                    let observed = try await next.bootstrap()
                    guard let installation = server.installationID,
                          observed.identity.installationID == installation,
                          try await next.restoreRememberedSession(observedInstallationID: installation) else {
                        throw FiestaBoardError.staleSession
                    }
                }
                try await next.logout()
                remoteConfirmed = true
            } catch { /* Local removal still proceeds; report unconfirmed remote revocation below. */ }
        }
        await next.forgetRememberedSession()
        let state = await next.sessionPersistenceState()
        guard !state.cleanupPending else {
            if valid(token) { busy = false; message = "Saved sign-in could not be removed. Try again before removing this server." }
            return
        }
        do {
            try await catalog.remove(id: server.id)
            if preferences.string(forKey: selectedKey) == server.id.uuidString { preferences.removeObject(forKey: selectedKey) }
            await reloadCatalog()
            guard valid(token) else { return }
            busy = false
            if active {
                selected = nil
                if let replacement = savedServers.first {
                    let selection = selectSaved(replacement), selectionToken = generation
                    await selection.value
                    guard valid(selectionToken) else { return }
                }
            }
            if !remoteConfirmed {
                message = "Removed \(server.alias.isEmpty ? server.deployment.description : server.alias) from this device. Hub sign-out could not be confirmed; its session may still appear on the hub."
            }
        } catch { if valid(token) { busy = false; message = safe(error) } }
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
    private func invalidateSnapshotSession() {
        snapshotConsentEpoch &+= 1; snapshotLease = nil; composePrincipal = nil
    }
    private func publishComposePrincipal(_ next: any FiestaBoardService, token: UUID, offline: Bool) async {
        guard valid(token), let provider = next as? any ComposePrincipalProviding,
              let hub = selected, let installation = hub.installationID,
              hub.deployment == next.deployment else { return }
        let proof: ComposePrincipalProof?
        if offline {
            proof = await provider.rememberedComposePrincipal(installationID: installation)
        } else {
            guard snapshot?.auth.authenticated == true, snapshot?.auth.authKind == "mobile" else { return }
            proof = await provider.composePrincipal()
        }
        guard valid(token), selected?.id == hub.id, let proof,
              proof.verifiedOnline == !offline,
              Data(proof.identity.deploymentID.utf8) == Data(next.deployment.description.utf8),
              Data(proof.identity.installationID.utf8) == Data(installation.utf8) else { return }
        composePrincipal = proof
    }
    private func beginSnapshotSession(token: UUID) async {
        guard let snapshots, let hub = selected else { return }
        let consent = snapshotConsentEpoch
        do {
            let lease = try await snapshots.beginSession(for: hub)
            guard valid(token), consent == snapshotConsentEpoch else { try? await snapshots.revoke(lease); return }
            snapshotLease = lease
        } catch { if valid(token) { snapshotLease = nil } }
    }
    private func removeSnapshot(for hub: SavedServer?) async {
        guard let snapshots, let hub else { return }
        do { try await snapshots.remove(hub) }
        catch { if selected?.id == hub.id { message = "Cached content could not be cleared. Try again before leaving this device." } }
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
