import XCTest
import Security
@testable import FiestaBoardKit

actor MemorySessionVault: SessionVault {
    private var entries: [DeploymentURL: Data] = [:]
    var fail = false
    private var paused = false
    private var saving: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func load(for deployment: DeploymentURL) throws -> Data? {
        if fail { throw URLError(.cannotOpenFile) }; return entries[deployment]
    }
    func save(_ data: Data, for deployment: DeploymentURL) async throws {
        if fail { throw URLError(.cannotWriteToFile) }
        if paused { await withCheckedContinuation { saving = $0; waiter?.resume(); waiter = nil } }
        entries[deployment] = data
    }
    func remove(for deployment: DeploymentURL) throws {
        if fail { throw URLError(.cannotRemoveFile) }; entries[deployment] = nil
    }
    func setFailure(_ value: Bool) { fail = value }
    func pauseSave() { paused = true }
    func waitForSave() async { if saving == nil { await withCheckedContinuation { waiter = $0 } } }
    func resumeSave() { paused = false; saving?.resume(); saving = nil }
}

@MainActor
final class SessionPersistenceTests: XCTestCase {
    let deployment = try! DeploymentURL("https://board.test/prefix")
    func transport(_ vault: MemorySessionVault, deployment: DeploymentURL? = nil) -> URLSessionTransport {
        URLSessionTransport(deployment: deployment ?? self.deployment, protocolClasses: [FixtureURLProtocol.self], vault: vault)
    }
    func fixture(cookie: String? = "fiestaboard_session=remembered; Path=/; Secure; Max-Age=3600") {
        FixtureURLProtocol.handler = { request in
            (200, request.url!.lastPathComponent == "login" ? cookie.map { ["Set-Cookie": $0] } ?? [:] : [:], Data("{}".utf8))
        }
    }
    func login(_ transport: URLSessionTransport) async throws {
        _ = try await transport.send(APIRequest(.post, path: ["auth", "login"]))
    }
    // Removing the consent or persistent-expiry guard must fail this test.
    func testNoConsentOrSessionCookieNeverPersists() async throws {
        for remember in [false, true] {
            let vault = MemorySessionVault(); let t = transport(vault)
            fixture(cookie: "fiestaboard_session=session; Path=/; Secure")
            await t.configureSessionPersistence(rememberMe: remember, installationID: "id-1")
            try await login(t)
            let stored = try await vault.load(for: deployment)
            XCTAssertNil(stored)
        }
    }
    func testPersistentCookieRoundTripsOnlyForExactDeploymentAndInstallation() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        try await login(t)
        let blob = try await vault.load(for: deployment)
        XCTAssertNotNil(blob)
        for id in ["", "id-2"] {
            let other = transport(vault)
            let restored = await other.restoreRememberedSession(observedInstallationID: id)
            XCTAssertFalse(restored)
        }
        // Restore rejection does not erase a credential owned by another window.
        let reopened = transport(vault)
        let restored = await reopened.restoreRememberedSession(observedInstallationID: "id-1")
        XCTAssertTrue(restored)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await reopened.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=remembered")
        for address in ["https://board.test/other", "https://board.test:8443/prefix", "https://other.test/prefix", "http://board.local/prefix"] {
            let wrong = try DeploymentURL(address, allowLocalHTTP: true)
            try await vault.save(blob!, for: wrong)
            let restored = await transport(vault, deployment: wrong).restoreRememberedSession(observedInstallationID: "id-1")
            XCTAssertFalse(restored)
        }
    }
    func testCorruptionExpiryForeignAndSecureCookiesAreRejected() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        let loaded = try await vault.load(for: deployment)
        let good = try XCTUnwrap(loaded)
        let json = try JSONSerialization.jsonObject(with: good) as! [String: Any]
        var variants = [Data("bad".utf8)]
        for (key, value) in [("version", 99 as Any), ("installationID", "different" as Any)] {
            var changed = json; changed[key] = value; variants.append(try JSONSerialization.data(withJSONObject: changed))
        }
        for (key, value) in [("domain", "foreign.test" as Any), ("expires", 0 as Any), ("name", "other" as Any), ("path", "relative" as Any)] {
            var changed = json; var cookies = changed["cookies"] as! [[String: Any]]
            cookies[0][key] = value; changed["cookies"] = cookies
            variants.append(try JSONSerialization.data(withJSONObject: changed))
        }
        for bad in variants {
            try await vault.save(bad, for: deployment)
            let restored = await transport(vault).restoreRememberedSession(observedInstallationID: "id-1")
            XCTAssertFalse(restored)
        }
    }
    func testMemoryOnlyNewLoginClearsRememberedMaterialAndOldWindowCannotEraseNewLogin() async throws {
        let vault = MemorySessionVault(); let old = transport(vault); fixture()
        await old.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(old)
        let new = transport(vault)
        await new.configureSessionPersistence(rememberMe: false, installationID: "id-1")
        let stored = try await vault.load(for: deployment)
            XCTAssertNil(stored)
        await new.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(new)
        await old.forgetRememberedSession()
        let storedAfter = try await vault.load(for: deployment)
        XCTAssertNotNil(storedAfter)
    }
    func testForgetOrdersAfterSuspendedSaveAndLateResponseCannotResurrect() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        await vault.pauseSave()
        let pending = Task { try await self.login(t) }
        await vault.waitForSave()
        let forget = Task { await t.forgetRememberedSession() }
        // The save is suspended in storage, not a timing-dependent network sleep.
        while await t.sessionPersistenceState().rememberMe { await Task.yield() }
        await vault.resumeSave()
        try await pending.value; await forget.value
        let stored = try await vault.load(for: deployment)
            XCTAssertNil(stored)
        let state = await t.sessionPersistenceState()
        XCTAssertFalse(state.rememberMe)
    }
    func testUnavailableStorageDoesNotRejectAcknowledgedLoginAndKeepsMemoryCookie() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        await vault.setFailure(true)
        try await login(t)
        let state = await t.sessionPersistenceState()
        XCTAssertEqual(state.warning, .unavailable)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=remembered")
    }
}

extension SessionPersistenceTests {
    func testServiceRestoreRevalidatesAndRevokedAccountLosesCookieAndWriteAccess() async throws {
        for revoked in [false, true] {
            let vault = MemorySessionVault(); let seeded = transport(vault); fixture()
            await seeded.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(seeded)
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in
                log.append(request)
                switch request.url!.lastPathComponent {
                case "health": return (200, [:], try BootstrapTests.body("health"))
                case "discover": return (200, [:], try BootstrapTests.body("discover_disabled"))
                case "status":
                    let authenticated = !revoked && request.value(forHTTPHeaderField: "Cookie") != nil
                    let body = authenticated ? "auth_authenticated" : "auth_enabled"
                    return (200, [:], try BootstrapTests.body(body))
                default: throw URLError(.badURL)
                }
            }
            let t = transport(vault); let service = LiveFiestaBoardService(deployment: deployment, transport: t)
            let restored = try await service.restoreRememberedSession(observedInstallationID: "id-1")
            XCTAssertEqual(restored, !revoked)
            XCTAssertEqual(log.requests.filter { $0.url!.lastPathComponent == "discover" }.count, 2)
            XCTAssertNil(log.requests.first?.value(forHTTPHeaderField: "Cookie"))
            if revoked {
                let stored = try await vault.load(for: deployment)
                XCTAssertNil(stored)
                let state = await service.sessionPersistenceState()
                XCTAssertFalse(state.rememberMe)
            }
        }
    }
    func testAcknowledgedServiceLoginStillSucceedsWhenCleanupAndSaveFail() async throws {
        let vault = MemorySessionVault(); let t = transport(vault)
        let service = LiveFiestaBoardService(deployment: deployment, transport: t)
        FixtureURLProtocol.handler = { request in
            switch request.url!.lastPathComponent {
            case "health": return (200, [:], try BootstrapTests.body("health"))
            case "discover": return (200, [:], try BootstrapTests.body("discover_disabled"))
            case "status": return (200, [:], try BootstrapTests.body("auth_authenticated"))
            case "login": return (200, ["Set-Cookie": "fiestaboard_session=private; Max-Age=3600; Path=/; Secure"], Data(#"{"status":"ok"}"#.utf8))
            default: throw URLError(.badURL)
            }
        }
        _ = try await service.bootstrap()
        await vault.setFailure(true)
        let auth = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: true)
        XCTAssertTrue(auth.authenticated)
        let state = await service.sessionPersistenceState()
        XCTAssertEqual(state.warning, .unavailable)
    }
    func testFailedLogoutClearsLocalStateAndReportsPendingRevocation() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        let service = LiveFiestaBoardService(deployment: deployment, transport: t)
        FixtureURLProtocol.handler = { _ in throw URLError(.networkConnectionLost) }
        do { try await service.logout(); XCTFail("Expected unreachable remote revocation") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        let stored = try await vault.load(for: deployment); XCTAssertNil(stored)
        let state = await service.sessionPersistenceState()
        XCTAssertEqual(state.warning, .remoteRevocationPending)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Cookie"))
    }
    func testLocalDisconnectRetainsRememberedMaterialButClearsActiveCookies() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        let service = LiveFiestaBoardService(deployment: deployment, transport: t)
        await service.disconnect()
        let stored = try await vault.load(for: deployment); XCTAssertNotNil(stored)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Cookie"))
    }
}

/// Suspends one response without blocking URLSession's delegate queue or using sleeps.
private final class PersistenceResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: PersistenceURLProtocol?
    private var waiter: CheckedContinuation<Void, Never>?
    private var entries: [URLRequest] = []
    let endpoint: String
    init(endpoint: String) { self.endpoint = endpoint }
    var requests: [URLRequest] { lock.withLock { entries } }
    func receive(_ value: PersistenceURLProtocol) {
        let shouldPause = value.request.url!.lastPathComponent == endpoint
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            entries.append(value.request)
            if shouldPause { pending = value; let result = waiter; waiter = nil; return result }
            return nil
        }
        if shouldPause { waiting?.resume(); return }
        let path = value.request.url!.lastPathComponent
        if path == "login" {
            value.respond(headers: ["Set-Cookie": "fiestaboard_session=new; Path=/; Secure; Max-Age=3600"], data: Data(#"{"status":"ok"}"#.utf8))
        } else {
            let name = path == "health" ? "health" : path == "discover" ? "discover_disabled" : "auth_authenticated"
            value.respond(headers: [:], data: try! BootstrapTests.body(name))
        }
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { if pending != nil { return true }; waiter = continuation; return false }
            if ready { continuation.resume() }
        }
    }
    func release(cookie: String) {
        let value = lock.withLock { let result = pending; pending = nil; return result }
        value?.respond(headers: ["Set-Cookie": cookie], data: Data(#"{"status":"ok"}"#.utf8))
    }
}
private final class PersistenceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var gate: PersistenceResponseGate!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.gate.receive(self) }
    override func stopLoading() {}
    func respond(headers: [String: String], data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
}
extension SessionPersistenceTests {
    // An old response must not acquire consent granted to a newer attempt.
    func testLateLoginResponseCannotUseReenabledConsent() async throws {
        let vault = MemorySessionVault(); let gate = PersistenceResponseGate(endpoint: "login")
        PersistenceURLProtocol.gate = gate
        let t = URLSessionTransport(deployment: deployment, protocolClasses: [PersistenceURLProtocol.self], vault: vault)
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        let pending = Task { try await self.login(t) }
        await gate.wait()
        await t.configureSessionPersistence(rememberMe: false, installationID: "id-1")
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        gate.release(cookie: "fiestaboard_session=old; Path=/; Secure; Max-Age=3600")
        try await pending.value
        let stored = try await vault.load(for: deployment); XCTAssertNil(stored)
    }
    func testLateOldLogoutCannotEraseNewRememberedLogin() async throws {
        let vault = MemorySessionVault(); let gate = PersistenceResponseGate(endpoint: "logout")
        PersistenceURLProtocol.gate = gate
        let t = URLSessionTransport(deployment: deployment, protocolClasses: [PersistenceURLProtocol.self], vault: vault)
        let service = LiveFiestaBoardService(deployment: deployment, transport: t)
        _ = try await service.bootstrap()
        _ = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: true)
        let pending = Task { try await service.logout() }
        await gate.wait()
        _ = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: true)
        gate.release(cookie: "fiestaboard_session=; Path=/; Max-Age=0")
        do { try await pending.value; XCTFail("Expected stale logout") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let stored = try await vault.load(for: deployment); XCTAssertNotNil(stored)
        _ = try await service.authStatus()
        XCTAssertEqual(gate.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=new")
    }
}

private final class SecurityCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String: Any]] = []
    func append(_ query: [String: Any]) { lock.withLock { calls.append(query) } }
    var queries: [[String: Any]] { lock.withLock { calls } }
}
extension SessionPersistenceTests {
    func testKeychainBoundaryUsesDeploymentAccountDeviceOnlyAndNeverSynchronizes() async throws {
        let recorder = SecurityCallRecorder()
        let boundary = SessionSecurity(copy: { query in recorder.append(query); return (errSecItemNotFound, nil) },
            add: { query in recorder.append(query); return errSecSuccess },
            update: { query, changes in recorder.append(query.merging(changes) { _, b in b }); return errSecItemNotFound },
            delete: { query in recorder.append(query); return errSecItemNotFound })
        let vault = KeychainSessionVault(service: "test-isolated-call-boundary", security: boundary)
        let loaded = try await vault.load(for: deployment); XCTAssertNil(loaded)
        try await vault.save(Data("opaque".utf8), for: deployment)
        try await vault.remove(for: deployment)
        for query in recorder.queries {
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "https://board.test/prefix")
            XCTAssertEqual(query[kSecAttrService as String] as? String, "test-isolated-call-boundary")
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        }
        let add = recorder.queries.first { $0[kSecValueData as String] != nil }!
        XCTAssertEqual(add[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
    func testLockedKeychainIsBoundedFailureAndRestoreNeverUsesCookie() async throws {
        let boundary = SessionSecurity(copy: { _ in (errSecInteractionNotAllowed, nil) },
            add: { _ in errSecInteractionNotAllowed }, update: { _, _ in errSecInteractionNotAllowed },
            delete: { _ in errSecInteractionNotAllowed })
        let vault = KeychainSessionVault(service: "test-locked-call-boundary", security: boundary)
        let t = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self], vault: vault)
        let restored = await t.restoreRememberedSession(observedInstallationID: "id-1")
        XCTAssertFalse(restored)
        let state = await t.sessionPersistenceState(); XCTAssertEqual(state.warning, .unavailable)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Cookie"))
    }
    func testReplacedPersistentCookieIsWhatRestartRestores() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        FixtureURLProtocol.handler = { _ in (200, ["Set-Cookie": "fiestaboard_session=rotated; Path=/; Secure; Max-Age=3600"], Data("{}".utf8)) }
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        let fresh = transport(vault)
        let restored = await fresh.restoreRememberedSession(observedInstallationID: "id-1"); XCTAssertTrue(restored)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await fresh.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=rotated")
    }
}

extension SessionPersistenceTests {
    func testLogoutAcknowledgementAndLocalCleanupFailureRemainSeparate() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        await vault.setFailure(true)
        let service = LiveFiestaBoardService(deployment: deployment, transport: t)
        FixtureURLProtocol.handler = { _ in (200, [:], Data(#"{"status":"ok"}"#.utf8)) }
        try await service.logout()
        let state = await service.sessionPersistenceState()
        XCTAssertEqual(state.warning, .unavailable)
        XCTAssertTrue(state.cleanupPending)
        await vault.setFailure(false)
        await service.forgetRememberedSession()
        let retried = await service.sessionPersistenceState()
        XCTAssertFalse(retried.cleanupPending)
        let stored = try await vault.load(for: deployment); XCTAssertNil(stored)
    }
    func testRevokedCookieWith401IsRemovedAfterFreshRestoreCheck() async throws {
        let vault = MemorySessionVault(); let t = transport(vault); fixture()
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        FixtureURLProtocol.handler = { request in
            switch request.url!.lastPathComponent {
            case "health": return (200, [:], try BootstrapTests.body("health"))
            case "discover": return (200, [:], try BootstrapTests.body("discover_disabled"))
            default:
                if request.value(forHTTPHeaderField: "Cookie") != nil { return (401, [:], Data("{}".utf8)) }
                return (200, [:], try BootstrapTests.body("auth_enabled"))
            }
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport(vault))
        let restored = try await service.restoreRememberedSession(observedInstallationID: "id-1")
        XCTAssertFalse(restored)
        let stored = try await vault.load(for: deployment); XCTAssertNil(stored)
    }
}

extension SessionPersistenceTests {
    func testSecondWindowReplacementOrdersBehindOldSaveAndOwnsFinalCredential() async throws {
        let vault = MemorySessionVault(); let old = transport(vault); fixture()
        await old.configureSessionPersistence(rememberMe: true, installationID: "id-1")
        await vault.pauseSave()
        let oldLogin = Task { try await self.login(old) }
        await vault.waitForSave()
        let new = transport(vault)
        let replacement = Task { await new.configureSessionPersistence(rememberMe: true, installationID: "id-1") }
        while !(await new.sessionPersistenceState().rememberMe) { await Task.yield() }
        await vault.resumeSave()
        try await oldLogin.value; await replacement.value
        fixture(cookie: "fiestaboard_session=new-window; Path=/; Secure; Max-Age=3600")
        try await login(new)
        await old.forgetRememberedSession()
        let fresh = transport(vault)
        let restored = await fresh.restoreRememberedSession(observedInstallationID: "id-1"); XCTAssertTrue(restored)
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        _ = try await fresh.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=new-window")
    }
}

extension SessionPersistenceTests {
    func testSchemeBindingDoesNotDependOnSecureCookieOrDifferentHost() async throws {
        let https = try DeploymentURL("https://board.local/prefix")
        let http = try DeploymentURL("http://board.local/prefix", allowLocalHTTP: true)
        let vault = MemorySessionVault(); let t = transport(vault, deployment: https)
        fixture(cookie: "fiestaboard_session=remembered; Path=/; Max-Age=3600")
        await t.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(t)
        let loaded = try await vault.load(for: https); let blob = try XCTUnwrap(loaded)
        try await vault.save(blob, for: http)
        let restored = await transport(vault, deployment: http).restoreRememberedSession(observedInstallationID: "id-1")
        XCTAssertFalse(restored)
    }
    func testMissingStableIdentityKeepsSuccessfulLoginOnlyInMemory() async throws {
        for identity: String? in [nil, "", "   "] {
            let vault = MemorySessionVault(); let t = transport(vault); fixture()
            await t.configureSessionPersistence(rememberMe: true, installationID: identity); try await login(t)
            let stored = try await vault.load(for: deployment); XCTAssertNil(stored)
            let state = await t.sessionPersistenceState(); XCTAssertEqual(state.warning, .identityRequired)
        }
    }
}

/// Uses the real coordinator for every operation, but suspends the final ownership
/// result after it has been computed. This models a delayed cross-actor return.
private actor RestoreOwnershipGate: SessionVaultCoordinating {
    private let base = SessionVaultCoordinator()
    private var waiting: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    func claim(_ vault: any SessionVault, for deployment: DeploymentURL, replacing: Bool) async -> SessionVaultCoordinator.Lease {
        await base.claim(vault, for: deployment, replacing: replacing)
    }
    func retire(_ lease: SessionVaultCoordinator.Lease) async -> SessionVaultCoordinator.Lease? { await base.retire(lease) }
    func perform(_ lease: SessionVaultCoordinator.Lease, operation: @escaping @Sendable () async throws -> Data?) async throws -> Data? {
        try await base.perform(lease, operation: operation)
    }
    func isCurrent(_ lease: SessionVaultCoordinator.Lease) async -> Bool {
        let result = await base.isCurrent(lease)
        await withCheckedContinuation { blocked = $0; waiting?.resume(); waiting = nil }
        return result
    }
    func waitForOwnershipResult() async {
        if blocked != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func releaseOwnershipResult() { blocked?.resume(); blocked = nil }
}

/// All requests, cookies, and storage remain real; only return from rejected
/// restore's local cleanup is held while a new authentication transition runs.
private actor RejectedRestoreCleanupTransport: APITransport {
    let base: URLSessionTransport
    private var waiting: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    private var pauseNextForget = true
    init(base: URLSessionTransport) { self.base = base }
    func send(_ request: APIRequest) async throws -> APIResponse { try await base.send(request) }
    func resetSession() async { await base.resetSession() }
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {
        await base.configureSessionPersistence(rememberMe: rememberMe, installationID: installationID)
    }
    func restoreRememberedSession(observedInstallationID: String) async -> Bool {
        await base.restoreRememberedSession(observedInstallationID: observedInstallationID)
    }
    func sessionPersistenceState() async -> SessionPersistenceState { await base.sessionPersistenceState() }
    func forgetRememberedSession() async {
        await base.forgetRememberedSession()
        guard pauseNextForget else { return }
        pauseNextForget = false
        await withCheckedContinuation { blocked = $0; waiting?.resume(); waiting = nil }
    }
    func waitForCleanup() async {
        if blocked != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func releaseCleanup() { blocked?.resume(); blocked = nil }
}

extension SessionPersistenceTests {
    func testFinalRestoreOwnershipResultCannotOutliveForgetResetOrLogout() async throws {
        for action in ["forget", "reset", "logout"] {
            let vault = MemorySessionVault(); let seed = transport(vault); fixture()
            await seed.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(seed)
            let gate = RestoreOwnershipGate()
            let t = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self], vault: vault, coordinator: gate)
            let restoring = Task { await t.restoreRememberedSession(observedInstallationID: "id-1") }
            await gate.waitForOwnershipResult()
            if action == "forget" { await t.forgetRememberedSession() }
            else if action == "reset" { await t.resetSession() }
            else {
                FixtureURLProtocol.handler = { _ in (200, [:], Data(#"{"status":"ok"}"#.utf8)) }
                try await LiveFiestaBoardService(deployment: deployment, transport: t).logout()
            }
            await gate.releaseOwnershipResult()
            let restored = await restoring.value
            XCTAssertFalse(restored, action)
            let state = await t.sessionPersistenceState()
            XCTAssertFalse(state.rememberMe, action); XCTAssertFalse(state.restored, action)
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
            _ = try await t.send(APIRequest(path: ["auth", "status"]))
            XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Cookie"), action)
        }
    }

    func testRejectedRestoreCleanupCannotResetNewLoginForAnyRejectionReason() async throws {
        for reason in ["unauthenticated", "identityMismatch", "notReady"] {
            let vault = MemorySessionVault(); let seed = transport(vault); fixture()
            await seed.configureSessionPersistence(rememberMe: true, installationID: "id-1"); try await login(seed)
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in
                log.append(request)
                let path = request.url!.lastPathComponent
                if path == "health" { return (200, [:], try BootstrapTests.body("health")) }
                if path == "login" {
                    return (200, ["Set-Cookie": "fiestaboard_session=new; Path=/; Secure; Max-Age=3600"], Data(#"{"status":"ok"}"#.utf8))
                }
                if path == "discover" {
                    var identity = try JSONSerialization.jsonObject(with: BootstrapTests.body("discover_disabled")) as! [String: Any]
                    if reason == "identityMismatch", log.requests.filter({ $0.url!.lastPathComponent == "discover" }).count == 2 {
                        identity["id"] = "changed-installation"
                    }
                    return (200, [:], try JSONSerialization.data(withJSONObject: identity))
                }
                let replacement = request.value(forHTTPHeaderField: "Cookie") == "fiestaboard_session=new"
                if replacement { return (200, [:], try BootstrapTests.body("auth_authenticated")) }
                if reason == "identityMismatch" { return (200, [:], try BootstrapTests.body("auth_authenticated")) }
                if reason == "notReady" {
                    var status = try JSONSerialization.jsonObject(with: BootstrapTests.body("auth_authenticated")) as! [String: Any]
                    status["setup_required"] = true
                    return (200, [:], try JSONSerialization.data(withJSONObject: status))
                }
                return (200, [:], try BootstrapTests.body("auth_enabled"))
            }
            let base = transport(vault)
            let gated = RejectedRestoreCleanupTransport(base: base)
            let service = LiveFiestaBoardService(deployment: deployment, transport: gated)
            let restoring = Task { try await service.restoreRememberedSession(observedInstallationID: "id-1") }
            await gated.waitForCleanup()
            let replacement = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: true)
            XCTAssertTrue(replacement.authenticated, reason)
            await gated.releaseCleanup()
            do { _ = try await restoring.value; XCTFail("Expected superseded restore: \(reason)") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession, reason) }
            let current = try await service.authStatus()
            XCTAssertTrue(current.authenticated, reason)
            XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Cookie"), "fiestaboard_session=new", reason)
            let stored = try await vault.load(for: deployment); XCTAssertNotNil(stored, reason)
        }
    }
}
