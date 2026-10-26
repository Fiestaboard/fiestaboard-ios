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
    func testRefreshAuthenticationLossInvalidatesControlsAndCapturedConfirmation() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertEqual(store.status?.access, .candidateWrites)
        let captured = try XCTUnwrap(store.prepare(.text("STALE")))
        await service.rejectNextRead()
        await store.refresh().value
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("sign in again") == true)
        await store.confirm(captured).value
        let sends = await service.sentCount
        XCTAssertEqual(sends, 0)
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertTrue(store.canWrite)
        await store.confirm(captured).value
        let sendsAfterReauthentication = await service.sentCount
        XCTAssertEqual(sendsAfterReauthentication, 0, "A confirmation from the expired session stays invalid after reconnecting")
    }
    func testAcknowledgedMutationReceiptSurvivesAuthenticationLossDuringReadback() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        let action = try XCTUnwrap(store.prepare(.text("ACKNOWLEDGED")))
        await service.rejectNextRead()
        await store.confirm(action).value
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("server acknowledged a send") == true)
        XCTAssertTrue(store.message?.contains("sign in again") == true)
        await store.confirm(action).value
        let sends = await service.sentCount
        XCTAssertEqual(sends, 1, "Readback authentication failure must not replay the acknowledged write")
    }
    func testFailedRemoteLogoutIsVisibleAfterImmediateLocalDisconnect() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service).value
        await service.configureLogout(fails: true, delayed: true)
        let logout = store.logout()
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("Signing out") == true)
        XCTAssertEqual(store.remoteLogoutState, .pending)
        await service.waitForLogout()
        await service.releaseLogout()
        await logout.value
        XCTAssertEqual(store.remoteLogoutState, .failed)
        XCTAssertTrue(store.message?.contains("could not be confirmed") == true)
        XCTAssertTrue(store.message?.contains("may still be active") == true)
    }
    func testSuccessfulRemoteLogoutIsAcknowledgedAfterImmediateLocalDisconnect() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service).value
        await store.logout().value
        XCTAssertNil(store.status)
        XCTAssertEqual(store.remoteLogoutState, .succeeded)
        XCTAssertTrue(store.message?.contains("Server sign-out confirmed") == true)
    }
    func testLateOldLogoutCannotOverwriteNewConnectionOrMessage() async throws {
        for fails in [false, true] {
            let old = try SessionFaultService()
            let store = BoardStore()
            await store.connect(old).value
            await old.configureLogout(fails: fails, delayed: true)
            let logout = store.logout()
            await old.waitForLogout()
            await store.connect(try DemoFiestaBoardService()).value
            let selected = try XCTUnwrap(store.prepare(.text("NEW SESSION")))
            await store.confirm(selected).value
            let newMessage = store.message
            await old.releaseLogout()
            await logout.value
            XCTAssertEqual(store.status?.access, .simulated)
            XCTAssertEqual(store.connectionLabel, "Demo · simulated")
            XCTAssertEqual(store.board?.text, "NEW SESSION")
            XCTAssertEqual(store.message, newMessage)
            XCTAssertNil(store.remoteLogoutState)
        }
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

// Real demo data/actions with bounded faults at the service boundary; never constructs networking.
private actor SessionFaultService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    private let demo: DemoFiestaBoardService
    private var rejectRead = false
    private var failLogout = false
    private var delayLogout = false
    private var logoutGate: CheckedContinuation<Void, Never>?
    private var logoutObservers: [CheckedContinuation<Void, Never>] = []
    private(set) var sentCount = 0
    init() throws { let demo = try DemoFiestaBoardService(); self.demo = demo; deployment = demo.deployment }
    func rejectNextRead() { rejectRead = true }
    func configureLogout(fails: Bool, delayed: Bool) { failLogout = fails; delayLogout = delayed }
    func waitForLogout() async {
        if logoutGate != nil { return }
        await withCheckedContinuation { logoutObservers.append($0) }
    }
    func releaseLogout() { logoutGate?.resume(); logoutGate = nil }
    func authStatus() async throws -> AuthStatus { try await demo.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await demo.login(username: username, password: password) }
    func logout() async throws {
        if delayLogout {
            await withCheckedContinuation { logoutGate = $0; logoutObservers.forEach { $0.resume() }; logoutObservers = [] }
        }
        if failLogout { throw FiestaBoardError.networkUnavailable }
        try await demo.logout()
    }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        let status = try await demo.connect(allowCandidateWrites: true)
        // Only the UI permission projection differs from demo; service data/actions remain real and isolated.
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        value["access"] = "candidateWrites"; value["isDemo"] = false
        return try JSONDecoder().decode(ConnectionStatus.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func boards() async throws -> [BoardSummary] { try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail {
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        return try await demo.board(target)
    }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult {
        sentCount += 1
        return try await demo.sendText(text, to: target)
    }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await demo.selectPage(id: id, on: target) }
}
