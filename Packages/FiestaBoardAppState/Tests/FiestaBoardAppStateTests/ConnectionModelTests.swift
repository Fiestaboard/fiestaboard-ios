import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class ConnectionModelTests: XCTestCase {
    private func model(_ service: OnboardingService) -> ConnectionModel {
        ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
    }
    func testSavedHubBootstrapFailureRetainsShellContextAndCanRecover() async throws {
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        await service.failBootstrap(.networkUnavailable)
        let model = model(service)
        let saved = SavedServer(deployment: service.deployment, alias: "Known hub", installationID: "installation")
        await model.selectSaved(saved).value
        XCTAssertEqual(model.phase, .unreachable)
        XCTAssertEqual(model.selectedSavedHub?.id, saved.id)
        XCTAssertNil(model.snapshot)
        await service.failBootstrap(nil)
        await model.retrySavedHub().value
        XCTAssertEqual(model.phase, .connected)
    }
    func testUnknownHubBootstrapFailureReturnsEnrollment() async throws {
        let service = try OnboardingService()
        await service.failBootstrap(.networkUnavailable)
        let model = model(service)
        model.address = service.deployment.description
        await model.connectAddress().value
        XCTAssertEqual(model.phase, .picker)
        XCTAssertNil(model.selectedSavedHub)
    }
    func testStartupNeverBuildsLiveServiceAndDisconnectReturnsPicker() async throws {
        let service = try OnboardingService(); let model = model(service)
        await model.start().value
        XCTAssertEqual(model.phase, .picker)
        let events = await service.events; XCTAssertTrue(events.isEmpty)
        model.disconnect(); XCTAssertEqual(model.phase, .picker)
    }
    func testBootstrapPrecedesRestoreAndNeverReplacesRememberedConsent() async throws {
        let service = try OnboardingService(); let model = model(service)
        model.address = "https://board.example.com"
        await model.connectAddress().value
        XCTAssertEqual(model.phase, .authentication(.signIn))
        let events = await service.events
        XCTAssertEqual(events, ["bootstrap", "restore:installation"])
    }
    func testSecretsClearSynchronouslyAndUnknownOutcomeRequiresExplicitCheck() async throws {
        let service = try OnboardingService(); let model = model(service)
        model.address = "https://board.example.com"; await model.connectAddress().value
        model.username = "admin"; model.password = "secret"; model.setupToken = "proof"
        let attempt = model.signIn()
        XCTAssertEqual(model.password, ""); XCTAssertEqual(model.setupToken, "")
        await attempt.value
        XCTAssertTrue(model.requiresStateCheck)
        XCTAssertNotNil(model.message)
        await model.signIn().value
        let events = await service.events; XCTAssertEqual(events.filter { $0 == "login" }.count, 1)
        await model.checkServerState().value; XCTAssertFalse(model.requiresStateCheck)
    }
    func testSavedIdentityMismatchStopsBeforeRestore() async throws {
        let service = try OnboardingService(); let model = model(service)
        let record = SavedServer(deployment: service.deployment, alias: "Old", installationID: "different")
        await model.selectSaved(record).value
        XCTAssertEqual(model.phase, .picker); XCTAssertNotNil(model.message)
        let events = await service.events; XCTAssertEqual(events, ["bootstrap"])
    }
    func testCancelledBootstrapCannotPublishItsLateResult() async throws {
        let service = try OnboardingService(); await service.blockBootstrap()
        let model = model(service); model.address = "https://board.example.com"
        let attempt = model.connectAddress(); await service.waitForBootstrap()
        model.cancel(); await service.releaseBootstrap(); await attempt.value
        XCTAssertEqual(model.phase, .picker); XCTAssertNil(model.snapshot)
    }
    func testCheckStateCannotAssociateChangedInstallation() async throws {
        let service = try OnboardingService(); let model = model(service)
        model.address = service.deployment.description; await model.connectAddress().value
        await service.changeInstallation("replacement")
        await model.checkServerState().value
        XCTAssertEqual(model.phase, .picker)
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.message?.contains("different FiestaBoard installation") == true)
    }
    func testStartupWithCachedServerNeverInvokesFactoryOrDiscovery() async throws {
        let service = try OnboardingService()
        let catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let saved = try await catalog.upsert(SavedServer(deployment: service.deployment, alias: "Cached", installationID: "installation"))
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        prefs.set(saved.id.uuidString, forKey: "FiestaBoard.selectedServerID")
        let calls = FactoryCalls()
        let model = ConnectionModel(store: BoardStore(), catalog: catalog, discovery: ForbiddenDiscovery(), preferences: prefs, serviceFactory: { _ in calls.record(); return service })
        await model.start().value
        XCTAssertEqual(model.phase, .picker); XCTAssertEqual(calls.count, 0)
    }

    func testCancellingSetupDuringPersistencePreparationCannotSubmitAdministrator() async throws {
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: true, authenticated: false))
        await service.blockConfiguration()
        let model = model(service); model.address = service.deployment.description
        await model.connectAddress().value
        model.username = "admin"; model.password = "secret"; model.rememberMe = true
        let attempt = model.setupAdministrator(); await service.waitForConfiguration()
        model.cancel(); await service.releaseConfiguration(); await attempt.value
        let events = await service.events
        XCTAssertFalse(events.contains("setup")); XCTAssertEqual(model.phase, .picker)
    }
    func testCredentialAndRateLimitErrorsStayActionableWithoutAutomaticRetry() async throws {
        let service = try OnboardingService(); let model = model(service)
        model.address = service.deployment.description; await model.connectAddress().value
        model.username = "admin"; model.password = "wrong"
        await service.setLoginError(.invalidCredentials); await model.signIn().value
        XCTAssertFalse(model.requiresStateCheck); XCTAssertTrue(model.message?.contains("incorrect") == true)
        model.password = "retry"
        await service.setLoginError(.rateLimited(retryAfterSeconds: 30)); await model.signIn().value
        XCTAssertTrue(model.message?.contains("30 seconds") == true)
        XCTAssertEqual(model.password, "")
        let events = await service.events; XCTAssertEqual(events.filter { $0 == "login" }.count, 2)
    }
    func testUnknownAuthenticationKindDoesNotOpenShell() async throws {
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: false, authenticated: true, authKind: "future-kind"))
        let model = model(service); model.address = service.deployment.description
        await model.connectAddress().value
        XCTAssertEqual(model.phase, .authentication(.signIn))
    }

    func testLateInitialBoardSelectionCannotOverwriteRestoredPreference() async throws {
        let service = try OnboardingService(); await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let saved = try await catalog.upsert(SavedServer(deployment: service.deployment, alias: "Saved", installationID: "installation", preferredBoardID: "board-led"))
        let store = BoardStore()
        let model = ConnectionModel(store: store, catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
        await model.selectSaved(saved).value
        XCTAssertEqual(model.phase, .connected); XCTAssertEqual(store.selectedBoardID, "board-led")
        await model.persistPreferredBoard("board-2")
        let records = try await catalog.list(); XCTAssertEqual(records.first?.preferredBoardID, "board-led")
    }

    func testAutomaticPreferredSelectionPreservesUnknownCommandBarrierForInitialAndOtherBoard() async throws {
        for preferred in ["board-2", "board-led"] {
            let service = try OnboardingService(usingDemoDeployment: true)
            await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
            let catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let saved = try await catalog.upsert(SavedServer(deployment: service.deployment, alias: "Saved", installationID: "installation", preferredBoardID: preferred))
            let store = BoardStore()
            let model = ConnectionModel(store: store, catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
            await model.selectSaved(saved).value
            XCTAssertEqual(store.selectedBoardID, preferred)
            await service.demo.setSimulation(.unknown)
            await store.confirm(try XCTUnwrap(store.prepare(.text("UNCERTAIN")))).value
            XCTAssertTrue(store.needsReadback)
            model.disconnect()
            await model.selectSaved(saved).value
            XCTAssertEqual(model.phase, .connected)
            XCTAssertEqual(store.selectedBoardID, preferred)
            XCTAssertTrue(store.needsReadback, "Automatic preferred selection must not acknowledge recovery for \(preferred)")
            await store.reconnect(allowCandidateWrites: true).value
            XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canWrite)
            await store.refresh().value
            XCTAssertFalse(store.needsReadback); XCTAssertTrue(store.canWrite)
        }
    }
    func testCheckStateRetriesRequiredShellLoadWithoutClearingAuthenticatedMemorySession() async throws {
        for failBoards in [false, true] {
            let service = try OnboardingService(usingDemoDeployment: true)
            await service.chooseAuth(AuthStatus(enabled: true, setupRequired: false, authenticated: true, authKind: "session"))
            await service.failNextShellLoad(boards: failBoards)
            let store = BoardStore()
            let model = ConnectionModel(store: store, catalog: ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
            model.address = service.deployment.description
            await model.connectAddress().value
            XCTAssertNil(store.status)
            await model.checkServerState().value
            XCTAssertEqual(model.phase, .connected); XCTAssertNotNil(store.status)
            let events = await service.events
            XCTAssertFalse(events.contains("disconnect")); XCTAssertFalse(events.contains("login"))
        }
    }

}
private struct EmptyDiscovery: ServerDiscovering {
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> { AsyncThrowingStream { $0.finish() } }
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> { AsyncThrowingStream { $0.finish() } }
}
private actor OnboardingService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    let demo: FixtureFiestaBoardService
    var events: [String] = []
    var installation = "installation"
    func changeInstallation(_ value: String) { installation = value }
    var auth = AuthStatus(enabled: true, setupRequired: false, authenticated: false)
    var loginError = FiestaBoardError.unknownMutationOutcome
    var configurationBlocked = false
    var configurationGate: CheckedContinuation<Void, Never>?
    var configurationObservers: [CheckedContinuation<Void, Never>] = []
    func chooseAuth(_ value: AuthStatus) { auth = value }
    func setLoginError(_ value: FiestaBoardError) { loginError = value }
    func blockConfiguration() { configurationBlocked = true }
    func waitForConfiguration() async { if configurationGate != nil { return }; await withCheckedContinuation { configurationObservers.append($0) } }
    func releaseConfiguration() { configurationGate?.resume(); configurationGate = nil }
    var blocked = false
    var gate: CheckedContinuation<Void, Never>?
    var observers: [CheckedContinuation<Void, Never>] = []
    init(usingDemoDeployment: Bool = false) throws {
        let demo = try FixtureFiestaBoardService(); self.demo = demo
        deployment = usingDemoDeployment ? demo.deployment : try DeploymentURL("https://board.example.com")
    }
    func blockBootstrap() { blocked = true }
    func waitForBootstrap() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func releaseBootstrap() { gate?.resume(); gate = nil }
    var bootstrapFailure: FiestaBoardError?
    func failBootstrap(_ error: FiestaBoardError?) { bootstrapFailure = error }
    func bootstrap() async throws -> BootstrapSnapshot {
        if let bootstrapFailure { throw bootstrapFailure }
        events.append("bootstrap")
        if blocked { await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] } }
        return try BootstrapSnapshot(deployment: deployment, health: ServerHealth(status: "ok", serviceRunning: false, version: "10.1.17"), identity: ServerIdentity(product: "FiestaBoard", version: "10.1.17", installationID: installation, name: "Test"), auth: authStatus())
    }
    func restoreRememberedSession(observedInstallationID: String) async throws -> Bool { events.append("restore:" + observedInstallationID); return false }
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {
        events.append("configure")
        if configurationBlocked { await withCheckedContinuation { configurationGate = $0; configurationObservers.forEach { $0.resume() }; configurationObservers = [] } }
    }
    func setupAdministrator(username: String, password: String, setupToken: String?) async throws -> AuthStatus { events.append("setup"); return auth }

    func authStatus() -> AuthStatus { auth }
    func login(username: String, password: String) async throws -> AuthStatus { throw FiestaBoardError.unknownMutationOutcome }
    func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus { events.append("login"); throw loginError }
    func logout() async throws {}
    private var connectFailure = false
    private var boardsFailure = false
    func failNextShellLoad(boards: Bool) { if boards { boardsFailure = true } else { connectFailure = true } }
    func disconnect() async {
        events.append("disconnect")
        if auth.enabled { auth = AuthStatus(enabled: true, setupRequired: false, authenticated: false) }
    }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        events.append("connect")
        if connectFailure { connectFailure = false; throw FiestaBoardError.networkUnavailable }
        guard !auth.enabled || auth.authenticated else { throw FiestaBoardError.unauthenticated }
        return try await demo.connect(allowCandidateWrites: false)
    }
    func boards() async throws -> [BoardSummary] {
        if boardsFailure { boardsFailure = false; throw FiestaBoardError.networkUnavailable }
        return try await demo.boards()
    }
    func board(_ target: BoardTarget) async throws -> BoardDetail { try await demo.board(target) }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func pageDocumentData(id: String) async throws -> Data { try await demo.pageDocumentData(id: id) }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { throw FiestaBoardError.unsupportedOperation }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { throw FiestaBoardError.unsupportedOperation }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { throw FiestaBoardError.unsupportedOperation }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { throw FiestaBoardError.unsupportedOperation }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { throw FiestaBoardError.unsupportedOperation }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { try await demo.sendText(text, to: target) }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { throw FiestaBoardError.unsupportedOperation }
}

private final class FactoryCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}
private struct ForbiddenDiscovery: ServerDiscovering {
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> { fatalError("Demo must not start discovery") }
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> { fatalError("Demo must not start discovery") }
}

extension ConnectionModelTests {
    func testAppOwnedPersistenceSharesOneCatalogAcrossConcurrentSceneUpdates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appPersistence = ConnectionPersistence(directory: directory)
        // DraftScene receives copies of this app-owned value; active Model/Store state remains independent.
        let firstScenePersistence = appPersistence
        let secondScenePersistence = appPersistence
        let firstCatalog = firstScenePersistence.catalog, secondCatalog = secondScenePersistence.catalog
        XCTAssertTrue(firstCatalog === secondCatalog)
        let records = try (0..<40).map {
            SavedServer(deployment: try DeploymentURL("https://board\($0).example.com"), alias: "Board \($0)")
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, record) in records.enumerated() {
                let catalog = index.isMultiple(of: 2) ? firstCatalog : secondCatalog
                group.addTask { _ = try await catalog.upsert(record) }
            }
            try await group.waitForAll()
        }
        let inserted = try await firstCatalog.list()
        XCTAssertEqual(Set(inserted.map(\.id)), Set(records.map(\.id)))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, record) in records.enumerated() {
                if index < 10 { group.addTask { try await firstCatalog.remove(id: record.id) } }
                else {
                    var changed = record; changed.alias = "Renamed \(index)"
                    let update = changed
                    group.addTask { _ = try await secondCatalog.upsert(update) }
                }
            }
            try await group.waitForAll()
        }
        let updated = try await secondCatalog.list()
        XCTAssertEqual(updated.count, 30)
        XCTAssertTrue(updated.allSatisfy { $0.alias.hasPrefix("Renamed ") })
        XCTAssertTrue(Set(updated.map(\.id)).isDisjoint(with: Set(records.prefix(10).map(\.id))))
    }
}

/// Exercises the actual URLSessionTransport restore boundary without using the host Keychain.
private actor EmptyRememberedConnectionVault: SessionVault {
    func load(for deployment: DeploymentURL) -> Data? { nil }
    func save(_ data: Data, for deployment: DeploymentURL) {}
    func remove(for deployment: DeploymentURL) {}
}

private final class AuthDisabledConnectionURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let page = #"{"id":"p","name":"Page","type":"template","device_type":"panel","template":["raw"],"unknown":null}"#
        let body: String
        switch request.url!.lastPathComponent {
        case "health": body = #"{"status":"ok","service_running":true,"version":"10.1.20"}"#
        case "discover": body = #"{"product":"FiestaBoard","version":"10.1.20","id":"native-installation","name":"Test"}"#
        case "status": body = #"{"enabled":false,"setup_required":false,"authenticated":false,"mode":"disabled","first_run":false}"#
        case "version": body = #"{"package_version":"10.1.20","build_version":"test","running_version":"10.1.20","is_dev":false}"#
        case "boards": body = #"{"boards":[],"total":0}"#
        case "pages": body = "{\"pages\":[\(page)],\"total\":1}"
        case "collection:00000000-0000-4000-8000-000000000022": body = #"{"id":"collection:00000000-0000-4000-8000-000000000022","name":"Collection","page_ids":["p"],"selection_mode":"time","time":{"interval_seconds":30},"revision":"original","edit_protocol":"collection-revision-v1"}"#
        case "p": body = page
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension ConnectionModelTests {
    func testAuthDisabledSelectionWithNoRememberedMaterialPublishesScopeForLocalEditor() async throws {
        for hasVault in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let deployment = try DeploymentURL("https://board.example.com")
            let vault: (any SessionVault)? = hasVault ? EmptyRememberedConnectionVault() : nil
            let transport = URLSessionTransport(deployment: deployment, protocolClasses: [AuthDisabledConnectionURLProtocol.self], vault: vault)
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
            let store = BoardStore()
            let model = ConnectionModel(store: store, catalog: ServerCatalog(directory: directory), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
            model.address = deployment.description
            await model.connectAddress().value
            XCTAssertEqual(model.phase, .connected, "vault present: \(hasVault)")
            XCTAssertNotNil(store.status)
            let snapshot = try await store.loadPageDocument(id: "p")
            XCTAssertEqual(snapshot.scope.installationID, "native-installation")
            XCTAssertEqual(snapshot.scope.deployment, deployment)
            XCTAssertFalse(snapshot.scope.isDemo)
            XCTAssertNotNil(store.status, "Opening an editor must keep the connection active")
            let creation = try await store.beginCollectionEditor(id: nil)
            let collection = try await store.beginCollectionEditor(id: "collection:00000000-0000-4000-8000-000000000022")
            XCTAssertEqual(creation.scope, snapshot.scope); XCTAssertNil(creation.collection)
            XCTAssertEqual(collection.scope, snapshot.scope); XCTAssertEqual(collection.context.scope, snapshot.scope)
            XCTAssertEqual(collection.collection?.revision, "original")
            await store.reconnect(allowCandidateWrites: false).value
            let reconnected = try await store.loadPageDocument(id: "p")
            XCTAssertEqual(snapshot.scope, reconnected.scope)
            let restoredCollection = try await store.beginCollectionEditor(id: "collection:00000000-0000-4000-8000-000000000022")
            XCTAssertEqual(collection.scope, restoredCollection.scope)
            do { _ = try await store.readbackCollection(context: collection.context); XCTFail("Durable scope must not revive an old live context") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        }
    }
}
