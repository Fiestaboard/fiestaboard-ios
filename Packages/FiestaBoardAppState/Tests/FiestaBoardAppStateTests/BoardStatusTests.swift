import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

/// One test per B8 scenario, mirroring the fixture's `/board-<scenario>-<n>/` facts.
final class NowShowingModelTests: XCTestCase {
    private let pages = ["hello": "Hello World", "morning": "Good Morning", "note": "Desk Note"]
    private let collections = ["9b3a1c2e-0000-4000-8000-00000000c011": "Morning rotation"]
    private let collectionID = "collection:9b3a1c2e-0000-4000-8000-00000000c011"

    private func board(paused: Bool = false, schedule: Bool = false) throws -> BoardSummary {
        try JSONDecoder().decode(BoardSummary.self, from: Data("""
        {"id":"kitchen","name":"Kitchen","device_type":"flagship","rows":6,"cols":22,"is_primary":true,
         "paused":\(paused),"schedule_enabled":\(schedule),"auto_restore":true,"output":"vestaboard",
         "device_model":"vestaboard_flagship","charset":"vestaboard_v1"}
        """.utf8))
    }

    private func make(_ board: BoardSummary, schedule: ActivePageStatus? = nil, manual: ActivePageStatus? = nil,
                      silence: SilenceStatus? = nil) -> NowShowing {
        NowShowingModel.make(board: board, detail: nil, schedule: schedule, manual: manual, silence: silence,
                             pageNames: pages, collectionNames: collections)
    }

    func testManual() throws {
        let now = make(try board(), schedule: .init(pageID: nil, scheduleEnabled: false), manual: .init(pageID: "hello", resolvedPageID: "hello"))
        XCTAssertEqual(now.name, "Hello World"); XCTAssertEqual(now.pageID, "hello")
        XCTAssertEqual(now.mode.label, "Manual Mode")
        XCTAssertFalse(now.collection || now.silence || now.paused || now.scheduleGap)
    }

    func testSchedule() throws {
        let now = make(try board(schedule: true), schedule: .init(pageID: "hello", resolvedPageID: "hello", scheduleEnabled: true))
        XCTAssertEqual(now.name, "Hello World"); XCTAssertEqual(now.mode.label, "Schedule Mode")
    }

    func testScheduleGap() throws {
        let now = make(try board(schedule: true), schedule: .init(pageID: nil, scheduleEnabled: true))
        XCTAssertEqual(now.name, "Schedule gap (no default page set)"); XCTAssertTrue(now.scheduleGap); XCTAssertNil(now.pageID)
    }

    func testCollection() throws {
        let now = make(try board(schedule: true), schedule: .init(pageID: collectionID, resolvedPageID: "morning",
                                                                   resolvedNextCheckSeconds: 2, scheduleEnabled: true))
        XCTAssertEqual(now.name, "Morning rotation › Good Morning"); XCTAssertTrue(now.collection)
        XCTAssertEqual(now.pageID, "morning")
        XCTAssertFalse(now.name.contains("collection:"), "no raw ids")
        XCTAssertEqual(BoardPolling.activePageInterval(nextCheck: 2), 2)
        XCTAssertEqual(BoardPolling.activePageInterval(nextCheck: 0.5), 2, "floored at 2 s")
        XCTAssertEqual(BoardPolling.activePageInterval(nextCheck: nil), 60)
    }

    func testCollectionNativeNull() throws {
        let now = make(try board(schedule: true), schedule: .init(pageID: collectionID, resolvedPageID: nil, scheduleEnabled: true))
        XCTAssertEqual(now.name, "Morning rotation › Device selecting…"); XCTAssertTrue(now.collection); XCTAssertNil(now.pageID)
    }

    func testOverride() throws {
        let now = make(try board(schedule: true), schedule: .init(pageID: "hello", scheduleEnabled: true,
                       temporaryOverride: .init(active: true, pageID: "note", remainingSeconds: 540)))
        XCTAssertEqual(now.mode.label, "Override: 9m remaining"); XCTAssertEqual(now.name, "Desk Note")
        XCTAssertEqual(NowShowing.Mode.override(remainingSeconds: 30).label, "Override: <1m remaining")
    }

    func testPaused() throws {
        let now = make(try board(paused: true), manual: .init(pageID: "hello"))
        XCTAssertTrue(now.paused); XCTAssertEqual(now.name, "Hello World"); XCTAssertEqual(now.mode.label, "Manual Mode")
    }

    func testSilence() throws {
        let now = make(try board(), manual: .init(pageID: "hello"), silence: .init(enabled: true, active: true, mode: "indicator"))
        XCTAssertTrue(now.silence); XCTAssertEqual(now.name, "Hello World")
        let page = make(try board(), manual: .init(pageID: "hello"), silence: .init(active: true, mode: "page", pageID: "note"))
        XCTAssertEqual(page.name, "Desk Note", "a silence page wins")
    }

    func testNothingSelected() throws {
        XCTAssertEqual(make(try board()).name, "No page selected")
    }
}

private actor SleepRecorder {
    var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
}

extension BoardStoreTests {
    /// B6: after a send the board is re-read at ≈0.75 s and ≈3.5 s.
    func testPostSendRefreshSchedule() async throws {
        XCTAssertEqual(BoardPolling.postSend, [0.75, 3.5])
        XCTAssertEqual(BoardPolling.board, 30); XCTAssertEqual(BoardPolling.status, 15); XCTAssertEqual(BoardPolling.activePage, 60)
        let recorder = SleepRecorder()
        let status = BoardStatus(store: BoardStore(), reader: { nil }, sleep: { await recorder.record($0) })
        var refreshes = 0
        let done = expectation(description: "two post-send refreshes")
        done.expectedFulfillmentCount = 2
        status.onPostSendRefresh = { refreshes += 1; done.fulfill() }
        status.noteSend()
        await fulfillment(of: [done], timeout: 2)
        let delays = await recorder.delays
        XCTAssertEqual(delays.count, 2)
        XCTAssertEqual(delays[0], 0.75, accuracy: 1e-9)
        XCTAssertEqual(delays[0] + delays[1], 3.5, accuracy: 1e-9, "second re-read at +3.5 s after the send")
        XCTAssertEqual(refreshes, 2)
    }
}
