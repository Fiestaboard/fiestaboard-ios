import XCTest
import FiestaBoardKit
@testable import FiestaBoardEditorState

/// Fake clock: `sleep` suspends until `advance()`; cancelled sleepers throw.
@MainActor final class ManualSleeper {
    private var waiters: [(id: Int, continuation: CheckedContinuation<Void, any Error>)] = []
    private var next = 0
    private(set) var requested: [Duration] = []
    var pending: Int { waiters.count }
    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        let id = next; next += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in waiters.append((id, continuation)) }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }
    private func cancel(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    /// Fire every pending timer (the idle interval elapsed for all of them).
    func advance() { let current = waiters; waiters = []; current.forEach { $0.continuation.resume() } }
}

/// Render double: each call suspends until the test answers it.
@MainActor final class ScriptedRenderer {
    private(set) var calls = 0
    private var replies: [CheckedContinuation<PreviewRender, any Error>] = []
    var waiting: Int { replies.count }
    func render() async throws -> PreviewRender {
        calls += 1
        return try await withCheckedThrowingContinuation { replies.append($0) }
    }
    func answer(_ lines: [String]) throws {
        let raw = try JSONSerialization.data(withJSONObject: ["rendered": lines.joined(separator: "\n"), "lines": lines, "line_count": lines.count])
        replies.removeFirst().resume(returning: .server(try TemplatePreviewResult(rawData: raw)))
    }
    func fail() { replies.removeFirst().resume(throwing: FiestaBoardError.rejected(status: 500)) }
}

@MainActor final class PreviewPipelineTests: XCTestCase {
    private var clock: ManualSleeper!
    private var renderer: ScriptedRenderer!
    private var commits = 0

    private func makePipeline() -> PreviewPipeline {
        clock = ManualSleeper(); renderer = ScriptedRenderer(); commits = 0
        let clock = clock!, renderer = renderer!
        return PreviewPipeline(sleep: { try await clock.sleep($0) }, commit: { [unowned self] in self.commits += 1 },
                               render: { try await renderer.render() })
    }
    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    func testPreviewTimingMeasuresLatestInputAndRejectsStaleReplies() async throws {
        let pipeline = makePipeline()
        var now: TimeInterval = 10
        pipeline.diagnosticNow = { now }
        pipeline.edited(); await settle(); clock.advance(); await settle()
        now = 11
        pipeline.edited(); await settle(); clock.advance(); await settle()
        try renderer.answer(["OLD"]); await settle()
        XCTAssertNil(pipeline.state.inputToPreviewSeconds)
        XCTAssertTrue(pipeline.state.inputToPreviewPhases.isEmpty)
        now = 11.3
        try renderer.answer(["NEW"]); await settle()
        XCTAssertEqual(try XCTUnwrap(pipeline.state.inputToPreviewSeconds), 0.3, accuracy: 0.0001)
        pipeline.edited()
        XCTAssertNil(pipeline.state.inputToPreviewSeconds)
        XCTAssertTrue(pipeline.state.inputToPreviewPhases.isEmpty)
    }

    func testPreviewPhasesSeparateCommitAndRenderWithoutChangingTotal() async throws {
        let timer = ManualSleeper(), renderer = ScriptedRenderer()
        var now: TimeInterval = 10
        let pipeline = PreviewPipeline(sleep: { try await timer.sleep($0) },
                                       commit: { now = 10.4 }, render: { try await renderer.render() })
        pipeline.diagnosticNow = { now }
        pipeline.edited(); await settle()
        now = 10.25; timer.advance(); await settle()
        now = 10.6; try renderer.answer(["NEW"]); await settle()
        XCTAssertEqual(try XCTUnwrap(pipeline.state.inputToPreviewSeconds), 0.6, accuracy: 0.0001)
        for (phase, expected) in [("fireEntered", 0.25), ("commitReturned", 0.4),
                                  ("renderStarted", 0.4), ("renderReturned", 0.6)] {
            XCTAssertEqual(try XCTUnwrap(pipeline.state.inputToPreviewPhases[phase]), expected, accuracy: 0.0001)
        }
    }

    func testDebounceCommitsOnceAfterTwoHundredFiftyMillisecondsOfIdle() async throws {
        let pipeline = makePipeline()
        for _ in 0..<5 { pipeline.edited(); await settle() }
        XCTAssertEqual(clock.requested.last, .milliseconds(250))
        XCTAssertEqual(commits, 0, "Nothing commits while typing continues")
        XCTAssertEqual(renderer.calls, 0)
        XCTAssertTrue(pipeline.state.isStale)
        clock.advance(); await settle()
        XCTAssertEqual(commits, 1, "Five keystrokes, one idle commit")
        XCTAssertEqual(renderer.calls, 1)
        XCTAssertTrue(pipeline.state.isUpdating)
        try renderer.answer(["HELLO"]); await settle()
        XCTAssertEqual(pipeline.state.lines, ["HELLO"])
        XCTAssertFalse(pipeline.state.isStale); XCTAssertFalse(pipeline.state.isUpdating)
    }

    func testInFlightInputCoalescesIntoOneFollowUp() async throws {
        let pipeline = makePipeline()
        pipeline.edited(); await settle(); clock.advance(); await settle()
        XCTAssertEqual(renderer.calls, 1)
        // Three more idle bursts while the first render is still in flight.
        for _ in 0..<3 { pipeline.edited(); await settle(); clock.advance(); await settle() }
        XCTAssertEqual(commits, 4)
        XCTAssertEqual(renderer.calls, 1, "No second request while one is in flight")
        try renderer.answer(["OLD"]); await settle()
        XCTAssertEqual(pipeline.state.lines, ["OLD"])
        XCTAssertTrue(pipeline.state.isStale, "Input arrived after this frame was requested")
        XCTAssertEqual(renderer.calls, 2, "Exactly one follow-up for all coalesced input")
        try renderer.answer(["NEW"]); await settle()
        XCTAssertEqual(pipeline.state.lines, ["NEW"])
        XCTAssertFalse(pipeline.state.isStale); XCTAssertFalse(pipeline.state.isUpdating)
        XCTAssertEqual(renderer.calls, 2)
    }

    func testHoldsLastFrameWhileStaleAndUpdating() async throws {
        let pipeline = makePipeline()
        pipeline.flush(); await settle(); try renderer.answer(["FIRST"]); await settle()
        pipeline.edited(); await settle()
        XCTAssertEqual(pipeline.state.lines, ["FIRST"], "Never blank while stale")
        clock.advance(); await settle()
        XCTAssertTrue(pipeline.state.isUpdating)
        XCTAssertEqual(pipeline.state.lines, ["FIRST"], "Never blank while in flight")
    }

    func testFailureKeepsFrameAndNeverRetriesAutomatically() async throws {
        let pipeline = makePipeline()
        pipeline.flush(); await settle(); try renderer.answer(["KEEP"]); await settle()
        pipeline.edited(); await settle(); clock.advance(); await settle()
        renderer.fail(); await settle()
        XCTAssertEqual(pipeline.state.lines, ["KEEP"])
        XCTAssertNotNil(pipeline.state.failure)
        XCTAssertFalse(pipeline.state.isUpdating)
        for _ in 0..<3 { clock.advance(); await settle() }
        XCTAssertEqual(renderer.calls, 2, "No automatic retry")
        pipeline.retry(); await settle()
        XCTAssertEqual(renderer.calls, 3, "Explicit retry only")
        try renderer.answer(["BACK"]); await settle()
        XCTAssertNil(pipeline.state.failure)
        XCTAssertEqual(pipeline.state.lines, ["BACK"])
    }

    func testGenerationGuardDiscardsRepliesForAnOldTarget() async throws {
        let pipeline = makePipeline()
        pipeline.flush(); await settle()
        pipeline.targetChanged(); await settle()   // e.g. the stage display changed mid-flight
        try renderer.answer(["FOR OLD BOARD"]); await settle()
        XCTAssertNil(pipeline.state.lines, "A reply for the previous display is never shown")
        XCTAssertEqual(renderer.calls, 2)
        try renderer.answer(["FOR NEW BOARD"]); await settle()
        XCTAssertEqual(pipeline.state.lines, ["FOR NEW BOARD"])
    }

    func testCancelStopsTimersAndDropsLateReplies() async throws {
        let pipeline = makePipeline()
        pipeline.flush(); await settle()
        pipeline.edited(); await settle()
        pipeline.cancel(); await settle()
        clock.advance(); await settle()
        XCTAssertEqual(commits, 1, "A cancelled timer never commits")
        try renderer.answer(["LATE"]); await settle()
        XCTAssertNil(pipeline.state.lines)
        XCTAssertEqual(renderer.calls, 1)
    }

    func testLocalRenderClearsFrameWithoutError() async throws {
        clock = ManualSleeper(); let clock = clock!
        let pipeline = PreviewPipeline(sleep: { try await clock.sleep($0) }, commit: {}, render: { .local })
        pipeline.flush(); await settle()
        XCTAssertNil(pipeline.state.lines); XCTAssertNil(pipeline.state.failure); XCTAssertFalse(pipeline.state.isUpdating)
        XCTAssertEqual(pipeline.state.adoptedRenders, 1)
    }
}

final class LocalStageProjectionTests: XCTestCase {
    func testUppercaseAlignTruncateAndTiles() {
        let lines = LocalStageProjection.lines(rows: ["hi {{red}}", "{{weather.temp}}", String(repeating: "X", count: 30)],
            alignment: { $0 == 0 ? "center" : "left" }, boardRows: 4, cols: 22, uppercase: true)
        XCTAssertEqual(lines.count, 4, "One line per board row")
        XCTAssertEqual(lines[0], String(repeating: " ", count: 9) + "HI {red}")
        XCTAssertEqual(lines[1], "WEATHER.TEMP", "Tokens are never evaluated")
        XCTAssertEqual(lines[2].count, 22, "Cut at the board width")
        XCTAssertEqual(lines[3], "")
        XCTAssertEqual(LocalStageProjection.lines(rows: ["Hi"], alignment: { _ in "right" }, boardRows: 1, cols: 4, uppercase: false), ["  Hi"])
    }
}

final class FlapInputCaseTests: XCTestCase {
    func testOnlyTextOutsideTokensIsUppercased() {
        XCTAssertEqual(FlapInputCase.uppercased("hello {{weather.temp|pad:3}} world", openBefore: false), "HELLO {{weather.temp|pad:3}} WORLD")
        XCTAssertEqual(FlapInputCase.uppercased("temp", openBefore: true), "temp")
        XCTAssertEqual(FlapInputCase.uppercased("p}} ok", openBefore: true), "p}} OK")
        XCTAssertTrue(FlapInputCase.isInsideToken(rowPrefix: "A {{weather."))
        XCTAssertFalse(FlapInputCase.isInsideToken(rowPrefix: "A {{red}} b"))
        XCTAssertFalse(FlapInputCase.isInsideToken(rowPrefix: "plain"))
    }
}
