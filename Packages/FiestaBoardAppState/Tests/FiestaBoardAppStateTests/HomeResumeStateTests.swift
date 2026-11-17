import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class HomeResumeStateTests: XCTestCase {
    private func pausedService() async throws -> FixtureFiestaBoardService {
        var root = URL(fileURLWithPath:#filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners")
        func read(_ name: String) throws -> Data { try Data(contentsOf:directory.appendingPathComponent(name + ".json")) }
        struct List: Decodable { let boards: [BoardSummary] }
        let decoder = JSONDecoder(), service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureHomeRecording(version:try decoder.decode(VersionInfo.self,from:read("home-version")),
            boards:try decoder.decode(List.self,from:read("home-boards")).boards,
            board:try decoder.decode(BoardDetail.self,from:read("home-paused")))
        await service.configureHomeResumeReadback(try decoder.decode(BoardDetail.self,from:read("home-resumed")))
        return service
    }
    func testPendingResumeBlocksAllWritersAndRepeatedTap() async throws {
        let service = try await pausedService()
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        XCTAssertTrue(status.canResumeHomeDisplay)
        await service.configureHome(delayed: true)
        let resume = Task { await status.resumeHomeDisplay() }
        await service.waitForHomeMutation()
        XCTAssertTrue(store.commandBusy); XCTAssertFalse(store.canWrite)
        XCTAssertNil(store.prepare(.restore)); XCTAssertFalse(status.canClearOverride)
        await status.resumeHomeDisplay()
        let targets = await service.resumedBoards
        XCTAssertEqual(targets,[try XCTUnwrap(store.selectedBoardID)])
        await service.releaseHomeMutation(); await resume.value
        XCTAssertEqual(status.homeControlOutcome,.displayResumed)
        XCTAssertFalse(try XCTUnwrap(store.board).summary.paused)
        XCTAssertFalse(status.canResumeHomeDisplay)
    }
    func testUnknownResumeNeedsExplicitVerificationAndNeverReplays() async throws {
        let service = try await pausedService()
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureHome(failure:.unknownMutationOutcome)
        await status.resumeHomeDisplay()
        XCTAssertTrue(store.needsReadback); XCTAssertFalse(status.canResumeHomeDisplay)
        await status.resumeHomeDisplay()
        let targets = await service.resumedBoards
        XCTAssertEqual(targets.count,1)
        await status.refreshHomeControlState()
        XCTAssertFalse(store.needsReadback); XCTAssertTrue(status.canResumeHomeDisplay)
    }
    func testLegacyWritableConnectionCannotDispatchScopedResume() async throws {
        let service = try FixtureFiestaBoardService()
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        XCTAssertTrue(store.canWrite); XCTAssertFalse(status.canResumeHomeDisplay)
        await status.resumeHomeDisplay()
        let targets = await service.resumedBoards
        XCTAssertTrue(targets.isEmpty)
    }
}
