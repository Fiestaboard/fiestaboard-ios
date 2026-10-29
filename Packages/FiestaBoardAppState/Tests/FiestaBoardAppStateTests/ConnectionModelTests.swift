import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class ConnectionModelTests: XCTestCase {
    private func model(_ service: OnboardingService) -> ConnectionModel {
        ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
    }
    func testDemoStartupNeverBuildsLiveServiceAndDisconnectReturnsPicker() async throws {
        let service = try OnboardingService(); let model = model(service)
        await model.start(demo: true).value
        XCTAssertEqual(model.phase, .demo)
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
    func testDemoWithCachedServerNeverInvokesFactoryOrDiscovery() async throws {
        let service = try OnboardingService()
        let catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let saved = try await catalog.upsert(SavedServer(deployment: service.deployment, alias: "Cached", installationID: "installation"))
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        prefs.set(saved.id.uuidString, forKey: "FiestaBoard.selectedServerID")
        let calls = FactoryCalls()
        let model = ConnectionModel(store: BoardStore(), catalog: catalog, discovery: ForbiddenDiscovery(), preferences: prefs, serviceFactory: { _ in calls.record(); return service })
        await model.start(demo: true).value
        XCTAssertEqual(model.phase, .demo); XCTAssertEqual(calls.count, 0)
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

}
private struct EmptyDiscovery: ServerDiscovering {
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> { AsyncThrowingStream { $0.finish() } }
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> { AsyncThrowingStream { $0.finish() } }
}
private actor OnboardingService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    let demo: DemoFiestaBoardService
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
    init() throws { deployment = try DeploymentURL("https://board.example.com"); demo = try DemoFiestaBoardService() }
    func blockBootstrap() { blocked = true }
    func waitForBootstrap() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func releaseBootstrap() { gate?.resume(); gate = nil }
    func bootstrap() async throws -> BootstrapSnapshot {
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
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus { try await demo.connect(allowCandidateWrites: false) }
    func boards() async throws -> [BoardSummary] { try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail { try await demo.board(target) }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func pageDocumentData(id: String) async throws -> Data { try await demo.pageDocumentData(id: id) }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { throw FiestaBoardError.unsupportedOperation }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { throw FiestaBoardError.unsupportedOperation }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { throw FiestaBoardError.unsupportedOperation }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { throw FiestaBoardError.unsupportedOperation }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { throw FiestaBoardError.unsupportedOperation }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { throw FiestaBoardError.unsupportedOperation }
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
