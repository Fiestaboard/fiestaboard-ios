import XCTest
@testable import FiestaBoardKit

@MainActor final class HomeContractTests: XCTestCase {
    private var directory: URL {
        if let path = ProcessInfo.processInfo.environment["CX_HOME_FIXTURES"] { return URL(fileURLWithPath: path) }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/Fixtures/Home")
    }
    private func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name + ".json")) }
    func testRecordedHomeRepliesDecode() throws {
        let board = try JSONDecoder().decode(BoardDetail.self, from: read("home-override"))
        let active = try JSONDecoder().decode(ActivePageStatus.self, from: read("active-override"))
        let payload = try XCTUnwrap(active.temporaryOverride)
        XCTAssertEqual(board.overrideExpiresAt, payload.expiresAt)
        XCTAssertEqual(board.overrideStartedAt, payload.startedAt)
        XCTAssertEqual(payload.boardID, board.summary.id)
        XCTAssertEqual(board.nextChangeReason, "override_ends")
        XCTAssertNotNil(board.nextChangeAt)
        XCTAssertEqual(board.nextPageID, payload.pageID)
        XCTAssertNil(board.health?.reachable, "No configured output is not proof of display reachability")
        let indefinite = try JSONDecoder().decode(BoardDetail.self, from: read("home-indefinite"))
        XCTAssertNil(indefinite.overrideExpiresAt)
        XCTAssertNotNil(indefinite.overrideStartedAt)
        let other = try JSONDecoder().decode(BoardDetail.self, from: read("other-display"))
        XCTAssertNil(other.overrideStartedAt)
        let canceled = try JSONDecoder().decode(ActivePageStatus.TemporaryOverride.self, from: read("override-canceled"))
        XCTAssertFalse(canceled.active)
        XCTAssertNil(canceled.startedAt)
    }
    func testCancelTargetsSelectedDisplayExactlyOnceAndRejectsUnsafeID() async throws {
        let log = RequestLog()
        let response = try read("override-cancel")
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], response) }
        let deployment = try DeploymentURL("https://hub.test/prefix")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        try await service.clearTemporaryOverride(boardID: "desk-note")
        XCTAssertEqual(log.requests.count, 1)
        XCTAssertEqual(log.requests[0].httpMethod, "DELETE")
        XCTAssertEqual(log.requests[0].url?.path, "/prefix/api/settings/temporary-override")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(log.requests[0].url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "board_id", value: "desk-note")])
        do { try await service.clearTemporaryOverride(boardID: "../primary"); XCTFail("Unsafe display ID must fail before dispatch") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
        XCTAssertEqual(log.requests.count, 1)
    }
    func testCancelUnknownOutcomeDoesNotRetry() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (503, [:], Data("{}".utf8)) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        do { try await service.clearTemporaryOverride(boardID: "kitchen"); XCTFail("Failure cannot acknowledge cancellation") }
        catch { XCTAssertNotNil(error as? FiestaBoardError) }
        XCTAssertEqual(log.requests.count, 1)
    }
}

extension HomeContractTests {
    func testHomeControlPolicyIsOperationScopedAndRequiresReadContract() {
        for operation in HomeControlOperation.allCases {
            XCTAssertTrue(CapabilityPolicy.allowsHomeControl(operation, version: "11.0.0-alpha.2", hasScopedStatus: true))
            XCTAssertTrue(CapabilityPolicy.allowsHomeControl(operation, version: "11.0.0-alpha.3", hasScopedStatus: true))
            XCTAssertFalse(CapabilityPolicy.allowsHomeControl(operation, version: "11.0.0-alpha.4", hasScopedStatus: true))
            XCTAssertFalse(CapabilityPolicy.allowsHomeControl(operation, version: "11.0.0-alpha.2", hasScopedStatus: false))
        }
        XCTAssertFalse(CapabilityPolicy.allows(.scalarControls, version: "11.0.0-alpha.2", isDev: false, optedIn: true), "The new audit never enables unrelated editor or scalar writes")
    }
    func testTimedPageUsesScopedRecordedOverrideContract() async throws {
        let log = RequestLog()
        let body = try read("override-timed")
        let source = try JSONSerialization.jsonObject(with: read("SOURCE")) as! [String: Any]
        let pageID = (source["scenario"] as! [String: String])["pageID"]!
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], body) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let receipt = try await service.selectHomePage(pageID: pageID, boardID: "cx-kitchen", durationMinutes: 180)
        XCTAssertEqual(receipt.boardID, "cx-kitchen")
        XCTAssertEqual(log.requests[0].url?.path, "/api/settings/temporary-override")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(sent["board_id"] as? String, "cx-kitchen")
        XCTAssertEqual(sent["page_id"] as? String, pageID)
        XCTAssertEqual(sent["duration_minutes"] as? Int, 180)
        XCTAssertEqual(sent["revert_mode"] as? String, "schedule")
        do { _ = try await service.selectHomePage(pageID: pageID, boardID: "cx-kitchen", durationMinutes: 0); XCTFail("Invalid duration must fail before dispatch") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
        XCTAssertEqual(log.requests.count, 1)
    }
}

extension HomeContractTests {
    func testActualV11MobileSelectionAndUnauthorizedReplies() async throws {
        let version = try JSONDecoder().decode(VersionInfo.self, from: read("HostV11/home-version"))
        XCTAssertEqual(version.runningVersion, "11.0.0-alpha.2")
        let source = try JSONSerialization.jsonObject(with: read("HostV11/SOURCE")) as! [String: Any]
        let pageID = (source["scenario"] as! [String: String])["pageID"]!
        let success = try read("HostV11/page-select")
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], success) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let receipt = try await service.selectHomePage(pageID: pageID, boardID: "cx-kitchen", durationMinutes: nil)
        XCTAssertEqual(receipt.sent, false, "Selection acknowledgement is not physical-send proof")
        XCTAssertEqual(log.requests[0].httpMethod, "PUT")
        XCTAssertEqual(log.requests[0].url?.path, "/api/v1/boards/cx-kitchen/active-page")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as? [String: String], ["page_id":pageID])
        let unauthorized = try read("HostV11/page-select-unauthorized")
        FixtureURLProtocol.handler = { request in log.append(request); return (401, [:], unauthorized) }
        do { _ = try await service.selectHomePage(pageID: pageID, boardID: "cx-kitchen", durationMinutes: nil); XCTFail("Actual mobile refusal cannot acknowledge selection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unauthenticated) }
        XCTAssertEqual(log.requests.count, 2, "No replay after the recorded 401")
    }
    func testHomeReadSentinelSurvivesRoundTripAndForeignReceiptFails() async throws {
        let detail = try JSONDecoder().decode(BoardDetail.self, from: read("home-manual"))
        XCTAssertTrue(detail.hasScopedHomeStatus)
        let roundTrip = try JSONDecoder().decode(BoardDetail.self, from: JSONEncoder().encode(detail))
        XCTAssertTrue(roundTrip.hasScopedHomeStatus)
        let source = try JSONSerialization.jsonObject(with: read("HostV11/SOURCE")) as! [String: Any]
        let pageID = (source["scenario"] as! [String: String])["pageID"]!
        let wrong = try read("HostV11/page-select")
        FixtureURLProtocol.handler = { _ in (200, [:], wrong) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        do { _ = try await service.selectHomePage(pageID: pageID, boardID: "cx-desk", durationMinutes: nil); XCTFail("Receipt for another display must not acknowledge the operation") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
    }
}

extension HomeContractTests {
    func testUntilCanceledUsesRecordedIndefiniteOverrideWithoutDuration() async throws {
        let source = try JSONSerialization.jsonObject(with: read("SOURCE")) as! [String: Any]
        let pageID = (source["scenario"] as! [String: String])["pageID"]!
        let response = try read("override-indefinite")
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], response) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let receipt = try await service.holdHomePage(pageID: pageID, boardID: "cx-kitchen", durationMinutes: nil)
        XCTAssertEqual(receipt.active,true)
        XCTAssertNil(receipt.expiresAt)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[0].httpBody)) as! [String: Any]
        XCTAssertNil(body["duration_minutes"], "Indefinite does not encode a zero-length timer")
        XCTAssertEqual(body["board_id"] as? String,"cx-kitchen")
        XCTAssertEqual(body["revert_mode"] as? String,"schedule")
    }
}

extension HomeContractTests {
    func testDurationBeyondActualEightHourContractFailsBeforeDispatch() async throws {
        let log = RequestLog()
        let response = try read("override-timed")
        let source = try JSONSerialization.jsonObject(with: read("SOURCE")) as! [String: Any]
        let page = (source["scenario"] as! [String: String])["pageID"]!
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], response) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        do { _ = try await service.holdHomePage(pageID: page, boardID: "cx-kitchen", durationMinutes: 481); XCTFail("The actual hub supports at most480minutes") }
        catch { XCTAssertEqual(error as? FiestaBoardError,.invalidTarget) }
        XCTAssertTrue(log.requests.isEmpty)
    }
}
