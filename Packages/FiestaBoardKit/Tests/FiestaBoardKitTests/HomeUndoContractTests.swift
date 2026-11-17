import XCTest
@testable import FiestaBoardKit

@MainActor final class HomeUndoContractTests: XCTestCase {
    private func read(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Home/" + name + ".json"))
    }
    func testRecordedCapabilityIsExplicitAndTimedRestorePreservesOriginalInstants() throws {
        let before = try JSONDecoder().decode(HomeOverrideStatus.self, from: read("HostUndo/undo-capability"))
        let restored = try JSONDecoder().decode(HomeOverrideStatus.self, from: read("HostUndo/undo-restored"))
        XCTAssertTrue(before.undoSupported)
        XCTAssertEqual(restored.startedAt,before.startedAt)
        XCTAssertEqual(restored.expiresAt,before.expiresAt)
        XCTAssertEqual(restored.pageID,before.pageID)
        XCTAssertEqual(restored.boardID,before.boardID)
        XCTAssertFalse(try JSONDecoder().decode(HomeOverrideStatus.self, from: read("HostV11/override-detail")).undoSupported)
        let indefinite = try JSONDecoder().decode(HomeOverrideStatus.self, from: read("HostUndo/undo-indefinite-restored"))
        XCTAssertTrue(indefinite.active); XCTAssertNil(indefinite.expiresAt)
    }
    func testOptInCancelAndRestoreAreScopedNoStoreAndNeverReplayConflict() async throws {
        let log = RequestLog()
        let cancel = try read("HostUndo/undo-cancel")
        let restored = try read("HostUndo/undo-restored")
        FixtureURLProtocol.handler = { request in log.append(request); return (200,[:],request.httpMethod == "DELETE" ? cancel : restored) }
        let deployment = try DeploymentURL("https://hub.test/prefix")
        let service = LiveFiestaBoardService(deployment: deployment,
            transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
        let receipt = try await service.cancelHomeOverride(boardID: "cx-kitchen", requestingUndo: true)
        let token = try XCTUnwrap(receipt.undoToken)
        _ = try await service.undoHomeOverride(boardID: "cx-kitchen", token: token)
        XCTAssertEqual(log.requests.count,2)
        XCTAssertEqual(log.requests[0].value(forHTTPHeaderField:"Cache-Control"),"no-store")
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField:"Cache-Control"),"no-store")
        XCTAssertEqual(log.requests[0].url?.query,"board_id=cx-kitchen&undo=true")
        XCTAssertEqual(log.requests[1].url?.path,"/prefix/api/settings/temporary-override/undo")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(log.requests[1].httpBody)) as? [String:String])
        XCTAssertEqual(body,["board_id":"cx-kitchen","undo_token":token])
        let conflict = try read("HostUndo/undo-used")
        FixtureURLProtocol.handler = { request in log.append(request); return (409,[:],conflict) }
        do { _ = try await service.undoHomeOverride(boardID: "cx-kitchen", token: token); XCTFail("A used receipt must fail") } catch {}
        XCTAssertEqual(log.requests.count,3)
        for invalid in ["",String(repeating:"x",count:129)] {
            do { _ = try await service.undoHomeOverride(boardID: "cx-kitchen", token: invalid); XCTFail("Reject invalid receipt before dispatch") } catch {}
        }
        XCTAssertEqual(log.requests.count,3)
    }
    func testNoActiveOverrideReturnsNoUndoAuthority() throws {
        let receipt = try JSONDecoder().decode(HomeOverrideCancellation.self, from: read("HostUndo/undo-empty-cancel"))
        XCTAssertNil(receipt.undoToken); XCTAssertNil(receipt.undoExpiresAt)
    }
    func testMalformedSuccessCannotAcknowledgeCancellation() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200,[:],Data("{}".utf8)) }
        let deployment = try DeploymentURL("https://hub.test")
        let service = LiveFiestaBoardService(deployment:deployment,
            transport:URLSessionTransport(deployment:deployment,protocolClasses:[FixtureURLProtocol.self]))
        do { _ = try await service.cancelHomeOverride(boardID:"cx-kitchen",requestingUndo:true); XCTFail("A malformed 200 is an unknown mutation outcome") }
        catch { XCTAssertEqual(error as? FiestaBoardError,.unknownMutationOutcome) }
        XCTAssertEqual(log.requests.count,1)
    }
}
