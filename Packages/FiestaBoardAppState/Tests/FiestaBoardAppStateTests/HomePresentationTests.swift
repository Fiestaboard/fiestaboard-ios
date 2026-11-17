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
    // Synthetic interval controls; recorded contracts are covered separately below.
    private func syntheticOverride(start: String? = "1970-01-01T00:00:00Z",
                                   end: String? = "1970-01-01T02:00:00Z",
                                   schedule: Bool = true, paused: Bool = false,
                                   silence: SilenceStatus? = nil, now: TimeInterval = 1800) throws -> HomePresentation {
        var object: [String: Any] = ["id": "cx-kitchen", "name": "Kitchen", "device_type": "flagship",
            "rows": 6, "cols": 22, "is_primary": true, "paused": paused,
            "schedule_enabled": schedule, "output": "none", "source": "manual",
            "next_change_reason": "override_ends"]
        object["override_started_at"] = start
        object["override_expires_at"] = end
        let detail = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: object))
        return HomePresentation.make(detail: detail, showing: nil, silence: silence, pageNames: [:],
                                     now: Date(timeIntervalSince1970: now))
    }

    private func recordedInactiveSilence() throws -> SilenceStatus {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(SilenceStatus.self, from: Data(contentsOf:
            root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners/home-silence.json")))
    }

    func testOverrideProgressDrainsFromAuthoritativeIntervalWithClock() throws {
        let start = try syntheticOverride(now: 0)
        XCTAssertEqual(start.overrideExpiresAt, Date(timeIntervalSince1970: 7200))
        XCTAssertEqual(try XCTUnwrap(start.overrideRemainingFraction), 1, accuracy: 0.000001)
        let later = try syntheticOverride(silence: recordedInactiveSilence(), now: 1800)
        XCTAssertEqual(try XCTUnwrap(later.overrideRemainingFraction), 0.75, accuracy: 0.000001)
        XCTAssertEqual(later.overrideRemaining, "1h 30m left")
        XCTAssertTrue(later.overrideResumesSchedule)
    }

    func testOverrideRejectsUnusableIntervalsInsteadOfInventingProgressOrResume() throws {
        let intervals: [(String?, String?, TimeInterval)] = [
            ("1970-01-01T00:00:00Z", nil, 1800),
            ("invalid", "1970-01-01T02:00:00Z", 1800),
            ("1970-01-01T00:00:00Z", "invalid", 1800),
            ("1970-01-01T02:00:00Z", "1970-01-01T02:00:00Z", 1800),
            ("1970-01-01T03:00:00Z", "1970-01-01T02:00:00Z", 1800),
            ("1970-01-01T01:00:00Z", "1970-01-01T02:00:00Z", 1800),
            ("1970-01-01T00:00:00Z", "1970-01-01T02:00:00Z", 7200),
            ("1970-01-01T00:00:00Z", "1970-01-01T02:00:00Z", 7201)
        ]
        for (start, end, now) in intervals {
            let p = try syntheticOverride(start: start, end: end, now: now)
            XCTAssertNil(p.overrideExpiresAt, "Unusable interval: \(String(describing: start)) / \(String(describing: end)) @ \(now)")
            XCTAssertNil(p.overrideRemainingFraction)
            XCTAssertFalse(p.overrideResumesSchedule)
        }
    }

    func testOverrideResumeClaimRequiresEnabledUnpausedUnsilencedSchedule() throws {
        XCTAssertFalse(try syntheticOverride(schedule: false, silence: recordedInactiveSilence()).overrideResumesSchedule)
        XCTAssertFalse(try syntheticOverride(paused: true, silence: recordedInactiveSilence()).overrideResumesSchedule)
        XCTAssertFalse(try syntheticOverride(silence: .init(active: true)).overrideResumesSchedule)
        XCTAssertTrue(try syntheticOverride(silence: .init(active: false)).overrideResumesSchedule)
        XCTAssertTrue(try syntheticOverride(silence: recordedInactiveSilence()).overrideResumesSchedule)
    }

    func testOverrideMissingSilenceReadKeepsExpiryExplanationNeutral() throws {
        // BoardStatus stores nil both before the first read and after try? fails.
        let p = try syntheticOverride(silence: nil)
        XCTAssertNotNil(p.overrideExpiresAt)
        XCTAssertFalse(p.overrideResumesSchedule, "No response does not prove silence is inactive")
    }

    func testOverrideOtherDisplayInactiveSilenceDoesNotProveSelectedDisplayResumes() throws {
        let p = try syntheticOverride(silence: .init(active: false, boardID: "desk"))
        XCTAssertFalse(p.overrideResumesSchedule)
    }

    func testNoOverrideDoesNotExposeExpiryProgressOrResumeClaim() {
        let p = HomePresentation.make(detail: nil, showing: nil, silence: nil, pageNames: [:], now: Date())
        XCTAssertNil(p.overrideExpiresAt)
        XCTAssertNil(p.overrideRemainingFraction)
        XCTAssertFalse(p.overrideResumesSchedule)
    }

    func testRecordedOverrideEndsReasonDoesNotClaimDisabledScheduleResumes() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(contentsOf:
            root.appendingPathComponent("Tests/Fixtures/Home/home-override.json")))
        let p = HomePresentation.make(detail: detail, showing: nil, silence: nil, pageNames: [:],
                                     now: try XCTUnwrap(HomeTiming.instant("2026-11-17T03:00:00Z")))
        XCTAssertNotNil(p.overrideExpiresAt)
        XCTAssertNotNil(p.overrideRemainingFraction)
        XCTAssertFalse(p.overrideResumesSchedule, "The recorded override_ends reason coexists with schedule_enabled:false")
    }

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

extension HomePresentationTests {
    func testPausedStatusUsesPausedModeInsteadOfManual() throws {
        var root = URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let detail = try JSONDecoder().decode(BoardDetail.self,from:Data(contentsOf:
            root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners/home-paused.json")))
        let result = HomePresentation.make(detail:detail,showing:nil,silence:nil,pageNames:[:],now:Date())
        XCTAssertEqual(result.modeLabel,"Paused")
    }
}

extension HomePresentationTests {
    func testRecordedSilenceEmptyHeldAndHoldDisabledRemainDistinctAndDisplayScoped() throws {
        var root = URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        func read(_ name: String) throws -> SilenceStatus {
            try JSONDecoder().decode(SilenceStatus.self,from:Data(contentsOf:
                root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners/" + name + ".json")))
        }
        let empty = HomeSilencePresentation.make(status:try read("silence-empty"),boardID:"cx-kitchen")
        XCTAssertNotNil(empty); XCTAssertNil(empty?.heldPreview)
        XCTAssertTrue(empty?.holdsBlockedSends == true); XCTAssertNotNil(empty?.endsAt)
        let held = HomeSilencePresentation.make(status:try read("silence-held"),boardID:"cx-kitchen")
        XCTAssertEqual(held?.heldPreview,"Package delivered"); XCTAssertNotNil(held?.queuedAt)
        let replacement = HomeSilencePresentation.make(status:try read("silence-replacement"),boardID:"cx-kitchen")
        XCTAssertEqual(replacement?.heldPreview,"New reminder")
        let disabled = HomeSilencePresentation.make(status:try read("silence-without-hold"),boardID:"cx-kitchen")
        XCTAssertEqual(disabled?.heldPreview,"New reminder"); XCTAssertFalse(disabled?.holdsBlockedSends ?? true)
        XCTAssertNil(HomeSilencePresentation.make(status:try read("silence-held"),boardID:"cx-desk"))
        XCTAssertNil(HomeSilencePresentation.make(status:.init(active:false),boardID:"cx-kitchen"))
    }
    func testSilencedModeRemainsVisibleWithoutInventingOverride() {
        let p = HomePresentation.make(detail:nil,showing:nil,silence:.init(active:true),pageNames:[:],now:Date())
        XCTAssertEqual(p.modeLabel,"Silenced"); XCTAssertEqual(p.banner,.silenced)
        XCTAssertNil(p.overrideRemaining)
    }
}
