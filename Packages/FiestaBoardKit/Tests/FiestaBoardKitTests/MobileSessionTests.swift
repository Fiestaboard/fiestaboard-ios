import XCTest
@testable import FiestaBoardKit

@MainActor final class MobileSessionTests: XCTestCase {
    let a = try! DeploymentURL("https://board.test/a")
    let b = try! DeploymentURL("https://board.test/b")

    func testDeviceLoginUsesPhoneMetadataAndBearerNeverCookies() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.path.hasSuffix("/auth/device/login") {
                return (200, ["Set-Cookie": "fiestaboard_session=ignored; Path=/"], Data(#"{"access_token":"fb_mob_test-fixture-only","token_type":"Bearer","expires_in":3600,"session_id":"session-a","scope":"control"}"#.utf8))
            }
            return (200, [:], try BootstrapTests.body("auth_authenticated"))
        }
        let service = LiveFiestaBoardService(deployment: a, transport: URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self]))
        _ = try await service.login(username: "contract_admin", password: "fixture-password")
        XCTAssertEqual(log.requests[0].url!.path, "/a/api/auth/device/login")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(body["client_id"] as? String, "fiestaboard-ios")
        XCTAssertNotNil(body["device_name"] as? String)
        XCTAssertNotNil(body["app_version"] as? String)
        XCTAssertNil(body["remember_me"])
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_test-fixture-only")
        XCTAssertTrue(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
    }

    func testSavedHubsKeepOnlyOneActiveAndNeverPersistSecretsInMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cx-i5-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedHubsStore(file: directory.appendingPathComponent("hubs.json"))
        let first = try SavedHub(deployment: a, name: "Kitchen", installationID: "install-a")
        let second = try SavedHub(deployment: b, name: "Studio", installationID: "install-b")
        try await store.save(first, makeActive: true)
        try await store.save(second, makeActive: true)
        let snapshot = try await store.snapshot()
        XCTAssertEqual(snapshot.hubs.count, 2)
        XCTAssertEqual(snapshot.activeHub, second)
        let reopened = SavedHubsStore(file: directory.appendingPathComponent("hubs.json"))
        let restored = try await reopened.snapshot()
        XCTAssertEqual(restored, snapshot)
        try await store.remove(b)
        let removed = try await store.snapshot()
        XCTAssertNil(removed.activeHub)
        XCTAssertEqual(removed.hubs, [first])
    }

    func testDateAndHTTPDateRetryAfterAreExposedWithoutReplayingRequest() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            return (429, ["Date":"Wed, 01 Jan 2025 00:00:00 GMT", "Retry-After":"Wed, 01 Jan 2025 00:00:07 GMT"], Data("{}".utf8))
        }
        let t = URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self])
        do { _ = try await t.send(APIRequest(path: ["boards"])) ; XCTFail("Expected throttling") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .rateLimited(retryAfterSeconds: 7)) }
        XCTAssertEqual(log.requests.count, 1)
        let date = await t.lastServerDate
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1735689600))
    }
}

extension MobileSessionTests {
    private var recordedDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CX_MOBILE_FIXTURES"] { return URL(fileURLWithPath: path) }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/Fixtures")
    }
    func testRecordedMobileRepliesDecode() async throws {
        let data = try Data(contentsOf: recordedDirectory.appendingPathComponent("device-login.json"))
        let token = try JSONDecoder().decode(MobileTokenReply.self, from: data)
        XCTAssertTrue(token.isValid)
        let status = try JSONDecoder().decode(AuthStatus.self, from: Data(contentsOf: recordedDirectory.appendingPathComponent("auth-status-mobile.json")))
        XCTAssertTrue(status.authenticated)
        XCTAssertEqual(status.username, "contract_admin")
        XCTAssertEqual(status.bootstrapPhase, .ready)
        struct Source: Decodable {
            struct Response: Decodable { let file: String; let status: Int; let headers: [String:String] }
            let responses: [Response]
        }
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: recordedDirectory.appendingPathComponent("SOURCE.json")))
        for name in ["device-login-invalid", "device-login-locked", "device-session-expired", "device-session-revoked"] {
            let entry = try XCTUnwrap(source.responses.first { $0.file == name + ".json" })
            let body = try Data(contentsOf: recordedDirectory.appendingPathComponent(entry.file))
            FixtureURLProtocol.handler = { _ in (entry.status, entry.headers, body) }
            let transport = URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self])
            let request = name.hasPrefix("device-login") ? APIRequest(.post, path: ["auth", "device", "login"]) : APIRequest(path: ["boards"])
            do { _ = try await transport.send(request); XCTFail("Expected actual recorded error: \(name)") }
            catch {
                let expected: FiestaBoardError = name == "device-login-invalid" ? .invalidCredentials : name == "device-login-locked" ? .rateLimited(retryAfterSeconds: entry.headers["retry-after"].flatMap(Int.init)) : .unauthenticated
                XCTAssertEqual(error as? FiestaBoardError, expected, name)
            }
        }
    }
    func testRevocationClearsOnlyThatHubsBearerAndRememberedToken() async throws {
        let vault = MemorySessionVault()
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.lastPathComponent == "login" { return (200, [:], MobileFixture.reply("hub-a")) }
            return (401, [:], Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let t = URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self], vault: vault)
        await t.configureSessionPersistence(rememberMe: true, installationID: "install-a")
        _ = try await t.send(APIRequest(.post, path: ["auth", "device", "login"]))
        do { _ = try await t.send(APIRequest(path: ["boards"])); XCTFail("Expected signed out") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unauthenticated) }
        let stored = try await vault.load(for: a)
        XCTAssertNil(stored)
        do { _ = try await t.send(APIRequest(path: ["boards"])) } catch {}
        XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Authorization"))
    }
    func testPairingClaimUsesPhoneMetadataAndSingleUseProofOnlyInBody() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.path.hasSuffix("/auth/pairing/claim") { return (200, [:], MobileFixture.reply("paired")) }
            return (200, [:], try BootstrapTests.body("auth_authenticated"))
        }
        let t = URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self])
        let service = LiveFiestaBoardService(deployment: a, transport: t, clientMetadata: .init(deviceName: "Studio iPad", appVersion: "2.3"))
        _ = try await service.claimPairing(code: "single-use-fixture-code", rememberMe: false)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body, ["pairing_code":"single-use-fixture-code","client_id":"fiestaboard-ios","device_name":"Studio iPad","app_version":"2.3"])
        XCTAssertNil(log.requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_paired")
    }
    func testForeignTokenScopeAndUnsafeHeaderNeverInstallCredential() async throws {
        for replacement in ["fb_tv_foreign", "fb_mob_bad\r\nCookie:secret"] {
            let object: [String: Any] = ["access_token":replacement,"token_type":"Bearer","expires_in":3600,"session_id":"fixture","scope":"control"]
            let data = try JSONSerialization.data(withJSONObject: object)
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], request.url!.lastPathComponent == "login" ? data : Data("{}".utf8)) }
            let t = URLSessionTransport(deployment: a, protocolClasses: [FixtureURLProtocol.self])
            do { _ = try await t.send(APIRequest(.post, path: ["auth", "device", "login"])); XCTFail("Expected invalid credential") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
            _ = try await t.send(APIRequest(path: ["boards"]))
            XCTAssertNil(log.requests.last?.value(forHTTPHeaderField: "Authorization"))
        }
    }
}

extension MobileSessionTests {
    func testQueuedMutationCannotAcquireReplacementSessionAfterWaitingForHubBudget() async throws {
        let gate = DeferredTransportResponse()
        DeferredTransportURLProtocol.coordinator = gate
        let budget = HubRequestBudget(limit: 1)
        let t = URLSessionTransport(deployment: a, protocolClasses: [DeferredTransportURLProtocol.self], requestBudget: budget)
        let first = Task { try await t.send(APIRequest(path: ["boards"])) }
        await gate.waitUntilPending()
        let queued = Task { try await t.send(APIRequest(.post, path: ["pages"])) }
        while await budget.waitingCount == 0 { await Task.yield() }
        await t.resetSession()
        gate.release()
        do { _ = try await first.value; XCTFail("Expected retired read") } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        do { _ = try await queued.value; XCTFail("Expected queued mutation retirement") } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        XCTAssertEqual(gate.authorizations.count, 1, "Queued retired mutation must never reach the wire")
    }
}

extension MobileSessionTests {
    func testStoredCredentialUsesTheSameTokenAndSessionValidationAsLogin() throws {
        let reply = try JSONDecoder().decode(MobileTokenReply.self, from: MobileFixture.reply())
        let valid = try MobileSession(reply: reply)
        let bytes = try XCTUnwrap(valid.persisted(deployment: a, installationID: "install-a", connectionID: UUID()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for (key, value) in [("accessToken","fb_mob_"), ("sessionID", "bad\nidentifier"), ("sessionID",String(repeating:"a",count:257))] {
            var changed = object
            var credential = try XCTUnwrap(changed["session"] as? [String: Any])
            credential[key] = value
            changed["session"] = credential
            let corrupted = try JSONSerialization.data(withJSONObject: changed)
            XCTAssertNil(MobileSession.restore(corrupted, deployment: a, installationID: "install-a"), key)
        }
    }
}
