import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class HomeRecordedVersionTests: XCTestCase {
    private func read(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf:root.appendingPathComponent("Tests/Fixtures/Home/DockerUndo/" + name + ".json"))
    }
    func testActualReviewedDockerVersionAndSnapshotPermitAuditedControlWithoutGenericWrites() async throws {
        struct List: Decodable { let boards: [BoardSummary] }
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionInfo.self,from:read("home-version"))
        let board = try decoder.decode(BoardDetail.self,from:read("home-manual"))
        let boards = try decoder.decode(List.self,from:read("home-boards")).boards
        let capability = try decoder.decode(HomeOverrideStatus.self,from:read("undo-capability"))
        XCTAssertEqual(version.runningVersion,"11.0.0-alpha.3")
        XCTAssertTrue(board.hasScopedHomeStatus)
        XCTAssertTrue(capability.undoSupported)
        let service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureHomeRecording(version:version,boards:boards,board:board)
        await service.configureUndo(supported:capability.undoSupported,expiresAt:Date().addingTimeInterval(30))
        let store = BoardStore(); await store.connect(service).value
        XCTAssertEqual(store.status?.version.runningVersion,version.runningVersion)
        XCTAssertEqual(store.selectedBoardID,board.summary.id)
        XCTAssertFalse(store.canWrite,"Auditing Home must not grant unrelated settings/editor writes")
        XCTAssertTrue(store.canPerformHomeControl(.cancelOverride))
        XCTAssertTrue(store.canPerformHomeControl(.selectPage))
        XCTAssertTrue(store.canPerformHomeControl(.timedOverride))
        await store.refreshHomeUndoCapability().value
        let action = store.prepare(.homeCancelOverride)
        XCTAssertNotNil(action,"The actual recorded hub must not be silently gated off")
        if let action {
            await store.confirm(action).value
            XCTAssertTrue(store.canUndoHomeOverride)
            let sent = await service.canceledBoards
            XCTAssertEqual(sent,[board.summary.id])
        }
    }
}
