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
