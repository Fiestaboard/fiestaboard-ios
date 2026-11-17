import XCTest
@testable import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class ConnectionModelTests: XCTestCase {
    private func model(_ service: OnboardingService, now: @escaping @MainActor () -> Date = { Date() }) -> ConnectionModel {
        ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, now: now, serviceFactory: { _ in service })
    }
    private final class Clock { var value = Date(timeIntervalSince1970: 1_000) }

    // The actual request gate must use elapsed wall time, including time in the background.
    func testLoginDispatchResumesExactlyAtTheAdvertisedDeadline() async throws {
        let clock = Clock(), service = try OnboardingService()
        let model = model(service, now: { clock.value })
        await service.setLoginError(.rateLimited(retryAfterSeconds: 60))
        model.address = service.deployment.description
        await model.connectAddress().value
        model.username = "admin"; model.password = "wrong-password"
        await model.signIn().value
        clock.value = Date(timeIntervalSince1970: 1_059.999)
        model.password = "still-before-deadline"; await model.signIn().value
        let before = await service.events.filter { $0 == "login" }.count
        XCTAssertEqual(before, 1)
        clock.value = Date(timeIntervalSince1970: 1_060)
        model.password = "new-user-attempt"; await model.signIn().value
        let after = await service.events.filter { $0 == "login" }.count
        XCTAssertEqual(after, 2)
    }

    // Returning through the hub picker must not bypass this hub's live lockout.
    func testReselectingTheSameHubKeepsItsAdvertisedLockout() async throws {
        let clock = Clock(), service = try OnboardingService()
        let model = model(service, now: { clock.value })
        await service.setLoginError(.rateLimited(retryAfterSeconds: 60))
        model.address = service.deployment.description; await model.connectAddress().value
        model.username = "admin"; model.password = "wrong-password"; await model.signIn().value
        model.cancel()
        model.address = service.deployment.description; await model.connectAddress().value
        model.username = "admin"; model.password = "try-from-picker"; await model.signIn().value
        let attempts = await service.events.filter { $0 == "login" }.count
        XCTAssertEqual(attempts, 1)
    }

    // Removing the auth Retry-After gate must dispatch a second forbidden login.
    func testLoginLockoutDoesNotDispatchAnImmediateSecondAttempt() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.setLoginError(.rateLimited(retryAfterSeconds: 60))
        model.address = service.deployment.description
        await model.connectAddress().value
        model.username = "admin"; model.password = "wrong-password"
        await model.signIn().value
        model.password = "new-attempt-before-deadline"
        await model.signIn().value
        let attempts = await service.events.filter { $0 == "login" }.count
        XCTAssertEqual(attempts, 1, "Retry-After blocks network dispatch, not only the button's copy")
        XCTAssertEqual(model.username, "admin")
        XCTAssertTrue(model.password.isEmpty)
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
    func testKnownHubRateLimitIsNotNetworkFailureAndDoesNotAutomaticallyRetry() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.failBootstrap(.rateLimited(retryAfterSeconds: 120))
        let saved = SavedServer(deployment: service.deployment, alias: "Known hub", installationID: "installation")
        await model.selectSaved(saved).value
        XCTAssertEqual(model.phase, .picker)
        XCTAssertEqual(model.selectedSavedHub?.id, saved.id)
        XCTAssertTrue(model.message?.contains("120") == true)
        let before = await service.bootstrapAttempts
        await model.retrySavedHub().value
        let after = await service.bootstrapAttempts
        XCTAssertEqual(after, before)
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
    func testForgetAndAuthenticationLossRemoveSnapshotAndRevokePendingWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let snapshots = ShellSnapshotStore(directory: directory.appendingPathComponent("snapshots"))
        let store = BoardStore()
        let model = ConnectionModel(store: store, catalog: ServerCatalog(directory: directory), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, snapshots: snapshots, serviceFactory: { _ in service })
        let saved = SavedServer(deployment: service.deployment, alias: "Known", installationID: "installation")
        await model.selectSaved(saved).value
        let hub = try XCTUnwrap(model.selectedSavedHub)
        let first = try XCTUnwrap(model.snapshotLease)
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(), board: nil, displayName: "Kitchen", pages: [])
        _ = try await snapshots.write(snapshot, lease: first)
        await model.forgetSignIn()
        XCTAssertNil(model.snapshotLease)
        let staleWrite = try await snapshots.write(snapshot, lease: first)
        XCTAssertFalse(staleWrite)
        let forgotten = try await snapshots.read(for: hub, at: Date())
        XCTAssertNil(forgotten)
        await model.selectSaved(hub).value
        let second = try XCTUnwrap(model.snapshotLease)
        _ = try await snapshots.write(snapshot, lease: second)
        store.disconnect()
        await model.storeConnectionChanged().value
        let signedOut = try await snapshots.read(for: hub, at: Date())
        XCTAssertNil(signedOut)
        XCTAssertNil(model.snapshotLease)
    }
    func testInstallationChangeAndForgetHubClearDurableSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let snapshots = ShellSnapshotStore(directory: directory.appendingPathComponent("snapshots"))
        let model = ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: directory), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, snapshots: snapshots, serviceFactory: { _ in service })
        let saved = SavedServer(deployment: service.deployment, alias: "Known", installationID: "installation")
        await model.selectSaved(saved).value
        let hub = try XCTUnwrap(model.selectedSavedHub)
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(), board: nil, displayName: "Kitchen", pages: [])
        _ = try await snapshots.write(snapshot, lease: XCTUnwrap(model.snapshotLease))
        await service.changeInstallation("different")
        await model.checkServerState().value
        let replaced = try await snapshots.read(for: hub, at: Date())
        XCTAssertNil(replaced)
        XCTAssertNil(model.snapshotLease)
        await service.changeInstallation("installation")
        await model.selectSaved(hub).value
        let lease = try XCTUnwrap(model.snapshotLease)
        _ = try await snapshots.write(snapshot, lease: lease)
        await model.removeServer(hub)
        let removed = try await snapshots.read(for: hub, at: Date())
        XCTAssertNil(removed)
        let staleWrite = try await snapshots.write(snapshot, lease: lease)
        XCTAssertFalse(staleWrite)
    }
    func testStartupNeverBuildsLiveServiceAndDisconnectReturnsPicker() async throws {
        let service = try OnboardingService(); let model = model(service)
        await model.start().value
        XCTAssertEqual(model.phase, .picker)
        let events = await service.events; XCTAssertTrue(events.isEmpty)
        model.disconnect(); XCTAssertEqual(model.phase, .picker)
    }
    func testForgettingActiveHubSignsOutAndClosesItsWindow() async throws {
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let store = BoardStore(), catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = ConnectionModel(store: store, catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
        await model.selectSaved(SavedServer(deployment: service.deployment, alias: "Kitchen", installationID: "installation")).value
        let hub = try XCTUnwrap(model.selectedSavedHub)
        XCTAssertNotNil(store.status)
        await model.removeServer(hub)
        XCTAssertEqual(model.phase, .picker)
        XCTAssertNil(model.selectedSavedHub)
        XCTAssertNil(store.status)
        XCTAssertTrue(model.savedServers.isEmpty)
        let events = await service.events
        XCTAssertEqual(events.filter { $0 == "logout" }.count, 1)
    }
    func testForgettingInactiveHubVerifiesInstallationBeforeRestoringItsSignIn() async throws {
        let active = try OnboardingService(), inactive = try OnboardingService(deploymentAddress: "https://other.example.com")
        await active.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        await inactive.setRestoreResult(true)
        let store = BoardStore(), catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let other = try await catalog.upsert(SavedServer(deployment: inactive.deployment, alias: "Other", installationID: "installation"))
        let model = ConnectionModel(store: store, catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { $0 == active.deployment ? active : inactive })
        await model.selectSaved(SavedServer(deployment: active.deployment, alias: "Kitchen", installationID: "installation")).value
        let hub = model.selectedSavedHub
        await model.removeServer(other)
        XCTAssertEqual(model.selectedSavedHub?.id, hub?.id)
        XCTAssertEqual(model.phase, .connected)
        XCTAssertNotNil(store.status)
        let events = await inactive.events
        XCTAssertEqual(Array(events.prefix(3)), ["bootstrap", "restore:installation", "logout"])
        XCTAssertFalse(model.savedServers.contains { $0.id == other.id })
    }
    func testForgettingChangedInstallationNeverRestoresCredentialsAndReportsUnconfirmedSignOut() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.changeInstallation("replacement")
        let hub = SavedServer(deployment: service.deployment, alias: "Old hub", installationID: "original")
        await model.removeServer(hub)
        let events = await service.events
        XCTAssertEqual(events.first, "bootstrap")
        XCTAssertFalse(events.contains { $0.hasPrefix("restore:") || $0 == "logout" })
        XCTAssertTrue(model.message?.contains("could not be confirmed") == true)
    }
    func testForgettingActiveHubSelectsNextSavedHub() async throws {
        let active = try OnboardingService(), next = try OnboardingService(deploymentAddress: "https://next.example.com")
        for service in [active, next] { await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false)) }
        let catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let replacement = try await catalog.upsert(SavedServer(deployment: next.deployment, alias: "Next", installationID: "installation"))
        let model = ConnectionModel(store: BoardStore(), catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { $0 == active.deployment ? active : next })
        await model.selectSaved(SavedServer(deployment: active.deployment, alias: "First", installationID: "installation")).value
        await model.removeServer(try XCTUnwrap(model.selectedSavedHub))
        XCTAssertEqual(model.selectedSavedHub?.id, replacement.id)
        XCTAssertEqual(model.phase, .connected)
        let events = await next.events
        XCTAssertFalse(events.contains("logout"))
    }
    func testForgettingHubKeepsRecordWhenProtectedCleanupFails() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        await model.selectSaved(SavedServer(deployment: service.deployment, alias: "Kitchen", installationID: "installation")).value
        let hub = try XCTUnwrap(model.selectedSavedHub)
        await service.failProtectedCleanup()
        await model.removeServer(hub)
        XCTAssertTrue(model.savedServers.contains { $0.id == hub.id })
        XCTAssertTrue(model.message?.contains("could not be removed") == true)
        XCTAssertFalse(model.busy)
    }
    func testLateForgetCompletionCannotDisconnectNewSelectedHub() async throws {
        let first = try OnboardingService(), second = try OnboardingService(deploymentAddress: "https://second.example.com")
        for service in [first, second] { await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false)) }
        let store = BoardStore(), catalog = ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = ConnectionModel(store: store, catalog: catalog, discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { $0 == first.deployment ? first : second })
        await model.selectSaved(SavedServer(deployment: first.deployment, alias: "First", installationID: "installation")).value
        let removed = try XCTUnwrap(model.selectedSavedHub)
        await first.blockLogout()
        let forget = Task { await model.removeServer(removed) }
        await first.waitForLogout()
        XCTAssertNil(store.status, "Retire active writes before awaiting the hub")
        await model.selectSaved(SavedServer(deployment: second.deployment, alias: "Second", installationID: "installation")).value
        let selected = try XCTUnwrap(model.selectedSavedHub)
        await first.releaseLogout()
        await forget.value
        XCTAssertEqual(model.selectedSavedHub?.id, selected.id)
        XCTAssertEqual(model.phase, .connected)
        XCTAssertNotNil(store.status)
        XCTAssertFalse(model.savedServers.contains { $0.id == removed.id })
    }
    func testLogoutPurgesCachedContentBeforeRemoteSignOutCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try OnboardingService()
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let snapshots = ShellSnapshotStore(directory: directory.appendingPathComponent("snapshots"))
        let model = ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: directory), discovery: EmptyDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, snapshots: snapshots, serviceFactory: { _ in service })
        await model.selectSaved(SavedServer(deployment: service.deployment, alias: "Kitchen", installationID: "installation")).value
        let hub = try XCTUnwrap(model.selectedSavedHub), lease = try XCTUnwrap(model.snapshotLease)
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(), board: nil, displayName: "Private content", pages: [.init(id: "private", name: "Private page")])
        _ = try await snapshots.write(snapshot, lease: lease)
        await service.blockLogout()
        let logout = model.logout()
        await service.waitForLogout()
        // Observe local cleanup independently while DELETE remains suspended.
        var cached = try await snapshots.read(for: hub, at: Date())
        for _ in 0..<200 where cached != nil {
            try await Task.sleep(for: .milliseconds(5))
            cached = try await snapshots.read(for: hub, at: Date())
        }
        XCTAssertNil(cached, "Explicit logout must purge local content without waiting for the hub")
        let staleWrite = try await snapshots.write(snapshot, lease: lease)
        XCTAssertFalse(staleWrite, "A pending writer cannot restore content after logout")
        let newerLease = try await snapshots.beginSession(for: hub)
        _ = try await snapshots.write(snapshot, lease: newerLease)
        await service.releaseLogout()
        await logout.value
        let newerSnapshot = try await snapshots.read(for: hub, at: Date())
        XCTAssertNotNil(newerSnapshot, "Old remote completion cannot purge a newer same-hub cache")
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
private actor OnboardingService: FiestaBoardService, ComposePrincipalProviding {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    let demo: FixtureFiestaBoardService
    var events: [String] = []
    var suppliedComposePrincipal: ComposePrincipalProof?
    func supplyComposePrincipal(_ proof: ComposePrincipalProof?) { suppliedComposePrincipal = proof }
    func composePrincipal() -> ComposePrincipalProof? { suppliedComposePrincipal?.verifiedOnline == true ? suppliedComposePrincipal : nil }
    private var composeProofBlocked = false
    private var composeProofGate: CheckedContinuation<Void, Never>?
    private var composeProofObserver: CheckedContinuation<Void, Never>?
    func blockComposeProof() { composeProofBlocked = true }
    func waitForComposeProof() async { if composeProofGate != nil { return }; await withCheckedContinuation { composeProofObserver = $0 } }
    func releaseComposeProof() { composeProofGate?.resume(); composeProofGate = nil }
    func rememberedComposePrincipal(installationID: String) async -> ComposePrincipalProof? {
        if composeProofBlocked { await withCheckedContinuation { composeProofGate = $0; composeProofObserver?.resume(); composeProofObserver = nil } }
        guard let proof = suppliedComposePrincipal, !proof.verifiedOnline,
              Data(proof.identity.installationID.utf8) == Data(installationID.utf8) else { return nil }
        return proof
    }
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
    init(usingDemoDeployment: Bool = false, deploymentAddress: String = "https://board.example.com") throws {
        let demo = try FixtureFiestaBoardService(); self.demo = demo
        deployment = usingDemoDeployment ? demo.deployment : try DeploymentURL(deploymentAddress)
    }
    func blockBootstrap() { blocked = true }
    func waitForBootstrap() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func releaseBootstrap() { gate?.resume(); gate = nil }
    var bootstrapAttempts = 0
    var bootstrapFailure: FiestaBoardError?
    func failBootstrap(_ error: FiestaBoardError?) { bootstrapFailure = error }
    func bootstrap() async throws -> BootstrapSnapshot {
        bootstrapAttempts += 1
        if let bootstrapFailure { throw bootstrapFailure }
        events.append("bootstrap")
        if blocked { await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] } }
        return try BootstrapSnapshot(deployment: deployment, health: ServerHealth(status: "ok", serviceRunning: false, version: "10.1.17"), identity: ServerIdentity(product: "FiestaBoard", version: "10.1.17", installationID: installation, name: "Test"), auth: authStatus())
    }
    var restoreResult = false
    func setRestoreResult(_ value: Bool) { restoreResult = value }
    func restoreRememberedSession(observedInstallationID: String) async throws -> Bool { events.append("restore:" + observedInstallationID); return restoreResult }
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {
        events.append("configure")
        if configurationBlocked { await withCheckedContinuation { configurationGate = $0; configurationObservers.forEach { $0.resume() }; configurationObservers = [] } }
    }
    func setupAdministrator(username: String, password: String, setupToken: String?) async throws -> AuthStatus { events.append("setup"); return auth }

    func authStatus() -> AuthStatus { auth }
    func login(username: String, password: String) async throws -> AuthStatus { throw FiestaBoardError.unknownMutationOutcome }
    func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus { events.append("login"); throw loginError }
    private var logoutBlocked = false
    private var logoutGate: CheckedContinuation<Void, Never>?
    private var logoutObservers: [CheckedContinuation<Void, Never>] = []
    func blockLogout() { logoutBlocked = true }
    func waitForLogout() async { if logoutGate != nil { return }; await withCheckedContinuation { logoutObservers.append($0) } }
    func releaseLogout() { logoutGate?.resume(); logoutGate = nil; logoutBlocked = false }
    private var protectedCleanupFailed = false
    func failProtectedCleanup() { protectedCleanupFailed = true }
    func sessionPersistenceState() -> SessionPersistenceState { .init(cleanupPending: protectedCleanupFailed) }
    func logout() async throws {
        events.append("logout")
        if logoutBlocked { await withCheckedContinuation { logoutGate = $0; logoutObservers.forEach { $0.resume() }; logoutObservers = [] } }
    }
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

extension ConnectionModelTests {
    // The wrong-password surface must target the password field while preserving the entered username.
    func testWrongCredentialsPublishPasswordFieldRejectionAndResetClearsIt() async throws {
        let service = try OnboardingService(), model = model(service)
        model.address = service.deployment.description; await model.connectAddress().value
        await service.setLoginError(.invalidCredentials)
        model.username = "retained-owner"; model.password = "wrong-secret"
        await model.signIn().value
        XCTAssertTrue(model.signInPasswordRejected)
        XCTAssertEqual(model.username, "retained-owner"); XCTAssertEqual(model.password, "")
        XCTAssertEqual(model.phase, .authentication(.signIn)); XCTAssertFalse(model.requiresStateCheck)
        model.beginPasswordReset()
        XCTAssertFalse(model.signInPasswordRejected)
        XCTAssertEqual(model.passwordResetFlow?.phase, .instructions)
    }

    // Opening setup uses the verified selected deployment; returning reads once without admin creation or sign in.
    func testWebSetupReturnRechecksOnceAndKeepsTheVerifiedHub() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: true, authenticated: false))
        model.address = service.deployment.description; await model.connectAddress().value
        let hub = try XCTUnwrap(model.selectedSavedHub)
        model.address = "https://unverified.example.test"
        XCTAssertEqual(model.beginWebSetup()?.absoluteString, service.deployment.description)
        XCTAssertEqual(model.setupWebReturn, .awaitingReturn)
        let before = await service.bootstrapAttempts
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: false, authenticated: false))
        await model.returnFromWebSetup().value
        XCTAssertEqual(model.setupWebReturn, .finished)
        XCTAssertEqual(model.selectedSavedHub?.id, hub.id)
        XCTAssertEqual(model.phase, .authentication(.signIn))
        await model.returnFromWebSetup().value
        let after = await service.bootstrapAttempts, events = await service.events
        XCTAssertEqual(after, before + 1)
        XCTAssertFalse(events.contains("login")); XCTAssertFalse(events.contains("setup"))
    }

    // An unfinished web wizard remains explicit; a foreground event cannot claim it finished.
    func testIncompleteWebSetupRetainsAddressAndPermitsExplicitReopen() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: true, authenticated: false))
        model.address = service.deployment.description; await model.connectAddress().value
        _ = model.beginWebSetup(); await model.returnFromWebSetup().value
        XCTAssertEqual(model.setupWebReturn, .incomplete)
        XCTAssertEqual(model.phase, .authentication(.setupAdministrator))
        XCTAssertEqual(model.snapshot?.deployment, service.deployment)
        XCTAssertEqual(model.beginWebSetup()?.absoluteString, service.deployment.description)
        XCTAssertEqual(model.setupWebReturn, .awaitingReturn)
    }

    // A browser return after leaving a hub cannot issue a new read or route the next connection.
    func testWebSetupReturnAfterHubExitDoesNotDispatch() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: true, setupRequired: true, authenticated: false))
        model.address = service.deployment.description; await model.connectAddress().value
        _ = model.beginWebSetup()
        let before = await service.bootstrapAttempts
        model.cancel(); await model.returnFromWebSetup().value
        let after = await service.bootstrapAttempts
        XCTAssertEqual(after, before)
        XCTAssertEqual(model.setupWebReturn, .none)
        XCTAssertNil(model.beginWebSetup())
        XCTAssertEqual(model.phase, .picker)
    }
}

extension ConnectionModelTests {
    // A callback from a replaced sheet must not cancel its successor while bootstrap is in flight.
    func testOldPresentationDismissalCannotCancelNewConnectionAttempt() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        await service.blockBootstrap()
        let oldPresentation = model.beginOnboardingPresentation()
        let replacement = model.beginOnboardingPresentation()
        XCTAssertNotEqual(oldPresentation, replacement)
        model.address = service.deployment.description
        let attempt = model.connectAddress(); await service.waitForBootstrap()
        model.dismissOnboardingPresentation(oldPresentation)
        XCTAssertEqual(model.phase, .checking); XCTAssertTrue(model.busy)
        await service.releaseBootstrap(); await attempt.value
        XCTAssertEqual(model.phase, .connected)
        XCTAssertNotNil(model.snapshot)
    }

    // A successful login removes its sheet too; dismissal may not revoke its retained live service.
    func testSuccessfulConnectionDismissalKeepsTheConnectedHub() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let presentation = model.beginOnboardingPresentation()
        model.address = service.deployment.description; await model.connectAddress().value
        let before = await service.events.filter { $0 == "disconnect" }.count
        model.dismissOnboardingPresentation(presentation)
        XCTAssertEqual(model.phase, .connected); XCTAssertNotNil(model.snapshot)
        let after = await service.events.filter { $0 == "disconnect" }.count
        XCTAssertEqual(after, before)
    }
}


extension ConnectionModelTests {
    func testKnownOfflineHubPublishesOnlyProtectedRememberedComposeIdentity() async throws {
        let service = try OnboardingService(), model = model(service)
        let proof = ComposePrincipalProof(deployment: service.deployment, installationID: "installation",
            principalID: "verified-user", connectionID: UUID(), verifiedOnline: false)
        await service.supplyComposePrincipal(proof); await service.failBootstrap(.networkUnavailable)
        await model.selectSaved(.init(deployment: service.deployment, alias: "Arbitrary alias", installationID: "installation")).value
        XCTAssertEqual(model.phase, .unreachable)
        XCTAssertEqual(model.composePrincipal, proof)
        model.cancel(); XCTAssertNil(model.composePrincipal)
    }
    func testCatalogAliasAndUnauthenticatedUsernameNeverSelectComposeBuffer() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.failBootstrap(.networkUnavailable)
        model.username = "admin"
        await model.selectSaved(.init(deployment: service.deployment, alias: "admin", installationID: "installation")).value
        XCTAssertNil(model.composePrincipal)
    }
    func testOnlineComposeProofPublicationAndForgetAreScopedToCurrentConnection() async throws {
        let service = try OnboardingService(usingDemoDeployment: true), model = model(service)
        await service.chooseAuth(.init(enabled: true, setupRequired: false, authenticated: true, authKind: "mobile"))
        let proof = ComposePrincipalProof(deployment: service.deployment, installationID: "installation",
            principalID: "verified-user", connectionID: UUID(), verifiedOnline: true)
        await service.supplyComposePrincipal(proof)
        await model.selectSaved(.init(deployment: service.deployment, alias: "Hub", installationID: "installation")).value
        XCTAssertEqual(model.phase, .connected); XCTAssertEqual(model.composePrincipal, proof)
        await model.forgetSignIn(); XCTAssertNil(model.composePrincipal)
    }
    func testWrongDeploymentProtectedProofCannotPublishUnderSelectedHub() async throws {
        let service = try OnboardingService(), model = model(service)
        let wrong = try DeploymentURL("https://other.example.com")
        await service.supplyComposePrincipal(.init(deployment: wrong, installationID: "installation",
            principalID: "verified-user", connectionID: UUID(), verifiedOnline: false))
        await service.failBootstrap(.networkUnavailable)
        await model.selectSaved(.init(deployment: service.deployment, alias: "Hub", installationID: "installation")).value
        XCTAssertNil(model.composePrincipal)
    }
}


extension ConnectionModelTests {
    func testCancelledOfflineLookupCannotPublishPreviousHubProof() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.supplyComposePrincipal(.init(deployment: service.deployment, installationID: "installation",
            principalID: "verified-user", connectionID: UUID(), verifiedOnline: false))
        await service.failBootstrap(.networkUnavailable); await service.blockComposeProof()
        let selecting = model.selectSaved(.init(deployment: service.deployment, alias: "Hub", installationID: "installation"))
        await service.waitForComposeProof(); model.cancel(); await service.releaseComposeProof(); await selecting.value
        XCTAssertEqual(model.phase, .picker); XCTAssertNil(model.composePrincipal)
    }
}


extension ConnectionModelTests {
    // DraftScene must consume this route so a user-owned form is not removed during bootstrap.
    func testActiveOnboardingRootRouteSurvivesCheckingAndAuthRequired() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.blockBootstrap()
        let presentation = model.attachOnboardingPresentation()
        model.address = service.deployment.description
        let selecting = model.connectAddress(); await service.waitForBootstrap()
        let visibleWhileChecking = model.shouldPresentOnboarding
        await service.releaseBootstrap(); await selecting.value
        XCTAssertTrue(visibleWhileChecking, "The actual root must retain enrollment's presenter while checking")
        XCTAssertEqual(model.phase, .authentication(.signIn)); XCTAssertNotNil(model.snapshot)
        XCTAssertTrue(model.shouldPresentOnboarding)
        // A legitimate host reattachment is distinct from explicitly replacing the presentation.
        model.password = "still-current-secret"
        let reattached = model.attachOnboardingPresentation()
        XCTAssertEqual(reattached, presentation)
        XCTAssertEqual(model.phase, .authentication(.signIn)); XCTAssertNotNil(model.snapshot)
        XCTAssertEqual(model.password, "still-current-secret")
        model.dismissOnboardingPresentation(presentation)
        XCTAssertEqual(model.phase, .picker); XCTAssertNil(model.snapshot); XCTAssertEqual(model.password, "")
    }

    func testColdSavedHubRootRouteKeepsCheckingAndUnreachableShell() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.blockBootstrap()
        let hub = SavedServer(deployment: service.deployment, alias: "Restoring hub", installationID: "installation")
        let restoring = model.selectSaved(hub); await service.waitForBootstrap()
        let visibleWhileChecking = model.shouldPresentOnboarding
        await service.releaseBootstrap(); await restoring.value
        XCTAssertFalse(visibleWhileChecking, "Cold restoration retains the connecting/cached shell")
        await service.failBootstrap(.networkUnavailable)
        await model.selectSaved(hub).value
        XCTAssertEqual(model.phase, .unreachable); XCTAssertFalse(model.shouldPresentOnboarding)
        XCTAssertEqual(model.selectedSavedHub?.id, hub.id)
    }

    func testOnboardingRootRouteHandsConnectedHubToShell() async throws {
        let service = try OnboardingService(), model = model(service)
        await service.chooseAuth(AuthStatus(enabled: false, setupRequired: false, authenticated: false))
        let presentation = model.attachOnboardingPresentation()
        model.address = service.deployment.description; await model.connectAddress().value
        XCTAssertEqual(model.phase, .connected); XCTAssertFalse(model.shouldPresentOnboarding)
        let before = await service.events.filter { $0 == "disconnect" }.count
        model.dismissOnboardingPresentation(presentation)
        XCTAssertEqual(model.phase, .connected); XCTAssertNotNil(model.snapshot)
        let after = await service.events.filter { $0 == "disconnect" }.count
        XCTAssertEqual(after, before)
    }

    func testAttachDoesNotReplaceButExplicitBeginStillRetiresTheOldForm() async throws {
        let service = try OnboardingService(), model = model(service)
        let first = model.attachOnboardingPresentation()
        model.address = service.deployment.description; await model.connectAddress().value
        model.password = "retired-secret"; model.setupToken = "retired-proof"
        let replacement = model.beginOnboardingPresentation()
        XCTAssertNotEqual(first, replacement)
        XCTAssertEqual(model.password, ""); XCTAssertEqual(model.setupToken, ""); XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.attachOnboardingPresentation(), replacement)
        await model.connectAddress().value
        model.password = "replacement-secret"
        model.dismissOnboardingPresentation(first)
        XCTAssertEqual(model.phase, .authentication(.signIn)); XCTAssertEqual(model.password, "replacement-secret")
        model.dismissOnboardingPresentation(replacement)
        XCTAssertEqual(model.phase, .picker); XCTAssertEqual(model.password, "")
        XCTAssertNotEqual(model.attachOnboardingPresentation(), replacement, "A dismissed scope cannot be reattached")
    }
}
