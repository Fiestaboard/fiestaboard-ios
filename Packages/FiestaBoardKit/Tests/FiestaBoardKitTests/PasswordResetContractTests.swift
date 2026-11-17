import XCTest
@testable import FiestaBoardKit

@MainActor final class PasswordResetContractTests: XCTestCase {
    private let deployment = try! DeploymentURL("https://board.test/prefix")
    private struct Source: Decodable {
        struct Response: Decodable { let file: String; let status: Int; let headers: [String: String] }
        let responses: [Response]
    }
    private func recorded(_ name: String) throws -> (Int, [String: String], Data) {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent("Tests/Fixtures/Onboarding")
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: directory.appendingPathComponent("SOURCE.json")))
        let entry = try XCTUnwrap(source.responses.first { $0.file == name + ".json" })
        return (entry.status, entry.headers, try Data(contentsOf: directory.appendingPathComponent(entry.file)))
    }
    private func transport(vault: (any SessionVault)? = nil) -> URLSessionTransport {
        URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self], vault: vault)
    }

    // An accidental login/readback, extra identity field or normalized password would violate the public contract.
    func testResetSendsExactPublicBodyAndAcknowledgesWithoutSigningIn() async throws {
        let reply = try recorded("reset-code-after-weak")
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return reply }
        let service: any FiestaBoardService = LiveFiestaBoardService(deployment: deployment, transport: transport())
        let password = "e\u{301}e\u{301}e\u{301}e\u{301}"
        try await service.resetPassword(code: "fb_reset_fixture", newPassword: password)
        XCTAssertEqual(log.requests.count, 1, "Reset must neither log in nor dispatch an automatic read")
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/prefix/api/auth/password-reset")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["code", "new_password"])
        XCTAssertEqual(body["code"], "fb_reset_fixture")
        XCTAssertEqual(Array(try XCTUnwrap(body["new_password"]).utf8), Array(password.utf8))
    }

    // Public proof must not become a general way to bypass bearer/context checks.
    func testResetContextRejectsOtherRoutesAndMethodsBeforeDispatch() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        let client = transport()
        for (method, path) in [(APIRequest.Method.get, ["auth", "password-reset"]),
                               (.post, ["auth", "device", "login"]), (.post, ["boards"])] {
            do {
                _ = try await client.send(APIRequest(method, path: path, context: .passwordReset))
                XCTFail("Reset context must be scoped to its one public POST")
            } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        }
        XCTAssertTrue(log.requests.isEmpty)
    }

    // A retained or concurrently established bearer must never be included with owner-terminal proof.
    func testResetContextOmitsAnExistingBearer() async throws {
        let reply = try recorded("reset-code-after-weak")
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.path.hasSuffix("/device/login") { return (200, [:], MobileFixture.reply("reset-context")) }
            return reply
        }
        let client = transport()
        _ = try await client.send(APIRequest(.post, path: ["auth", "device", "login"]))
        _ = try await client.send(APIRequest(path: ["boards"]))
        _ = try await client.send(APIRequest(.post, path: ["auth", "password-reset"], context: .passwordReset, cachePolicy: .noStore))
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_reset-context")
        XCTAssertNil(log.requests[2].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(log.requests[2].value(forHTTPHeaderField: "Cookie"))
    }

    // Invalid, reused, replaced and expired proof has one safe outcome, never raw server text.
    func testRecordedInvalidGrantVariantsHaveTheSameSafeError() async throws {
        for name in ["reset-invalid-code", "reset-code-reused", "reset-superseded-code", "reset-expired-code"] {
            let reply = try recorded(name), log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); return reply }
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport())
            do { try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password"); XCTFail(name) }
            catch {
                XCTAssertEqual(error as? FiestaBoardError, .invalidResetCode, name)
                XCTAssertFalse(error.localizedDescription.contains("fb_reset_fixture"))
            }
            XCTAssertEqual(log.requests.count, 1, name)
        }
    }

    // Validation points to the reset field; a real advertised cooldown survives without a retry.
    func testRecordedValidationAndSharedLockoutRemainDistinct() async throws {
        for (name, expected) in [("reset-weak-password", FiestaBoardError.validation(fields: [.newPassword])),
                                 ("reset-password-too-long", .validation(fields: [.newPassword])),
                                 ("reset-shared-lockout", .rateLimited(retryAfterSeconds: 60))] {
            let reply = try recorded(name), log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); return reply }
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport())
            do { try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password"); XCTFail(name) }
            catch { XCTAssertEqual(error as? FiestaBoardError, expected, name) }
            XCTAssertEqual(log.requests.count, 1, name)
        }
    }

    // A token-shaped reply or unconfirmed status must not install authority or announce success.
    func testMalformedAcknowledgementsNeverBecomeCredentials() async throws {
        let tokenReply = try recorded("device-login-after-reset")
        for reply in [(200, Data("{}".utf8)), (202, Data(#"{"status":"ok"}"#.utf8)),
                      (200, Data(#"{"status":"pending"}"#.utf8)), (200, tokenReply.2)] {
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in
                log.append(request)
                return request.url!.path.hasSuffix("password-reset") ? (reply.0, [:], reply.1) : (200, [:], Data("{}".utf8))
            }
            let client = transport(), service = LiveFiestaBoardService(deployment: deployment, transport: client)
            do { try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password"); XCTFail("Unconfirmed reset") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
            XCTAssertEqual(log.requests.count, 1)
            _ = try await client.send(APIRequest(path: ["boards"]))
            XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Authorization"))
        }
    }

    // Even cancellation after dispatch can hide a successful reset; never replay it.
    func testLostOrCancelledResetIsOneUnknownAttempt() async throws {
        for code in [URLError.Code.networkConnectionLost, .cancelled] {
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); throw URLError(code) }
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport())
            do { try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password"); XCTFail("Unknown outcome") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
            XCTAssertEqual(log.requests.count, 1)
        }
    }

    // Successful reset revokes this hub's remembered proof, preserving a different saved hub.
    func testConfirmedResetForgetsOnlyThisHubsRememberedCredential() async throws {
        let reply = try recorded("reset-code-after-weak"), vault = MemorySessionVault()
        let other = try DeploymentURL("https://board.test/other")
        try await vault.save(Data("unrelated-saved-hub".utf8), for: other)
        FixtureURLProtocol.handler = { request in
            request.url!.path.hasSuffix("/device/login") ? (200, [:], MobileFixture.reply("reset-vault")) : reply
        }
        let client = transport(vault: vault)
        await client.configureSessionPersistence(rememberMe: true, installationID: "fixture-install")
        _ = try await client.send(APIRequest(.post, path: ["auth", "device", "login"]))
        let before = try await vault.load(for: deployment)
        XCTAssertNotNil(before)
        let service = LiveFiestaBoardService(deployment: deployment, transport: client)
        try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password")
        let removed = try await vault.load(for: deployment), retained = try await vault.load(for: other)
        XCTAssertNil(removed)
        XCTAssertEqual(retained, Data("unrelated-saved-hub".utf8))
    }

    // A late reset response belongs to its old session, never a replacement intention.
    func testDisconnectRejectsAnOutstandingResetCompletion() async throws {
        let gate = DeferredTransportResponse()
        DeferredTransportURLProtocol.coordinator = gate
        let client = URLSessionTransport(deployment: deployment, protocolClasses: [DeferredTransportURLProtocol.self])
        let service = LiveFiestaBoardService(deployment: deployment, transport: client)
        let reset = Task { try await service.resetPassword(code: "fb_reset_fixture", newPassword: "new-fixture-password") }
        await gate.waitUntilPending()
        await service.disconnect()
        gate.release()
        do { try await reset.value; XCTFail("Expected old reset rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
}
