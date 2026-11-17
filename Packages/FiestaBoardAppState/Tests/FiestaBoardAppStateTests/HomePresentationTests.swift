import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

final class HomePresentationTests: XCTestCase {
    func testOverrideBeatsSilencePageWhileRetainingSilenceStatus() throws {
        let board = try JSONDecoder().decode(BoardSummary.self, from: Data(#"{"id":"kitchen","name":"Kitchen board","device_type":"flagship","rows":6,"cols":22,"is_primary":true,"paused":false,"schedule_enabled":true,"output":"none"}"#.utf8))
        let showing = NowShowingModel.make(board: board, detail: nil,
            schedule: .init(pageID: "scheduled", scheduleEnabled: true,
                temporaryOverride: .init(active: true, pageID: "override", remainingSeconds: 300)),
            manual: nil, silence: .init(active: true, mode: "page", pageID: "silence"),
            pageNames: ["override":"Back soon", "silence":"Quiet hours", "scheduled":"Good night"], collectionNames: [:])
        XCTAssertEqual(showing.name, "Back soon", "The actual per-display override wins the silence page")
        XCTAssertEqual(showing.pageID, "override")
        XCTAssertTrue(showing.silence, "Preserve the underlying silence-window fact for the status presentation")
    }
}

extension HomePresentationTests {
    func testCountdownUsesExpiryAndClockRatherThanPolledRemainingValue() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HomeTiming.remainingLabel(expiresAt: "1970-01-01T02:42:00Z", now: now), "2h 42m left")
        XCTAssertEqual(HomeTiming.remainingLabel(expiresAt: "1970-01-01T02:42:00Z", now: now.addingTimeInterval(60)), "2h 41m left")
        XCTAssertEqual(HomeTiming.remainingLabel(expiresAt: nil, now: now), "Until canceled")
        XCTAssertEqual(HomeTiming.remainingLabel(expiresAt: "invalid", now: now), "")
        XCTAssertEqual(HomeTiming.remainingLabel(expiresAt: "1970-01-01T00:00:00Z", now: now), "Ending…")
    }
    func testAuthoritativeNextChangeAndUnknownHealth() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let detail = try JSONDecoder().decode(BoardDetail.self,
            from: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Home/home-override.json")))
        let p = HomePresentation.make(detail: detail, showing: nil, silence: nil,
            pageNames: [try XCTUnwrap(detail.nextPageID): "Welcome"], now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(p.modeLabel, "Override")
        XCTAssertEqual(p.nextChange?.title, "Override ends")
        XCTAssertEqual(p.nextChange?.pageName, "Welcome")
        XCTAssertNil(p.banner, "Null device health is not offline")
    }
    func testPausedBannerWinsSilenceAndIndefiniteOverrideHasNoFakeExpiry() throws {
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(#"{"id":"kitchen","name":"Kitchen","device_type":"flagship","rows":6,"cols":22,"is_primary":true,"paused":true,"schedule_enabled":false,"output":"none","source":"manual","override_started_at":"1970-01-01T00:00:00Z"}"#.utf8))
        let p = HomePresentation.make(detail: detail, showing: nil, silence: .init(active: true), pageNames: [:], now: Date())
        XCTAssertEqual(p.banner, .paused)
        XCTAssertEqual(p.overrideRemaining, "Until canceled")
        XCTAssertNil(p.nextChange)
    }
}

extension HomePresentationTests {
    func testUntilScheduleBoundaryUsesFreshClockAndRejectsExpiredOrLongTimers() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HomeTiming.durationMinutes(until: now.addingTimeInterval(162 * 60), now: now),162)
        XCTAssertEqual(HomeTiming.durationMinutes(until: now.addingTimeInterval(61), now: now),2)
        XCTAssertNil(HomeTiming.durationMinutes(until: now, now: now))
        XCTAssertNil(HomeTiming.durationMinutes(until: now.addingTimeInterval(86401), now: now))
    }
}

extension HomePresentationTests {
    func testUntilScheduleBoundaryRespectsEightHourCreateContract() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(HomeTiming.durationMinutes(until: now.addingTimeInterval(28800), now: now),480)
        XCTAssertNil(HomeTiming.durationMinutes(until: now.addingTimeInterval(28801), now: now))
    }
}
