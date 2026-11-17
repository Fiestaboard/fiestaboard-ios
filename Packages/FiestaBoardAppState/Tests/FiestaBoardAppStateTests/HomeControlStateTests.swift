import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class HomeControlStateTests: XCTestCase {
    func testUnknownCancelRequiresExplicitReadBeforeAnotherMutation() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let reader = try HomeControlReader()
        let status = BoardStatus(store: store, reader: { reader })
        await reader.failNextMutation()
        await status.clearTemporaryOverride()
        XCTAssertTrue(status.homeControlNeedsReadback)
        XCTAssertFalse(status.canClearOverride)
        await status.clearTemporaryOverride()
        let before = await reader.canceledBoards
        XCTAssertEqual(before, ["board-2"], "An ambiguous mutation is never replayed by another tap")
        await status.refreshHomeControlState()
        XCTAssertFalse(status.homeControlNeedsReadback)
        XCTAssertTrue(status.canClearOverride)
    }
    func testCommonHomeBarrierRespectsOfflineAndOtherUnknownWrite() async throws {
        let service = try FixtureFiestaBoardService()
        let store = BoardStore()
        await store.connect(service).value
        XCTAssertTrue(store.canPerformScopedHomeControl)
        store.networkAvailable = false
        XCTAssertFalse(store.canPerformScopedHomeControl)
        store.networkAvailable = true
        await store.probeReachability().value
        XCTAssertTrue(store.canPerformScopedHomeControl)
        await service.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("UNCONFIRMED")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canPerformScopedHomeControl)
    }
}

private actor HomeControlReader: BoardStatusReading, TemporaryOverrideClearing, HomePageSelecting {
    nonisolated let deployment = try! DeploymentURL("https://home.test")
    var canceledBoards: [String] = []
    private var fail = false
    func failNextMutation() { fail = true }
    func clearTemporaryOverride(boardID: String) async throws {
        canceledBoards.append(boardID)
        if fail { fail = false; throw FiestaBoardError.unknownMutationOutcome }
    }
    func selectHomePage(pageID: String, boardID: String, durationMinutes: Int?) async throws -> HomeControlReceipt {
        throw FiestaBoardError.unknownMutationOutcome
    }
    func boardSettings() async throws -> [StoredBoardEntry] { [] }
    func serviceStatus() async throws -> ServiceStatusReport { try JSONDecoder().decode(ServiceStatusReport.self, from: Data(#"{"boards":{}}"#.utf8)) }
    func currentMessage(boardID: String) async throws -> CurrentBoardMessage { try JSONDecoder().decode(CurrentBoardMessage.self, from: Data("{}".utf8)) }
    func activeSchedulePage(boardID: String) async throws -> ActivePageStatus { .init(pageID: nil, scheduleEnabled: false) }
    func activePage(boardID: String) async throws -> ActivePageStatus { .init(pageID: nil) }
    func silenceStatus(boardID: String) async throws -> SilenceStatus { .init(active: false) }
    func displaySettings() async throws -> BoardDisplaySettings { .init() }
    func collectionNames() async throws -> [String: String] { [:] }
}

extension HomeControlStateTests {
    func testUnconfirmedHomeWriteSurvivesSameHubReconnect() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let reader = try HomeControlReader()
        let status = BoardStatus(store: store, reader: { reader })
        await reader.failNextMutation()
        await status.clearTemporaryOverride()
        XCTAssertTrue(status.homeControlNeedsReadback)
        await store.connect(try FixtureFiestaBoardService()).value
        XCTAssertTrue(status.homeControlNeedsReadback, "Reconnect is not an explicit verification of the mutation result")
        XCTAssertFalse(status.canClearOverride)
    }
}
