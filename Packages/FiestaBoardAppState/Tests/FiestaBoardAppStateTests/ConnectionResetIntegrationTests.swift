import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

/// Real connection/service/transport integration; only the HTTP boundary is deterministic.
@MainActor final class ConnectionResetIntegrationTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func connected(_ fixture: ResetConnectionHTTP) async throws -> ConnectionModel {
        ResetConnectionURLProtocol.fixture = fixture
        let deployment = try DeploymentURL("https://board.test/prefix")
        let transport = URLSessionTransport(deployment: deployment, protocolClasses: [ResetConnectionURLProtocol.self])
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let model = ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: directory), discovery: ResetNoDiscovery(), preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in service })
        model.address = deployment.description
        await model.connectAddress().value
        XCTAssertEqual(model.phase, .authentication(.signIn))
        return model
    }
    private func fill(_ model: ConnectionModel) {
        model.resetCode = "fb_reset_fixture"
        model.resetNewPassword = "new-fixture-password"
        model.resetConfirmation = "new-fixture-password"
    }

    // Removing the explicit-success branch must leave this view in submitting or incorrectly open the shell.
    func testConfirmedResetKeepsHubAndUsernameWithoutAutomaticLogin() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-code-after-weak")
        let model = try await connected(fixture)
        let hub = try XCTUnwrap(model.selectedSavedHub)
        model.username = "retained-owner"; model.password = "old-secret"
        model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
        let attempt = model.submitPasswordReset()
        XCTAssertEqual(model.resetCode, ""); XCTAssertEqual(model.resetNewPassword, ""); XCTAssertEqual(model.resetConfirmation, "")
        XCTAssertEqual(model.password, "")
        await attempt.value
        XCTAssertEqual(model.passwordResetFlow?.phase, .passwordChanged)
        XCTAssertEqual(model.phase, .authentication(.signIn))
        XCTAssertEqual(model.selectedSavedHub?.id, hub.id)
        XCTAssertEqual(model.username, "retained-owner")
        XCTAssertNil(model.snapshotLease)
        XCTAssertEqual(fixture.paths.filter { $0.hasSuffix("/password-reset") }.count, 1)
        XCTAssertFalse(fixture.paths.contains { $0.hasSuffix("/device/login") })
        let readsBefore = fixture.paths.count
        model.finishPasswordReset()
        XCTAssertNil(model.passwordResetFlow)
        XCTAssertEqual(fixture.paths.count, readsBefore, "Returning to sign in must not fetch or sign in")
    }

    // A second UI submit while the original HTTP call is held must never dispatch another reset.
    func testPendingResetIsOneAttemptAndCancelRejectsItsLateSuccess() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-code-after-weak", deferred: true)
        let model = try await connected(fixture)
        model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
        let attempt = model.submitPasswordReset()
        await fixture.waitForReset()
        fill(model); await model.submitPasswordReset().value
        XCTAssertEqual(fixture.resetCount, 1)
        model.cancelPasswordReset()
        XCTAssertNil(model.passwordResetFlow)
        XCTAssertTrue(model.requiresStateCheck)
        fixture.release()
        await attempt.value
        XCTAssertNil(model.passwordResetFlow)
        XCTAssertEqual(model.phase, .authentication(.signIn))
        model.beginPasswordReset()
        XCTAssertNil(model.passwordResetFlow, "An uncertain reset requires an explicit state check before a new intent")
        XCTAssertEqual(fixture.resetCount, 1)
    }

    // Network failure after dispatch cannot turn into success or a replay after leaving the reset screen.
    func testUnknownResetOutcomeRequiresExplicitCheckAndNeverReplays() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-code-after-weak", failReset: true)
        let model = try await connected(fixture)
        model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
        await model.submitPasswordReset().value
        XCTAssertEqual(model.passwordResetFlow?.phase, .uncertain)
        XCTAssertTrue(model.requiresStateCheck)
        fill(model); await model.submitPasswordReset().value
        XCTAssertEqual(fixture.resetCount, 1)
        model.cancelPasswordReset(); model.beginPasswordReset()
        XCTAssertNil(model.passwordResetFlow)
        await model.checkServerState().value
        XCTAssertFalse(model.requiresStateCheck)
        XCTAssertEqual(fixture.resetCount, 1, "State check is read-only")
        model.beginPasswordReset()
        XCTAssertEqual(model.passwordResetFlow?.phase, .instructions)
    }

    // Invalid/used/expired/replaced proof shares one field state and cannot retain submitted secrets.
    func testRecordedInvalidCodesRemainSafeAndAllowExplicitReplacement() async throws {
        for name in ["reset-invalid-code", "reset-code-reused", "reset-expired-code", "reset-superseded-code"] {
            let fixture = try ResetConnectionHTTP(reply: name)
            let model = try await connected(fixture)
            model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
            await model.submitPasswordReset().value
            XCTAssertEqual(model.passwordResetFlow?.phase, .enterCode, name)
            XCTAssertEqual(model.passwordResetFlow?.invalidFields, [.code], name)
            XCTAssertFalse(model.requiresStateCheck, name)
            XCTAssertEqual(model.resetCode, ""); XCTAssertEqual(model.resetNewPassword, ""); XCTAssertEqual(model.resetConfirmation, "")
            XCTAssertEqual(model.message, FiestaBoardError.invalidResetCode.localizedDescription, name)
            XCTAssertEqual(fixture.resetCount, 1)
            model.cancel()
            XCTAssertNil(model.passwordResetFlow)
        }
    }

    // Reset shares the actual advertised IP cooldown with sign in while the help route remains available.
    func testResetRateLimitBlocksFurtherDispatchAndKeepsHelpAvailable() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-shared-lockout")
        let model = try await connected(fixture)
        model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
        await model.submitPasswordReset().value
        XCTAssertNotNil(model.loginRetryDeadline)
        XCTAssertFalse(model.requiresStateCheck)
        fill(model); await model.submitPasswordReset().value
        XCTAssertEqual(fixture.resetCount, 1)
        model.cancelPasswordReset(); model.beginPasswordReset()
        XCTAssertEqual(model.passwordResetFlow?.phase, .instructions)
    }

    // Server field validation must not be mislabeled as a bad code or unknown mutation.
    func testRecordedPasswordValidationHighlightsOnlyNewPassword() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-weak-password")
        let model = try await connected(fixture)
        model.beginPasswordReset(); model.enterPasswordResetCode(); fill(model)
        await model.submitPasswordReset().value
        XCTAssertEqual(model.passwordResetFlow?.phase, .enterCode)
        XCTAssertEqual(model.passwordResetFlow?.invalidFields, [.newPassword])
        XCTAssertFalse(model.requiresStateCheck)
        XCTAssertEqual(fixture.resetCount, 1)
    }

    // Invalid local input may never reach the actual transport, nor may stale fields survive a hub change.
    func testInvalidInputAndHubExitClearSecretsWithoutDispatch() async throws {
        let fixture = try ResetConnectionHTTP(reply: "reset-code-after-weak")
        let model = try await connected(fixture)
        model.beginPasswordReset(); model.enterPasswordResetCode()
        model.resetCode = ""; model.resetNewPassword = "short"; model.resetConfirmation = "different"
        await model.submitPasswordReset().value
        XCTAssertEqual(model.passwordResetFlow?.invalidFields, [.code, .newPassword, .confirmation])
        XCTAssertEqual(fixture.resetCount, 0)
        fill(model); model.cancel()
        XCTAssertNil(model.passwordResetFlow)
        XCTAssertEqual(model.resetCode, ""); XCTAssertEqual(model.resetNewPassword, ""); XCTAssertEqual(model.resetConfirmation, "")
        model.beginPasswordReset()
        XCTAssertNil(model.passwordResetFlow, "Reset needs a verified same-hub sign-in route")
    }
}

private struct ResetNoDiscovery: ServerDiscovering {
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> { AsyncThrowingStream { $0.finish() } }
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> { AsyncThrowingStream { $0.finish() } }
}

private final class ResetConnectionHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private let resetReply: (Int, [String: String], Data)
    private let deferred: Bool
    private let failReset: Bool
    private var requests: [String] = []
    private var pending: ResetConnectionURLProtocol?
    private var observers: [CheckedContinuation<Void, Never>] = []
    var paths: [String] { lock.withLock { requests } }
    var resetCount: Int { paths.filter { $0.hasSuffix("/password-reset") }.count }
    init(reply name: String, deferred: Bool = false, failReset: Bool = false) throws {
        struct Source: Decodable {
            struct Response: Decodable { let file: String; let status: Int; let headers: [String: String] }
            let responses: [Response]
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent("Tests/Fixtures/Onboarding")
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: directory.appendingPathComponent("SOURCE.json")))
        let response = try XCTUnwrap(source.responses.first { $0.file == name + ".json" })
        resetReply = (response.status, response.headers, try Data(contentsOf: directory.appendingPathComponent(response.file)))
        self.deferred = deferred; self.failReset = failReset
    }
    func handle(_ channel: ResetConnectionURLProtocol) {
        let path = channel.request.url!.path
        lock.withLock { requests.append(path) }
        if path.hasSuffix("/password-reset") {
            if failReset { channel.fail(); return }
            if deferred {
                let waiting = lock.withLock { pending = channel; let waiting = observers; observers = []; return waiting }
                waiting.forEach { $0.resume() }; return
            }
            channel.respond(resetReply); return
        }
        let body: String
        switch channel.request.url!.lastPathComponent {
        case "health": body = #"{"status":"ok","service_running":false,"version":"10.1.20"}"#
        case "discover": body = #"{"product":"FiestaBoard","version":"10.1.20","id":"reset-installation","name":"Test hub"}"#
        case "status": body = #"{"enabled":true,"setup_required":false,"authenticated":false,"mode":"enabled","first_run":false}"#
        default: channel.fail(); return
        }
        channel.respond((200, [:], Data(body.utf8)))
    }
    func waitForReset() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { if pending != nil { return true }; observers.append(continuation); return false }
            if ready { continuation.resume() }
        }
    }
    func release() {
        let channel = lock.withLock { let result = pending; pending = nil; return result }
        channel?.respond(resetReply)
    }
}

private final class ResetConnectionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: ResetConnectionHTTP!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.fixture.handle(self) }
    override func stopLoading() {}
    func fail() { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
    func respond(_ reply: (Int, [String: String], Data)) {
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: reply.1)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.2)
        client?.urlProtocolDidFinishLoading(self)
    }
}
