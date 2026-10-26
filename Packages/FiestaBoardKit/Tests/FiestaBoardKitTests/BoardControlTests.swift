import XCTest
@testable import FiestaBoardKit

@MainActor final class BoardControlTests: XCTestCase {
    func testPatchEncodesOnlyExplicitFieldsAndDistinguishesClear() throws {
        func json(_ patch: BoardPatch) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as! [String: Any]
        }
        let pause = try json(BoardPatch(paused: true))
        XCTAssertEqual(pause.count, 1)
        XCTAssertEqual(pause["paused"] as? Bool, true)
        XCTAssertNil(pause["default_page_id"])
        let clear = try json(BoardPatch(defaultPage: .clear))
        XCTAssertTrue(clear["default_page_id"] is NSNull)
        XCTAssertEqual(try json(BoardPatch(defaultPage: .set("page-selected")))["default_page_id"] as? String, "page-selected")
    }
    func testLivePatchAndRestoreUseExactConcreteRoutesAndReceiptKinds() async throws {
        let log = RequestLog()
        let deployment = try DeploymentURL("https://board.test/prefix")
        FixtureURLProtocol.handler = { request in
            log.append(request)
            if request.url!.path.hasSuffix("version") { return (200, [:], Data(#"{"package_version":"10.0.0","build_version":"fixture","running_version":"10.0.0","is_dev":false}"#.utf8)) }
            if request.url!.path.hasSuffix("boards") { return (200, [:], fixture("boards")) }
            if request.url!.path.hasSuffix("restore") { return (200, [:], Data(#"{"board_id":"board-2","page_id":"page-selected","sent":false,"reason":"UI only","device_observed":false}"#.utf8)) }
            return (200, [:], fixture("board"))
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        _ = try await service.connect(allowCandidateWrites: true)
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        let updated = try await service.updateBoard(BoardPatch(paused: true), on: target)
        XCTAssertEqual(updated.board.summary.id, "board-2")
        XCTAssertEqual(log.requests.last?.httpMethod, "PATCH")
        XCTAssertEqual(log.requests.last?.url?.path, "/prefix/api/v1/boards/board-2")
        let restore = try await service.restoreBoard(target)
        XCTAssertFalse(restore.sent)
        XCTAssertFalse(restore.deviceObserved)
        XCTAssertEqual(restore.pageID, "page-selected")
        XCTAssertEqual(log.requests.last?.httpMethod, "POST")
        XCTAssertNil(log.requests.last?.httpBody)
        XCTAssertGreaterThanOrEqual(log.requests.last?.timeoutInterval ?? 0, 180)
        XCTAssertEqual(log.requests.filter { $0.httpMethod != "GET" }.count, 2)
    }
    func testDemoPauseScheduleDefaultAndRestoreKeepSelectionSeparate() async throws {
        let service = try DemoFiestaBoardService()
        _ = try await service.connect()
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
        let original = try await service.board(target)
        let paused = try await service.updateBoard(BoardPatch(paused: true), on: target)
        XCTAssertTrue(paused.board.summary.paused)
        XCTAssertEqual(paused.board.summary.scheduleEnabled, original.summary.scheduleEnabled)
        do { _ = try await service.restoreBoard(target); XCTFail("Paused restore must refuse") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .conflict) }
        _ = try await service.updateBoard(BoardPatch(paused: false, scheduleEnabled: true, autoRestore: false, defaultPage: .set("page-weather")), on: target)
        let resumed = try await service.board(target)
        XCTAssertFalse(resumed.summary.paused)
        XCTAssertTrue(resumed.summary.scheduleEnabled)
        XCTAssertEqual(resumed.summary.autoRestore, false)
        XCTAssertEqual(resumed.defaultPageID, "page-weather")
        _ = try await service.updateBoard(BoardPatch(defaultPage: .clear), on: target)
        let cleared = try await service.board(target)
        XCTAssertNil(cleared.defaultPageID)
        XCTAssertEqual(cleared.activePageID, original.activePageID)
        let restored = try await service.restoreBoard(target)
        XCTAssertTrue(restored.sent)
        XCTAssertFalse(restored.deviceObserved)
        XCTAssertEqual(restored.pageID, original.activePageID)
        await service.setSimulation(.held)
        do { _ = try await service.restoreBoard(target); XCTFail("Silenced restore must refuse") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .conflict) }
    }
}

extension BoardControlTests {
    func testPageDocumentReadPreservesUnknownFieldsAndExactBytes() async throws {
        let bytes = Data(#"{ "id":"page-selected", "name":"Selected", "type":"template", "device_type":"flagship", "future_field":{"x":[1,2]} }"#.utf8)
        let deployment = try DeploymentURL("https://board.test")
        FixtureURLProtocol.handler = { _ in (200, [:], bytes) }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let document = try await service.pageDocumentData(id: "page-selected")
        XCTAssertEqual(document, bytes)
        do { _ = try await service.pageDocumentData(id: "different"); XCTFail("Reject mismatched identity") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
    }
    func testControlsStayReadOnlyForUnknownVersionAndRejectUnscopedTarget() async throws {
        let deployment = try DeploymentURL("https://board.test")
        FixtureURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("version") { return (200, [:], Data(#"{"package_version":"9.14.9","build_version":"fixture","running_version":"9.14.9","is_dev":false}"#.utf8)) }
            return (200, [:], fixture("boards"))
        }
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        _ = try await service.connect(allowCandidateWrites: true)
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        do { _ = try await service.updateBoard(BoardPatch(paused: false), on: target); XCTFail("Expected write gate") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .writesDisabled) }
        do { _ = try await service.restoreBoard(target); XCTFail("Expected write gate") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .writesDisabled) }
        let demo = try DemoFiestaBoardService()
        _ = try await demo.connect()
        do { _ = try await demo.updateBoard(BoardPatch(paused: false), on: target); XCTFail("Expected scope rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
        do { _ = try await demo.restoreBoard(BoardTarget(deployment: demo.deployment, boardID: "missing")); XCTFail("Expected target rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
    }
}

extension BoardControlTests {
    func testMalformedOrMismatchedControlReceiptsBecomeUnknownWithoutReplay() async throws {
        let deployment = try DeploymentURL("https://board.test")
        for malformed in [#"{}"#, #"{"board_id":"other","page_id":null,"sent":true,"device_observed":false}"#, #"{"board_id":"board-2","page_id":null,"sent":true,"device_observed":true}"#] {
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in
                log.append(request)
                if request.url!.path.hasSuffix("version") { return (200, [:], Data(#"{"package_version":"10.0.0","build_version":"fixture","running_version":"10.0.0","is_dev":false}"#.utf8)) }
                if request.url!.path.hasSuffix("boards") { return (200, [:], fixture("boards")) }
                return (200, [:], Data(malformed.utf8))
            }
            let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
            _ = try await service.connect(allowCandidateWrites: true)
            let target = try BoardTarget(deployment: deployment, boardID: "board-2")
            do { _ = try await service.restoreBoard(target); XCTFail("Expected unknown restore") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
            do { _ = try await service.updateBoard(BoardPatch(paused: true), on: target); XCTFail("Expected unknown patch") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
            XCTAssertEqual(log.requests.filter { $0.httpMethod == "POST" }.count, 1)
            XCTAssertEqual(log.requests.filter { $0.httpMethod == "PATCH" }.count, 1)
        }
    }
}
