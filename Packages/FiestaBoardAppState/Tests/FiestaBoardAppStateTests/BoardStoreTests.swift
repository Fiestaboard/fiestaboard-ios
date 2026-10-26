import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class BoardStoreTests: XCTestCase {
    func testDemoLoadsAndCapturedTargetIsInvalidatedByBoardChange() async throws {
        let store = BoardStore()
        await store.connect(try DemoFiestaBoardService()).value
        XCTAssertEqual(store.status?.access, .simulated)
        XCTAssertEqual(store.board?.summary.id, "board-2")
        let action = try XCTUnwrap(store.prepare(.text("CAPTURED")))
        await store.selectBoard("board-led").value
        await store.confirm(action).value
        await store.selectBoard("board-2").value
        XCTAssertNotEqual(store.board?.text, "CAPTURED")
    }
    func testConfirmationUsesOriginalTextAndSuppressesDuplicateTap() async throws {
        let store = BoardStore()
        await store.connect(try DemoFiestaBoardService()).value
        let action = try XCTUnwrap(store.prepare(.text("ORIGINAL")))
        let first = store.confirm(action)
        XCTAssertTrue(store.commandBusy)
        let second = store.confirm(action)
        await first.value; await second.value
        XCTAssertEqual(store.board?.text, "ORIGINAL")
        XCTAssertFalse(store.commandBusy)
        XCTAssertTrue(store.message?.contains("Simulated") == true)
    }
    func testUnknownOutcomeRequiresReadbackAndDoesNotReplay() async throws {
        let demo = try DemoFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("MAYBE")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("unknown") == true)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback)
        XCTAssertEqual(store.board?.text, "MAYBE")
    }
    func testHeldPageSeparatesSelectionFromReportedOutput() async throws {
        let demo = try DemoFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        let previous = store.board?.characters
        await demo.setSimulation(.held)
        await store.confirm(try XCTUnwrap(store.prepare(.page("page-weather")))).value
        XCTAssertEqual(store.board?.activePageID, "page-weather")
        XCTAssertEqual(store.board?.characters, previous)
        XCTAssertTrue(store.message?.contains("selection stored") == true)
    }
    func testLateBoardSnapshotCannotReplaceAnotherBoard() async throws {
        let delayed = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(delayed).value
        await delayed.delayNextRead()
        let oldRead = store.refresh()
        await delayed.waitUntilBlocked()
        await store.selectBoard("board-led").value
        await delayed.release()
        await oldRead.value
        XCTAssertEqual(store.board?.summary.id, "board-led")
    }
    func testTargetRemainsLockedAfterChangingAwayDuringCommandUntilReadback() async throws {
        let delayed = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(delayed).value
        await delayed.delayNextMutation()
        let action = try XCTUnwrap(store.prepare(.text("ONCE")))
        let command = store.confirm(action)
        let duplicate = store.confirm(action)
        await delayed.waitUntilBlocked()
        await store.selectBoard("board-led").value
        await store.selectBoard("board-2").value
        XCTAssertTrue(store.commandBusy)
        await delayed.release()
        await command.value; await duplicate.value
        let count = await delayed.sentCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback)
        XCTAssertTrue(store.canWrite)
        XCTAssertEqual(store.board?.text, "ONCE")
    }
    func testPartialAndRejectedOutcomesAreNotAcknowledgedAsSuccess() async throws {
        let demo = try DemoFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.partial)
        await store.confirm(try XCTUnwrap(store.prepare(.text("PART")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertTrue(store.message?.contains("Only part") == true)
        await store.refresh().value
        await demo.setSimulation(.rejected)
        await store.confirm(try XCTUnwrap(store.prepare(.text("REFUSED")))).value
        XCTAssertTrue(store.message?.contains("refused") == true)
        XCTAssertNotEqual(store.board?.text, "REFUSED")
    }
    func testLateConnectionCannotRestoreDisconnectedSession() async throws {
        let delayed = try DelayedService()
        let store = BoardStore()
        let task = store.connect(delayed)
        await delayed.waitUntilBlocked()
        store.disconnect()
        await delayed.release()
        await task.value
        XCTAssertNil(store.status)
        XCTAssertNil(store.board)
        XCTAssertTrue(store.boards.isEmpty)
        XCTAssertEqual(store.connectionLabel, "Disconnected")
    }
    func testOldServerResultCannotReplaceNewDemo() async throws {
        let delayed = try DelayedService()
        let store = BoardStore()
        let first = store.connect(delayed)
        await delayed.waitUntilBlocked()
        await store.connect(try DemoFiestaBoardService()).value
        await delayed.release()
        await first.value
        XCTAssertEqual(store.status?.access, .simulated)
        XCTAssertEqual(store.board?.summary.id, "board-2")
        XCTAssertNil(store.message)
    }
}

// Delays an actual demo connect result even after task cancellation, modeling a late server reply.
private actor DelayedService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = true
    private let demo: DemoFiestaBoardService
    private let delayConnection: Bool
    private var delayRead = false
    private var delayMutation = false
    private(set) var sentCount = 0
    func delayNextRead() { delayRead = true }
    func delayNextMutation() { delayMutation = true }
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    init(delayConnection: Bool = true) throws { let d = try DemoFiestaBoardService(); demo = d; deployment = d.deployment; self.delayConnection = delayConnection }
    func waitUntilBlocked() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func release() { gate?.resume(); gate = nil }
    func authStatus() async throws -> AuthStatus { try await demo.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await demo.login(username: username, password: password) }
    func logout() async throws { try await demo.logout() }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        let value = try await demo.connect(allowCandidateWrites: allowCandidateWrites)
        if delayConnection { await hold() }
        return value
    }
    private func hold() async {
        await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] }
    }
    func boards() async throws -> [BoardSummary] { try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail {
        let detail = try await demo.board(target)
        if delayRead { delayRead = false; await hold() }
        return detail
    }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult {
        sentCount += 1
        let result = try await demo.sendText(text, to: target)
        if delayMutation { delayMutation = false; await hold() }
        return result
    }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await demo.selectPage(id: id, on: target) }
}
