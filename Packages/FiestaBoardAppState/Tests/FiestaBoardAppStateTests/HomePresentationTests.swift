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
