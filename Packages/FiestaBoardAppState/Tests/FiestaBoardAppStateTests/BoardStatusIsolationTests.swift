import Combine
import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class BoardStatusIsolationTests: XCTestCase {
    func testRestartRejectsOldHubStatusFramesAppearanceAndActivePage() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let old = try DelayedStatusReader(marker: "old", blocked: true)
        let fresh = try DelayedStatusReader(marker: "fresh", blocked: false)
        var reader: any BoardStatusReading = old
        let status = BoardStatus(store: store, reader: { reader })
        defer { status.stop() }
        status.start()
        await old.gate.waitUntilCalled(["settings", "runtime", "message", "schedule", "manual", "silence"])
        reader = fresh
        status.start()
        await waitForFresh(status)
        await assertNoOldReplies(status, releasing: old)
        XCTAssertEqual(status.runtime["board-2"]?.error, "fresh")
        XCTAssertEqual(status.frames["board-led"]?.message, "fresh")
        XCTAssertEqual(status.display.flapStepMs, 48)
        XCTAssertTrue(status.nowShowing?.name.hasPrefix("fresh") == true)
        XCTAssertEqual(status.outOfSync?.grid, [[2]])
    }
    func testStoreReconnectRejectsOldReplyWithoutExplicitStatusRestart() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let old = try DelayedStatusReader(marker: "old", blocked: true)
        let status = BoardStatus(store: store, reader: { old })
        defer { status.stop() }
        status.start()
        await old.gate.waitUntilCalled(["settings", "runtime", "message", "schedule", "manual", "silence"])
        await store.connect(try FixtureFiestaBoardService()).value
        await assertNoOldReplies(status, releasing: old)
        XCTAssertTrue(status.runtime.isEmpty)
        XCTAssertTrue(status.frames.isEmpty)
        XCTAssertNil(status.outOfSync)
    }
    func testStopRejectsAlreadyDispatchedReplies() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let old = try DelayedStatusReader(marker: "old", blocked: true)
        let status = BoardStatus(store: store, reader: { old })
        status.start()
        await old.gate.waitUntilCalled(["settings", "runtime", "message", "schedule", "manual", "silence"])
        status.stop()
        await assertNoOldReplies(status, releasing: old)
        XCTAssertTrue(status.runtime.isEmpty)
        XCTAssertTrue(status.frames.isEmpty)
        XCTAssertNil(status.outOfSync)
    }
    func testOldOverrideFailureCannotSetNewHubError() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let old = try DelayedStatusReader(marker: "old", blocked: true)
        let fresh = try DelayedStatusReader(marker: "fresh", blocked: false)
        var reader: any BoardStatusReading = old
        let status = BoardStatus(store: store, reader: { reader })
        defer { status.stop() }
        let cancel = Task { await status.clearTemporaryOverride() }
        await old.gate.waitUntilCalled(["clear"])
        reader = fresh
        status.start()
        await waitForFresh(status)
        await old.gate.release()
        await cancel.value
        XCTAssertFalse(status.overrideClearFailed, "A failed old-hub mutation cannot annotate the new hub")
        XCTAssertEqual(status.runtime["board-2"]?.error, "fresh")
    }

    func testHubStatusFailurePublishesReachabilityWithoutDisplayRead() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let reader = try DelayedStatusReader(marker: "unreachable", blocked: false)
        let status = BoardStatus(store: store, reader: { reader })
        defer { status.stop() }
        let failed = expectation(description: "hub-level status failure invalidates reachability")
        let subscription = store.$hubReachable.dropFirst().filter { $0 == false }.first().sink { _ in failed.fulfill() }
        status.start()
        await fulfillment(of: [failed], timeout: 3)
        subscription.cancel()
        XCTAssertEqual(store.hubReachable, false)
    }

    func testStatusReplyFromEarlierPathCannotConfirmReachability() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let reader = try DelayedStatusReader(marker: "old", blocked: true)
        let status = BoardStatus(store: store, reader: { reader })
        defer { status.stop() }
        let replied = expectation(description: "earlier-path status response completed")
        let subscription = status.$runtime.filter { $0["board-2"]?.error == "old" }.first().sink { _ in replied.fulfill() }
        status.start()
        await reader.gate.waitUntilCalled(["runtime"])
        store.networkAvailable = false
        store.networkAvailable = true
        await reader.gate.release()
        await fulfillment(of: [replied], timeout: 3)
        subscription.cancel()
        XCTAssertEqual(store.hubReachable, false)
        await store.probeReachability().value
        XCTAssertEqual(store.hubReachable, true)
    }

    private func waitForFresh(_ status: BoardStatus) async {
        let done = expectation(description: "new hub facts published")
        let token = Publishers.CombineLatest4(status.$runtime, status.$frames, status.$display, status.$nowShowing)
            .filter { runtime, frames, display, showing in
                runtime["board-2"]?.error == "fresh" && frames["board-led"]?.message == "fresh"
                    && display.flapStepMs == 48 && showing?.name.hasPrefix("fresh") == true
            }.first().sink { _ in done.fulfill() }
        await fulfillment(of: [done], timeout: 3)
        token.cancel()
    }
    private func assertNoOldReplies(_ status: BoardStatus, releasing reader: DelayedStatusReader) async {
        var sawOldReply = false
        var tokens = Set<AnyCancellable>()
        status.$runtime.filter { $0["board-2"]?.error == "old" }.first()
            .sink { _ in sawOldReply = true }.store(in: &tokens)
        status.$frames.filter { $0["board-led"]?.message == "old" }.first()
            .sink { _ in sawOldReply = true }.store(in: &tokens)
        status.$display.filter { $0.flapStepMs == 130 }.first()
            .sink { _ in sawOldReply = true }.store(in: &tokens)
        status.$nowShowing.filter { $0?.name.hasPrefix("old") == true }.first()
            .sink { _ in sawOldReply = true }.store(in: &tokens)
        status.$outOfSync.filter { $0?.grid == [[1]] }.first()
            .sink { _ in sawOldReply = true }.store(in: &tokens)
        await reader.gate.release()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(sawOldReply, "No old hub reply may publish after the connection epoch changes")
    }
}
private actor StatusReplyGate {
    private var blocked: Bool
    private var called: Set<String> = []
    private var calls: [(Set<String>, CheckedContinuation<Void, Never>)] = []
    private var replies: [CheckedContinuation<Void, Never>] = []
    init(blocked: Bool) { self.blocked = blocked }
    func wait(_ kind: String) async {
        called.insert(kind)
        let ready = calls.filter { $0.0.isSubset(of: called) }
        calls.removeAll { $0.0.isSubset(of: called) }
        ready.forEach { $0.1.resume() }
        if blocked { await withCheckedContinuation { replies.append($0) } }
    }
    func waitUntilCalled(_ kinds: Set<String>) async {
        if !kinds.isSubset(of: called) { await withCheckedContinuation { calls.append((kinds, $0)) } }
    }
    func release() { blocked = false; let pending = replies; replies = []; pending.forEach { $0.resume() } }
}
private actor DelayedStatusReader: BoardStatusReading, TemporaryOverrideClearing {
    let marker: String
    let gate: StatusReplyGate
    nonisolated let deployment: DeploymentURL
    init(marker: String, blocked: Bool) throws {
        self.marker = marker; gate = StatusReplyGate(blocked: blocked)
        deployment = try DeploymentURL("https://\(marker).example.invalid")
    }
    func clearTemporaryOverride(boardID: String) async throws {
        await gate.wait("clear")
        throw URLError(.cannotConnectToHost)
    }
    func boardSettings() async throws -> [StoredBoardEntry] { await gate.wait("settings"); return [] }
    func serviceStatus() async throws -> ServiceStatusReport {
        await gate.wait("runtime")
        if marker == "unreachable" { throw FiestaBoardError.networkUnavailable }
        return try JSONDecoder().decode(ServiceStatusReport.self,
            from: Data("{\"boards\":{\"board-2\":{\"error\":\"\(marker)\"}}}".utf8))
    }
    func currentMessage(boardID: String) async throws -> CurrentBoardMessage {
        await gate.wait("message")
        if boardID == "board-led" {
            return try JSONDecoder().decode(CurrentBoardMessage.self, from: Data("{\"message\":\"\(marker)\"}".utf8))
        }
        return try JSONDecoder().decode(CurrentBoardMessage.self,
            from: Data("{\"message\":\"\(marker)\",\"characters\":[[\(marker == "old" ? 1 : 2)]],\"expected_characters\":[[0]]}".utf8))
    }
    func activeSchedulePage(boardID: String) async throws -> ActivePageStatus {
        await gate.wait("schedule"); return .init(pageID: "collection:rotation", scheduleEnabled: true)
    }
    func activePage(boardID: String) async throws -> ActivePageStatus { await gate.wait("manual"); return .init(pageID: nil) }
    func silenceStatus(boardID: String) async throws -> SilenceStatus { await gate.wait("silence"); return .init(active: false) }
    func displaySettings() async throws -> BoardDisplaySettings { .init(boardFlapSpeed: marker == "old" ? "relaxed" : "quick") }
    func collectionNames() async throws -> [String: String] { ["rotation": marker] }
}
