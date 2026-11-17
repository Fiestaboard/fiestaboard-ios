import XCTest
@testable import FiestaBoardKit

@MainActor final class HomeBannerContractTests: XCTestCase {
    private func read(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf:root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners/" + name + ".json"))
    }
    func testActualScopedResumeDoesNotUnpauseTheOtherDisplay() throws {
        let paused = try JSONDecoder().decode(BoardDetail.self,from:read("home-paused"))
        let unchanged = try JSONDecoder().decode(BoardDetail.self,from:read("home-still-paused"))
        let resumed = try JSONDecoder().decode(BoardDetail.self,from:read("home-resumed"))
        XCTAssertTrue(paused.summary.paused); XCTAssertTrue(unchanged.summary.paused)
        XCTAssertFalse(resumed.summary.paused)
        let receipt = try JSONDecoder().decode(HomePauseReceipt.self,from:read("resume-accepted"))
        XCTAssertEqual(receipt.boardID,"cx-kitchen"); XCTAssertFalse(receipt.paused)
        let before = try JSONDecoder().decode(ActivePageStatus.TemporaryOverride.self,from:read("override-before-resume"))
        let after = try JSONDecoder().decode(ActivePageStatus.TemporaryOverride.self,from:read("override-after-resume"))
        XCTAssertEqual(before.startedAt,after.startedAt); XCTAssertEqual(before.expiresAt,after.expiresAt)
        XCTAssertEqual(before.pageID,after.pageID); XCTAssertTrue(after.active)
        let silenceBefore = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-before-resume"))
        let silenceAfter = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-after-resume"))
        XCTAssertTrue(silenceAfter.active); XCTAssertEqual(silenceBefore.held,silenceAfter.held)
        XCTAssertEqual(silenceBefore.holdsBlockedSends,silenceAfter.holdsBlockedSends)
    }
    func testResumeDispatchesOnlyFalseToExplicitTargetOnceAndRejectsMismatchedAck() async throws {
        let log = RequestLog(), reply = try read("resume-accepted")
        FixtureURLProtocol.handler = { request in log.append(request); return (200,[:],reply) }
        let deployment = try DeploymentURL("https://hub.test/prefix")
        let service = LiveFiestaBoardService(deployment:deployment,
            transport:URLSessionTransport(deployment:deployment,protocolClasses:[FixtureURLProtocol.self]))
        _ = try await service.resumeHomeDisplay(boardID:"cx-kitchen")
        XCTAssertEqual(log.requests[0].url?.path,"/prefix/api/settings/board/cx-kitchen/pause")
        XCTAssertEqual(log.requests[0].httpMethod,"POST")
        XCTAssertEqual(try JSONSerialization.jsonObject(with:XCTUnwrap(log.requests[0].httpBody)) as? [String:Bool],["paused":false])
        let other = try read("resume-other-display")
        FixtureURLProtocol.handler = { request in log.append(request); return (200,[:],other) }
        do { _ = try await service.resumeHomeDisplay(boardID:"cx-kitchen"); XCTFail("Wrong-display success cannot acknowledge the action") }
        catch { XCTAssertEqual(error as? FiestaBoardError,.unknownMutationOutcome) }
        do { _ = try await service.resumeHomeDisplay(boardID:"../other"); XCTFail("Reject invalid target before dispatch") } catch {}
        XCTAssertEqual(log.requests.count,2)
    }
    func testActualHeldReadFieldsReplaceRatherThanAccumulateAndHoldFlagIsIndependent() throws {
        let empty = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-empty"))
        let held = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-held"))
        let newer = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-replacement"))
        let disabled = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-without-hold"))
        let other = try JSONDecoder().decode(SilenceStatus.self,from:read("silence-other-display"))
        XCTAssertTrue(empty.active); XCTAssertTrue(empty.holdsBlockedSends); XCTAssertNil(empty.held)
        XCTAssertEqual(held.boardID,"cx-kitchen"); XCTAssertEqual(held.held?.kind,"text")
        XCTAssertEqual(held.held?.preview,"Package delivered"); XCTAssertNotNil(held.held?.queuedAt)
        XCTAssertEqual(newer.held?.preview,"New reminder"); XCTAssertNotEqual(held.held,newer.held)
        XCTAssertFalse(disabled.holdsBlockedSends); XCTAssertNotNil(disabled.held,"The server retains an intent independently of the delivery preference")
        XCTAssertEqual(other.boardID,"cx-desk"); XCTAssertNil(other.held)
    }
    func testHeldShapeIsStrictAndLegacyAbsenceDoesNotInventQueueAuthority() throws {
        let legacy = try JSONDecoder().decode(SilenceStatus.self,from:Data(#"{"active":true}"#.utf8))
        XCTAssertFalse(legacy.holdsBlockedSends); XCTAssertNil(legacy.held); XCTAssertNil(legacy.boardID)
        for json in [#"{"active":true,"holds_blocked_sends":"true"}"#,
                     #"{"active":true,"held":{}}"#,
                     #"{"active":true,"held":{"kind":1,"preview":"x","queued_at":"now"}}"#,
                     #"{"active":true,"held":{"kind":"text","preview":"x"}}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(SilenceStatus.self,from:Data(json.utf8)))
        }
    }
}
