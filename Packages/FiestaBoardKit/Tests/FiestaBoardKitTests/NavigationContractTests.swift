import XCTest
@testable import FiestaBoardKit

@MainActor final class NavigationContractTests: XCTestCase {
    func testWebEditorPreservesDeploymentAndEncodesOnlyOneValidatedSegment() throws {
        let deployment = try DeploymentURL("https://board.test:8443/fiesta/base")
        let url = try XCTUnwrap(deployment.webEditorURL(pageID: "été ?#", isDemo: false))
        XCTAssertEqual(url.absoluteString, "https://board.test:8443/fiesta/base/pages/edit/%C3%A9t%C3%A9%20%3F%23")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertNil(parts.query); XCTAssertNil(parts.fragment); XCTAssertNil(parts.user); XCTAssertNil(parts.password)
        for id in ["", "   ", ".", "..", "../other", "a/b", "a\\b", "%2f", "https://evil.test", "\nsecret"] {
            XCTAssertThrowsError(try deployment.webEditorURL(pageID: id, isDemo: false), id)
        }
        XCTAssertNil(try deployment.webEditorURL(pageID: "page-selected", isDemo: true))
    }

    func testRootAndLocalWebRoutesAndDemoNeverProduceFakeHostLink() throws {
        XCTAssertEqual(try DeploymentURL("https://board.test").webEditorURL(pageID: "p-1", isDemo: false)?.absoluteString,
            "https://board.test/pages/edit/p-1")
        XCTAssertEqual(try DeploymentURL("http://[::1]:4420/prefix", allowLocalHTTP: true).webEditorURL(pageID: "p-1", isDemo: false)?.absoluteString,
            "http://[::1]:4420/prefix/pages/edit/p-1")
        XCTAssertNil(try DeploymentURL("https://demo.invalid").webEditorURL(pageID: "p-1", isDemo: true))
    }

    func testLateScheduleReplyIsRejectedAfterServiceSessionChanges() async throws {
        let deployment = try DeploymentURL("https://board.test")
        let transport = DelayedScheduleTransport()
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let read = Task { try await service.schedules(on: BoardTarget(deployment: deployment, boardID: "board-2")) }
        await transport.waitUntilStarted()
        await service.disconnect()
        await transport.release()
        do { _ = try await read.value; XCTFail("Late schedule escaped its session") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let mutations = await transport.mutations
        XCTAssertEqual(mutations, 0)
    }

    func testCapabilityGuidancePrioritizesUnsupportedOverOptIn() {
        XCTAssertEqual(CapabilityPolicy.boardActionDisabledReason(version: "10.3.2", isDev: false, optedIn: false), .unsupportedOperation)
        XCTAssertEqual(CapabilityPolicy.boardActionDisabledReason(version: "10.1.20", isDev: false, optedIn: false), .changesDisabled)
        XCTAssertNil(CapabilityPolicy.boardActionDisabledReason(version: "10.1.20", isDev: false, optedIn: true))
        XCTAssertEqual(CapabilityPolicy.pageManagementDisabledReason(version: "10.3.2", isDev: false, optedIn: false), .unsupportedOperation)
        XCTAssertEqual(CapabilityPolicy.pageManagementDisabledReason(version: "10.1.20", isDev: false, optedIn: false), .changesDisabled)
        XCTAssertFalse(ActionDisabledReason.unsupportedOperation.message.contains("Enable"))
        XCTAssertTrue(ActionDisabledReason.changesDisabled.message.contains("Settings"))
    }

    func testScheduleReadUsesConcreteBoardQueryRetainsEnvelopeAndNeverWrites() async throws {
        let deployment = try DeploymentURL("https://board.test/prefix")
        let log = RequestLog()
        let bytes = Data(#"{"schedules":[{"id":"s-1","revision":"r1","edit_protocol":"schedule-revision-v1","board_id":"board-2","page_id":"page-selected","start_time":"06:00","end_time":null,"day_pattern":"custom","custom_days":["monday"],"enabled":true,"recurrence_type":"annual_date","annual_date":"02-29","start_type":"sunrise","start_sun_offset":-10,"resolved_start_time":"05:51","future":{"null":null}}],"total":1,"default_page_id":"page-weather","enabled":null,"future":"preserve"}"#.utf8)
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], bytes) }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let result = try await service.schedules(on: BoardTarget(deployment: deployment, boardID: "board-2"))
        XCTAssertEqual(result.rawData, bytes)
        XCTAssertEqual(result.schedules.first?.annualDate, "02-29")
        XCTAssertEqual(result.schedules.first?.startSunOffset, -10)
        XCTAssertEqual(result.schedules.first?.resolvedStartTime, "05:51")
        XCTAssertNil(result.enabled)
        XCTAssertEqual(log.requests.count, 1)
        XCTAssertEqual(log.requests.first?.url?.path, "/prefix/api/v1/schedules")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(log.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "board_id", value: "board-2")])
        XCTAssertTrue(log.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testScheduleRejectsWrongTargetDuplicateIDsAndIncorrectTotal() async throws {
        let deployment = try DeploymentURL("https://board.test/prefix")
        let entry = #"{"id":"s","board_id":"board-2","page_id":"p","start_time":"09:00","day_pattern":"all","enabled":true}"#
        for raw in ["{\"schedules\":[\(entry)],\"total\":2}", "{\"schedules\":[\(entry),\(entry)],\"total\":2}", "{\"schedules\":[\(entry.replacingOccurrences(of: "board-2", with: "other"))],\"total\":1}"] {
            FixtureURLProtocol.handler = { _ in (200, [:], Data(raw.utf8)) }
            let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
            do { _ = try await service.schedules(on: BoardTarget(deployment: deployment, boardID: "board-2")); XCTFail("Invalid listing accepted") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
        }
    }

    func testScheduleUnavailableAndOfflineAreNotEmptySuccess() async throws {
        for error in [FiestaBoardError.rejected(status: 404), .networkUnavailable, .unsupportedOperation] {
            let deployment = try DeploymentURL("https://board.test")
            let service = LiveFiestaBoardService(deployment: deployment, transport: ScheduleFailureTransport(error: error))
            do { _ = try await service.schedules(on: BoardTarget(deployment: deployment, boardID: "board-2")); XCTFail("Failure hidden") }
            catch let actual { XCTAssertEqual(actual as? FiestaBoardError, error) }
        }
    }
}
private actor ScheduleFailureTransport: APITransport {
    let error: FiestaBoardError
    init(error: FiestaBoardError) { self.error = error }
    func send(_ request: APIRequest) async throws -> APIResponse { throw error }
    func resetSession() {}
}

private actor DelayedScheduleTransport: APITransport {
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var mutations = 0
    func send(_ request: APIRequest) async throws -> APIResponse {
        if request.isMutation { mutations += 1 }
        await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] }
        return APIResponse(status: 200, data: Data(#"{"schedules":[],"total":0}"#.utf8))
    }
    func waitUntilStarted() async {
        if gate != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
    func resetSession() {}
}
