import XCTest
import FiestaBoardDocuments
@testable import FiestaBoardKit

@MainActor final class ComposeServiceTests: XCTestCase {
    private func fixture(_ file: String, _ name: String) throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/\(file).json"))
        let corpus = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        return try XCTUnwrap((corpus["records"] as? [[String: Any]])?.first { $0["case"] as? String == name })
    }
    private func setup(outcome: String = "formatted-timed-primary", protocolName: String? = "compose-intent-v1", budget: HubRequestBudget? = nil) async throws -> (LiveFiestaBoardService, ComposeRequest, RequestLog) {
        let recorded = try fixture("compose-authenticated", outcome)
        var board = try fixture("compose-authenticated", "primary-capability")["response"] as! [String: Any]
        board["compose_protocol"] = protocolName
        let response = try JSONSerialization.data(withJSONObject: recorded["response"]!)
        let responseStatus = recorded["status"] as! Int
        let poll = try JSONSerialization.data(withJSONObject: fixture("compose-authenticated", "uuid-poll")["response"]!)
        let boardBytes = try JSONSerialization.data(withJSONObject: board)
        let boardsBytes = try JSONSerialization.data(withJSONObject: ["boards": [board], "total": 1])
        let preview = try JSONSerialization.data(withJSONObject: fixture("operations-authenticated", "preview-primary-formatting")["response"]!)
        let created = try JSONSerialization.data(withJSONObject: fixture("operations-authenticated", "create-hall-1")["response"]!)
        let readback = try JSONSerialization.data(withJSONObject: fixture("operations-authenticated", "created-readback-hall-1")["response"]!)
        let log = RequestLog(), deployment = try DeploymentURL("https://board.test/prefix")
        FixtureURLProtocol.handler = { request in
            log.append(request)
            switch request.url!.lastPathComponent {
            case "health": return (200, [:], try BootstrapTests.body("health"))
            case "discover": return (200, [:], try BootstrapTests.body("discover_disabled"))
            case "login": return (200, [:], MobileFixture.reply("compose-operation"))
            case "session": return (200, [:], Data(#"{"status":"ok"}"#.utf8))
            case "status":
                var value = try JSONSerialization.jsonObject(with: BootstrapTests.body("auth_authenticated")) as! [String: Any]
                let authenticated = request.value(forHTTPHeaderField: "Authorization") != nil
                value["authenticated"] = authenticated; value["auth_kind"] = authenticated ? "mobile" as Any : NSNull()
                return (200, [:], try JSONSerialization.data(withJSONObject: value))
            case "version": return (200, [:], Data(#"{"package_version":"11.0.0-alpha.3","build_version":"dev","running_version":"11.0.0-alpha.3","is_dev":true}"#.utf8))
            case "boards": return (200, [:], boardsBytes)
            case "compose": return (responseStatus, [:], response)
            case "render": return (200, [:], preview)
            case "pages": return (201, [:], created)
            default:
                if request.url!.path.contains("/pages/") { return (200, [:], readback) }
                if request.url!.path.contains("/compose/") { return (200, [:], poll) }
                return (200, [:], boardBytes)
            }
        }
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self], requestBudget: budget))
        _ = try await service.bootstrap()
        _ = try await service.login(username: "contract_admin", password: "fixture-password", rememberMe: false)
        let status = try await service.connect(allowCandidateWrites: true)
        XCTAssertEqual(status.access, .readOnly, "Compose operation audit must not widen generic writes")
        let target = try BoardTarget(deployment: deployment, boardID: board["id"] as! String)
        _ = try await service.board(target)
        let observed = await service.composePrincipal(), proof = try XCTUnwrap(observed)
        let original = recorded["request"] as! [String: Any]
        let request = ComposeRequest(principal: proof, target: target, requestID: UUID(uuidString: original["request_id"] as! String)!,
            text: "HELLO {{red:WORLD}}", lineMetadata: [.init(alignment: "center", wrap: false)],
            geometry: .flagship, duration: .minutes(120), silence: .hold)
        return (service, request, log)
    }
    func testCapturedAuthenticatedComposeDispatchesOnceAndPreservesReceipt() async throws {
        let (service, request, log) = try await setup()
        let receipt = try await service.sendCompose(request)
        XCTAssertEqual(receipt.state, .sent); XCTAssertEqual(receipt.requestID, request.requestID)
        do { _ = try await service.sendCompose(request); XCTFail("A consumed UUID must never dispatch again") } catch {}
        let writes = log.requests.filter { $0.url?.lastPathComponent == "compose" }
        XCTAssertEqual(writes.count, 1)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(writes.first?.httpBody)) as! [String: Any]
        XCTAssertEqual(body["template"] as? [String], ["HELLO {{red:WORLD}}"])
        XCTAssertEqual(body["silence"] as? String, "hold")
    }
    func testMissingOrUnknownComposeProtocolDoesNotWidenGenericWrites() async throws {
        for value in [nil, "future-compose"] as [String?] {
            let (service, request, log) = try await setup(protocolName: value)
            do { _ = try await service.sendCompose(request); XCTFail("Unknown capability cannot dispatch") } catch {}
            XCTAssertTrue(log.requests.filter { $0.url?.lastPathComponent == "compose" }.isEmpty)
        }
    }
    func testActualErrorReceiptShapesRemainDistinctAndNeverReplay() async throws {
        for (name, state) in [("paused", ComposeReceipt.State.rejected), ("rate-limit", .notSent), ("partial", .partial), ("unknown", .unknown)] {
            let (service, request, log) = try await setup(outcome: name)
            let receipt = try await service.sendCompose(request)
            XCTAssertEqual(receipt.state, state, name)
            XCTAssertEqual(log.requests.filter { $0.url?.lastPathComponent == "compose" }.count, 1)
        }
    }
    func testCapturedOldConnectionCannotDispatchAfterLogout() async throws {
        let (service, request, log) = try await setup()
        try await service.logout()
        do { _ = try await service.sendCompose(request); XCTFail("Retired authority cannot send") } catch {}
        XCTAssertTrue(log.requests.filter { $0.url?.lastPathComponent == "compose" }.isEmpty)
    }
    func testComposePreviewIsReadOnlyAndExpiredDurationDoesNotBlockAuthoring() async throws {
        let (service, current, log) = try await setup()
        let request = ComposeRequest(principal: current.principal, target: current.target, text: "HELLO", lineMetadata: [.init(alignment: "right", wrap: true)],
            geometry: .flagship, duration: .until(.distantPast), silence: .hold)
        let preview = try await service.previewCompose(request)
        XCTAssertFalse(preview.lines.isEmpty)
        XCTAssertTrue(log.requests.filter { $0.url?.lastPathComponent == "compose" || $0.url?.lastPathComponent == "live" }.isEmpty)
        let reads = log.requests.filter { $0.url?.lastPathComponent == "render" }
        XCTAssertEqual(reads.count, 1)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(reads.first?.httpBody)) as! [String: Any]
        XCTAssertEqual(body["board_id"] as? String, current.target.boardID)
        XCTAssertEqual(body["template"] as? [String], ["HELLO"])
        XCTAssertEqual(body["diagnostics"] as? Bool, true)
        XCTAssertEqual((body["preview"] as? [String: String])?["data"], "cached")
        XCTAssertNil(body["duration"]); XCTAssertNil(body["silence"])
    }
}


private actor ComposeBudgetHold {
    private var held: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { held = $0; ready?.resume(); ready = nil } }
    func wait() async { if held == nil { await withCheckedContinuation { ready = $0 } } }
    func release() { held?.resume(); held = nil }
}

extension ComposeServiceTests {
    func testForgetWhileComposeWaitsForTransportBudgetPreventsWireDispatch() async throws {
        let budget = HubRequestBudget(limit: 1)
        let (service, request, log) = try await setup(budget: budget)
        let hold = ComposeBudgetHold()
        let occupying = Task { try await budget.run { await hold.hold() } }
        await hold.wait()
        let sending = Task { try await service.sendCompose(request) }
        while await budget.waitingCount == 0 { await Task.yield() }
        await service.forgetRememberedSession()
        await hold.release(); try await occupying.value
        do { _ = try await sending.value; XCTFail("Forgotten authority must retire a queued intent") } catch {}
        XCTAssertTrue(log.requests.filter { $0.url?.lastPathComponent == "compose" }.isEmpty, "Rechecking only after the response cannot undo physical dispatch")
    }
}


extension ComposeServiceTests {
    func testUUIDOutcomeReadNeverReplaysMutation() async throws {
        let (service, request, log) = try await setup()
        _ = try await service.sendCompose(request)
        let receipt = try await service.composeOutcome(request)
        XCTAssertEqual(receipt.requestID, request.requestID); XCTAssertEqual(receipt.state, .sent)
        XCTAssertEqual(log.requests.filter { $0.url?.lastPathComponent == "compose" }.count, 1)
        let polls = log.requests.filter { $0.url?.path.contains("/compose/") == true }
        XCTAssertEqual(polls.count, 1); XCTAssertEqual(polls.first?.httpMethod, "GET")
    }
}


extension ComposeServiceTests {
    func testSaveAsPageOnlyCreatesAndReadsBackCapturedContentWithoutDisplayMutation() async throws {
        let (service, current, log) = try await setup()
        let request = ComposeRequest(principal: current.principal, target: current.target, text: "KEEP EXACT\nSECOND",
            lineMetadata: [.init(alignment: "right", wrap: true), .init(alignment: "center", wrap: false)],
            geometry: .flagship, duration: .until(.distantPast), silence: .hold)
        let generic = await service.pageManagementCapability()
        XCTAssertFalse(generic.canCreate); XCTAssertFalse(generic.canDelete)
        let receipt = try await service.saveComposePage(name: "Captured hall-1", request: request)
        XCTAssertEqual(receipt.page.template, ["KEEP EXACT", "SECOND"])
        do { _ = try await service.saveComposePage(name: "Captured hall-1", request: request); XCTFail("An uncertain or consumed create must never replay") } catch {}
        let mutations = log.requests.filter { $0.httpMethod == "POST" && $0.url?.lastPathComponent != "login" }
        XCTAssertEqual(mutations.count, 1); XCTAssertEqual(mutations.first?.url?.lastPathComponent, "pages")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(mutations.first?.httpBody)) as! [String: Any]
        XCTAssertEqual(body["type"] as? String, "template"); XCTAssertEqual(body["template"] as? [String], ["KEEP EXACT", "SECOND"])
        XCTAssertNil(body["duration"]); XCTAssertNil(body["silence"]); XCTAssertNil(body["board_id"])
        XCTAssertNil(body["request_id"]); XCTAssertNil(body["protocol"]); XCTAssertNil(body["prepared_at"])
        XCTAssertEqual(log.requests.filter { $0.url?.path.contains("/pages/") == true && $0.httpMethod == "GET" }.count, 1)
        XCTAssertTrue(log.requests.filter { $0.url?.path.contains("/compose") == true || $0.url?.path.contains("active-page") == true || $0.url?.path.contains("schedule") == true }.isEmpty)
    }
}
