import XCTest
@testable import FiestaBoardKit

func fixture(_ name: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
}

@MainActor
final class ServiceTests: XCTestCase {
    let deployment = try! DeploymentURL("https://board.test/prefix")
    func service(version: String = "10.0.0", log: RequestLog = RequestLog(), message: String? = nil, status: Int = 200) -> LiveFiestaBoardService {
        FixtureURLProtocol.handler = { request in
            log.append(request)
            let path = request.url!.path
            if path.hasSuffix("version") {
                return (200, [:], Data("{\"package_version\":\"10.0.0\",\"build_version\":\"test\",\"running_version\":\"\(version)\",\"is_dev\":false}".utf8))
            }
            if path.hasSuffix("message") { return (status, [:], Data((message ?? #"{"sent":true,"board_id":"board-2","characters":[[1,2,3,4],[5,6,7,8]],"text":"ABCD\nEFGH","expires_at":null,"reason":null,"silenced":false,"held":false}"#).utf8)) }
            if path.hasSuffix("active-page") { return (200, [:], Data(#"{"board_id":"board-2","page_id":"page-selected","sent":false,"silenced":false,"reason":null,"error":"private error secret","warnings":[]}"#.utf8)) }
            if path.hasSuffix("boards") { return (200, [:], fixture("boards")) }
            if path.hasSuffix("board-2") { return (200, [:], fixture("board")) }
            if path.hasSuffix("pages") { return (200, [:], fixture("pages")) }
            if path.hasSuffix("page-selected") { return (200, [:], fixture("page")) }
            return (200, [:], fixture("auth"))
        }
        return LiveFiestaBoardService(deployment: deployment,
             transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
    }
    func testCandidateRequiresOptInAndOnlyExactRunningVersionCanWrite() async throws {
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        for version in ["9.14.9", "10.0.1", "10.0.0-beta.1", "unknown"] {
            let log = RequestLog(), service = service(version: version, log: log)
            let status = try await service.connect(allowCandidateWrites: true)
            XCTAssertEqual(status.access, .readOnly)
            do { _ = try await service.sendText("Hello", to: target); XCTFail("Expected write gate") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .writesDisabled) }
            XCTAssertFalse(log.requests.contains { $0.httpMethod != "GET" })
        }
        let service = service()
        let status = try await service.connect(allowCandidateWrites: false)
        XCTAssertEqual(status.access, .readOnly)
        do { _ = try await service.sendText("Hello", to: target); XCTFail("Expected opt-in") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .writesDisabled) }
    }
    func testMutationUsesImmutableConcreteTargetAndExactPayload() async throws {
        let log = RequestLog(), service = service(log: log)
        XCTAssertThrowsError(try BoardTarget(deployment: deployment, boardID: "primary"))
        _ = try await service.connect(allowCandidateWrites: true)
        let result = try await service.sendText("HELLO", to: BoardTarget(deployment: deployment, boardID: "board-2"))
        XCTAssertEqual(result.disposition, .accepted)
        XCTAssertEqual(log.requests.last!.url!.path, "/prefix/api/v1/boards/board-2/message")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests.last!.httpBody)) as! [String: String]
        XCTAssertEqual(body, ["text": "HELLO"])
        for target in [try BoardTarget(deployment: deployment, boardID: "missing"),
                       try BoardTarget(deployment: DeploymentURL("https://board.test/other"), boardID: "board-2")] {
            do { _ = try await service.sendText("Oops", to: target); XCTFail("Expected target refusal") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
        }
        XCTAssertEqual(log.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testHeldAndSelectionStoredDoNotClaimDelivery() async throws {
        let service = service(message: #"{"sent":false,"board_id":"board-2","characters":[[1,2,3,4],[5,6,7,8]],"text":"ABCD\nEFGH","expires_at":null,"reason":"Held","silenced":true,"held":true}"#, status: 202)
        _ = try await service.connect(allowCandidateWrites: true)
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        let held = try await service.sendText("HELLO", to: target)
        XCTAssertEqual(held.disposition, .held)
        XCTAssertFalse(held.sent)
        let selected = try await service.selectPage(id: "page-selected", on: target)
        XCTAssertEqual(selected.disposition, .selectionStored)
        XCTAssertTrue(selected.deliveryFailed)
        XCTAssertFalse(selected.sent)
    }
    func testReadFixtureKeepsSelectionExpectedAndReportedOutputSeparate() async throws {
        let service = service()
        _ = try await service.connect(allowCandidateWrites: false)
        let detail = try await service.board(BoardTarget(deployment: deployment, boardID: "board-2"))
        XCTAssertEqual(detail.summary.rows, 2)
        XCTAssertEqual(detail.summary.cols, 4)
        XCTAssertEqual(detail.activePageID, "page-selected")
        XCTAssertEqual(detail.resolvedPageID, "page-actual")
        XCTAssertEqual(detail.characters, [[1,2,3,4],[5,6,7,8]])
        XCTAssertEqual(detail.expectedCharacters, [[8,7,6,5],[4,3,2,1]])
        XCTAssertEqual(detail.renderingSupport, .flapGrid)
        let pages = try await service.pages()
        let page = try await service.page(id: "page-selected")
        XCTAssertEqual(pages.first?.id, "page-selected")
        XCTAssertEqual(page.gridCols, 4)
    }
    func testMalformedBoardGeometryCannotEnableWritesAndPixelOutputIsUnsupported() async throws {
        var json = try JSONSerialization.jsonObject(with: fixture("board")) as! [String: Any]
        json["charset"] = "led_3x5"
        json["layers"] = [["x":0,"y":0,"width":1,"height":1,"rgba":"AAAAAA=="]]
        let pixel = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(pixel.renderingSupport, .unsupported)
        XCTAssertEqual(pixel.layers?.first?.width, 1)
        json["characters"] = [[1,2]]
        let invalid = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try invalid.validate())
        let service = service()
        FixtureURLProtocol.handler = { _ in (200, [:], Data("{}".utf8)) }
        do { _ = try await service.connect(allowCandidateWrites: true); XCTFail("Expected shape refusal") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
    }
}

actor SuspendedTransport: APITransport {
    var resetCount = 0
    private var pending: CheckedContinuation<APIResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func send(_ request: APIRequest) async throws -> APIResponse {
        if request.path == ["auth", "device", "session"] {
            return await withCheckedContinuation { continuation in
                pending = continuation; waiter?.resume(); waiter = nil
            }
        }
        let data: Data
        if request.path == ["auth", "device", "login"] { data = MobileFixture.reply("memory") }
        else { data = fixture("auth") }
        return APIResponse(status: 200, data: data)
    }
    func waitUntilBlocked() async {
        if pending == nil { await withCheckedContinuation { waiter = $0 } }
    }
    func release() { pending?.resume(returning: APIResponse(status: 200, data: Data(#"{"status":"ok"}"#.utf8))); pending = nil }
    func resetSession() { resetCount += 1 }
}

extension ServiceTests {
    func testLateLogoutCannotClearNewLoginSession() async throws {
        let transport = SuspendedTransport()
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let oldLogout = Task { try await service.logout() }
        await transport.waitUntilBlocked()
        let status = try await service.login(username: "demo", password: "never-persist-me")
        XCTAssertTrue(status.authenticated)
        await transport.release()
        do { try await oldLogout.value; XCTFail("Expected stale logout") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let resets = await transport.resetCount
        XCTAssertEqual(resets, 1, "Old logout must not reset the replacement session")
    }

    func testLoginPayloadOmitsBrowserPersistenceAndLogoutClearsBearer() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.path.hasSuffix("login") {
                return (200, [:], MobileFixture.reply("memory"))
            }
            if request.url!.path.hasSuffix("session") {
                return (200, ["Set-Cookie":"fiestaboard_session=; Path=/; Max-Age=0"], Data(#"{"status":"ok"}"#.utf8))
            }
            return (200, [:], fixture("auth"))
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let auth = try await service.login(username: "demo", password: "secret")
        XCTAssertTrue(auth.authenticated)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests.first?.httpBody)) as! [String: Any]
        XCTAssertNil(body["remember_me"])
        XCTAssertEqual(body["username"] as? String, "demo")
        XCTAssertEqual(body["password"] as? String, "secret")
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_memory")
        try await service.logout()
        _ = try await service.authStatus()
        XCTAssertNil(log.requests.last!.value(forHTTPHeaderField: "Authorization"))
    }
}


extension ServiceTests {
    func testOlderReadShapeCanOmitAutoRestoreWithoutGainingWrites() async throws {
        var object = try JSONSerialization.jsonObject(with: fixture("boards")) as! [String: Any]
        var boards = object["boards"] as! [[String: Any]]
        boards[0].removeValue(forKey: "auto_restore")
        object["boards"] = boards
        let olderBoards = try JSONSerialization.data(withJSONObject: object)
        FixtureURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("version") {
                return (200, [:], Data(#"{"package_version":"9.14.9","build_version":"old","running_version":"9.14.9","is_dev":false}"#.utf8))
            }
            return (200, [:], olderBoards)
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let status = try await service.connect(allowCandidateWrites: true)
        XCTAssertEqual(status.access, .readOnly)
        let results = try await service.boards()
        XCTAssertNil(results.first?.autoRestore)
    }
}

extension ServiceTests {
    func testOnboardingUsesExactBodiesScopedProofAndPublicReadback() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.lastPathComponent == "login" { return (200, [:], MobileFixture.reply()) }
            if request.httpMethod == "POST" {
                return (request.url!.lastPathComponent == "setup" ? 201 : 200, [:], Data(#"{"status":"ok","username":"contract_admin"}"#.utf8))
            }
            let name = log.requests.contains { $0.url!.lastPathComponent == "setup" } ? "auth_authenticated" : "auth_enabled"
            return (200, [:], try BootstrapTests.body(name))
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let chosen = try await service.setAuthenticationPreference(enabled: true, setupToken: "fixture-proof")
        XCTAssertEqual(chosen.bootstrapPhase, .setupAdministrator)
        let setup = try await service.setupAdministrator(username: "contract_admin", password: "fixture-password", setupToken: "fixture-proof")
        XCTAssertEqual(setup.bootstrapPhase, .ready)
        XCTAssertEqual(log.requests.map { $0.url!.lastPathComponent }, ["preference", "status", "setup", "login", "status"])
        let preference = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as! [String: Bool]
        XCTAssertEqual(preference, ["enabled": true])
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[2].httpBody)) as! [String: String]
        XCTAssertEqual(body, ["username": "contract_admin", "password": "fixture-password"])
        for index in [0, 2] { XCTAssertEqual(log.requests[index].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-proof") }
        for index in [1, 3] { XCTAssertNil(log.requests[index].value(forHTTPHeaderField: "Authorization")) }
        XCTAssertTrue(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-store" })
    }
    func testRememberMeIsExplicitAndNoOptionalLibraryReadFollowsLogin() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.httpMethod == "POST" { return (200, [:], MobileFixture.reply()) }
            return (200, [:], try BootstrapTests.body("auth_authenticated"))
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let status = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: true)
        XCTAssertEqual(status.bootstrapPhase, .ready)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as! [String: Any]
        XCTAssertNil(body["remember_me"])
        XCTAssertEqual(log.requests.map { $0.url!.lastPathComponent }, ["login", "status"])
    }
    func testAcknowledgedSetupWithFailedReadbackIsUnknownAndNeverReplayed() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.lastPathComponent == "login" { return (200, [:], MobileFixture.reply()) }
            if request.httpMethod == "POST" { return (201, [:], Data(#"{"status":"ok"}"#.utf8)) }
            throw URLError(.networkConnectionLost)
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        do { _ = try await service.setupAdministrator(username: "contract_admin", password: "fixture-password"); XCTFail("Expected unverified readback") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        XCTAssertEqual(log.requests.map { $0.httpMethod }, ["POST", "POST", "GET"])
    }
    func testMalformedMutationAcknowledgementDiffersFromMalformedRead() async throws {
        FixtureURLProtocol.handler = { _ in (200, [:], Data("{}".utf8)) }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        do { _ = try await service.login(username: "demo", password: "fixture-password"); XCTFail("Expected unknown mutation") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        do { _ = try await service.bootstrap(); XCTFail("Expected invalid read") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
    }
}
