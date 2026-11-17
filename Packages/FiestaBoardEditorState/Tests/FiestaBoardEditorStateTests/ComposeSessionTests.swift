import XCTest
import FiestaBoardKit
import FiestaBoardDocuments
@testable import FiestaBoardEditorState
#if DEBUG
import CryptoKit
#endif

@MainActor private final class ComposeRenderGate {
    var inputs: [ComposePreviewInput] = []
    private var replies: [CheckedContinuation<TemplatePreviewResult, any Error>] = []
    var waiting: Int { replies.count }
    func render(_ input: ComposePreviewInput) async throws -> TemplatePreviewResult {
        inputs.append(input)
        return try await withCheckedThrowingContinuation { replies.append($0) }
    }
    func answer(_ value: TemplatePreviewResult) { replies.removeFirst().resume(returning:value) }
    func fail() { replies.removeFirst().resume(throwing:FiestaBoardError.networkUnavailable) }
}

#if DEBUG
/// Synthetic host ticks exercise ownership and arithmetic only. These tests do
/// not capture native pixels or establish a presentation-performance result.
@MainActor private final class ComposePresentationTestClock {
    var ticks: UInt64 = 1_000
}

extension ComposeSessionTests {
    private func presentationSession(target: ComposeScope? = nil) throws
        -> (ComposeSession, ManualSleeper, ComposeRenderGate, ComposePresentationTestClock) {
        let idle = ManualSleeper(), renderer = ComposeRenderGate(), clock = ComposePresentationTestClock()
        let session = ComposeSession(scope: try target ?? scope(), sleep: { try await idle.sleep($0) },
            monotonicNow: { Double(clock.ticks) / 1_000 }, render: { try await renderer.render($0) })
        session.enableCapturedPresentationDiagnostics(nowTicks: { clock.ticks }, secondsPerTick: 0.001)
        return (session, idle, renderer, clock)
    }

    func testCapturedPresentationRequiresPixelMatchedEvidenceAfterAdoptionAndPreservesAdoptionMetrics() async throws {
        let (session, idle, renderer, clock) = try presentationSession()
        session.update(.init(text: "FRAME A")); await settle()
        XCTAssertNil(session.capturedPresentationTicket)
        XCTAssertNil(session.firstObservedPresentation)
        clock.ticks = 1_250; idle.advance(); await settle()
        XCTAssertNil(session.capturedPresentationTicket, "Dispatch is not a drawn or presented result")
        let result = try reply("FRAME A")
        clock.ticks = 1_350; renderer.answer(result); await settle()
        let ticket = try XCTUnwrap(session.capturedPresentationTicket)
        XCTAssertEqual(ticket.scope, session.scope)
        XCTAssertEqual(ticket.readyTicks, 1_250); XCTAssertEqual(ticket.adoptedTicks, 1_350)
        XCTAssertEqual(ticket.responseDigest, SHA256.hash(data: result.rawData).map { String(format: "%02x", $0) }.joined())
        XCTAssertNil(session.firstObservedPresentation, "Result adoption alone cannot record native presentation")
        XCTAssertEqual(try XCTUnwrap(session.postDebouncePreviewSeconds), 0.100, accuracy: 0.000001)
        clock.ticks = 1_450 // Capture callback arrives after the actual captured frame timestamp.
        let pixels = String(repeating: "a", count: 64)
        XCTAssertTrue(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_420,
            responseDigest: ticket.responseDigest, pixelDigest: pixels))
        let observed = try XCTUnwrap(session.firstObservedPresentation)
        XCTAssertEqual(observed.ticket, ticket); XCTAssertEqual(observed.displayTicks, 1_420)
        XCTAssertEqual(observed.pixelDigest, pixels)
        XCTAssertEqual(observed.postDebounceUpperBoundSeconds, 0.170, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(observed.inputToObservedUpperBoundSeconds), 0.420, accuracy: 0.000001)
        XCTAssertEqual(observed.adoptionToObservedUpperBoundSeconds, 0.070, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(session.postDebouncePreviewSeconds), 0.100, accuracy: 0.000001,
            "The adoption metric retains its existing meaning and name")
        XCTAssertFalse(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_430,
            responseDigest: ticket.responseDigest, pixelDigest: pixels), "One matched observation per ticket")
        XCTAssertEqual(session.firstObservedPresentation?.displayTicks, 1_420)
        session.close()
    }

    func testCapturedPresentationIncludesWaitBehindOlderInFlightRequestAfterLatestDebounce() async throws {
        let (session, idle, renderer, clock) = try presentationSession()
        session.update(.init(text: "OLD")); await settle()
        clock.ticks = 1_250; idle.advance(); await settle()
        clock.ticks = 1_260; session.update(.init(text: "LATEST")); await settle()
        clock.ticks = 1_510; idle.advance(); await settle()
        XCTAssertEqual(renderer.inputs.count, 1)
        clock.ticks = 1_700; renderer.answer(try reply("OLD")); await settle()
        XCTAssertNil(session.capturedPresentationTicket, "The obsolete result cannot mint a measurement ticket")
        XCTAssertEqual(renderer.inputs.count, 2)
        clock.ticks = 1_750; renderer.answer(try reply("LATEST")); await settle()
        let ticket = try XCTUnwrap(session.capturedPresentationTicket)
        XCTAssertEqual(ticket.readyTicks, 1_510, "Do not start at eventual dispatch and hide queue wait")
        clock.ticks = 1_810
        XCTAssertTrue(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_800,
            responseDigest: ticket.responseDigest, pixelDigest: String(repeating: "b", count: 64)))
        XCTAssertEqual(try XCTUnwrap(session.firstObservedPresentation).postDebounceUpperBoundSeconds, 0.290, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(session.postDebouncePreviewSeconds), 0.240, accuracy: 0.000001)
        session.close()
    }

    func testCapturedPresentationRejectsWrongResultAndInvalidTimestampsWithoutConsumingTicket() async throws {
        let (session, idle, renderer, clock) = try presentationSession()
        session.update(.init(text: "CURRENT")); await settle()
        clock.ticks = 1_250; idle.advance(); await settle()
        clock.ticks = 1_350; renderer.answer(try reply("CURRENT")); await settle()
        let ticket = try XCTUnwrap(session.capturedPresentationTicket), pixels = String(repeating: "c", count: 64)
        clock.ticks = 1_500
        XCTAssertFalse(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_400,
            responseDigest: String(repeating: "0", count: 64), pixelDigest: pixels), "An old pixel match cannot label the new response")
        for stamp in [UInt64(0), 1_249, 1_349, 1_501] {
            XCTAssertFalse(session.recordCapturedPresentation(ticket: ticket, displayTicks: stamp,
                responseDigest: ticket.responseDigest, pixelDigest: pixels), "Reject pre-adoption/future clock samples")
        }
        XCTAssertFalse(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_400,
            responseDigest: ticket.responseDigest, pixelDigest: ""), "Keep captured pixel evidence addressable")
        XCTAssertNil(session.firstObservedPresentation)
        XCTAssertTrue(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_400,
            responseDigest: ticket.responseDigest, pixelDigest: pixels))
        XCTAssertEqual(try XCTUnwrap(session.firstObservedPresentation).postDebounceUpperBoundSeconds, 0.150, accuracy: 0.000001)
        session.close()
    }

    func testCapturedPresentationTicketCannotSurviveEditScopeOfflineOrClose() async throws {
        let mutations: [(ComposeSession) throws -> Void] = [
            { $0.update(.init(text: "NEW INPUT")) },
            { $0.changeScope(try self.scope(board: "other")) },
            { $0.setOnline(false) },
            { $0.close() }
        ]
        for mutate in mutations {
            let (session, idle, renderer, clock) = try presentationSession()
            session.update(.init(text: "OLD VISIBLE")); await settle()
            clock.ticks = 1_250; idle.advance(); await settle()
            clock.ticks = 1_350; renderer.answer(try reply("OLD VISIBLE")); await settle()
            let ticket = try XCTUnwrap(session.capturedPresentationTicket)
            clock.ticks = 1_400; try mutate(session)
            XCTAssertNil(session.capturedPresentationTicket); XCTAssertNil(session.firstObservedPresentation)
            XCTAssertFalse(session.recordCapturedPresentation(ticket: ticket, displayTicks: 1_400,
                responseDigest: ticket.responseDigest, pixelDigest: String(repeating: "d", count: 64)))
            session.close(); await settle()
        }
    }

    func testFailedPreviewCannotMintPresentationEvidenceFromRetainedOldFrame() async throws {
        let (session, idle, renderer, clock) = try presentationSession()
        session.update(.init(text: "OLD FRAME")); await settle()
        clock.ticks = 1_250; idle.advance(); await settle()
        clock.ticks = 1_350; renderer.answer(try reply("OLD FRAME")); await settle()
        let old = try XCTUnwrap(session.capturedPresentationTicket)
        clock.ticks = 1_400; session.update(.init(text: "FAILED NEW FRAME")); await settle()
        clock.ticks = 1_650; idle.advance(); await settle()
        clock.ticks = 1_700; renderer.fail(); await settle()
        XCTAssertEqual(session.preview?.lines, ["OLD FRAME"])
        XCTAssertTrue(session.previewIsStale)
        XCTAssertNil(session.capturedPresentationTicket); XCTAssertNil(session.firstObservedPresentation)
        XCTAssertFalse(session.recordCapturedPresentation(ticket: old, displayTicks: 1_700,
            responseDigest: old.responseDigest, pixelDigest: String(repeating: "0", count: 64)))
        session.close()
    }

    func testCapturedPresentationRetryAndNewSessionRejectOldTicketEvenForIdenticalResultBytes() async throws {
        let sharedScope = try scope(), same = try reply("SAME PIXELS")
        let (session, idle, renderer, clock) = try presentationSession(target: sharedScope)
        session.update(.init(text: "SAME PIXELS")); await settle()
        clock.ticks = 1_250; idle.advance(); await settle()
        clock.ticks = 1_350; renderer.answer(same); await settle()
        let original = try XCTUnwrap(session.capturedPresentationTicket)
        session.setOnline(false); session.setOnline(true)
        clock.ticks = 1_400; session.retryPreview(); await settle()
        clock.ticks = 1_450; renderer.answer(same); await settle()
        let retry = try XCTUnwrap(session.capturedPresentationTicket)
        XCTAssertEqual(retry.sessionID, original.sessionID)
        XCTAssertEqual(retry.revision, original.revision); XCTAssertNotEqual(retry.renderID, original.renderID)
        XCTAssertEqual(retry.responseDigest, original.responseDigest)
        XCTAssertFalse(session.recordCapturedPresentation(ticket: original, displayTicks: 1_450,
            responseDigest: original.responseDigest, pixelDigest: String(repeating: "e", count: 64)))
        session.close()
        let (reopened, idle2, renderer2, clock2) = try presentationSession(target: sharedScope)
        reopened.update(.init(text: "SAME PIXELS")); await settle()
        clock2.ticks = 1_250; idle2.advance(); await settle()
        clock2.ticks = 1_350; renderer2.answer(same); await settle()
        let fresh = try XCTUnwrap(reopened.capturedPresentationTicket)
        XCTAssertNotEqual(fresh.sessionID, original.sessionID)
        XCTAssertEqual(fresh.revision, original.revision); XCTAssertEqual(fresh.responseDigest, original.responseDigest)
        clock2.ticks = 1_500
        XCTAssertFalse(reopened.recordCapturedPresentation(ticket: original, displayTicks: 1_400,
            responseDigest: original.responseDigest, pixelDigest: String(repeating: "f", count: 64)))
        XCTAssertNil(reopened.firstObservedPresentation)
        reopened.close()
    }
}
#endif

@MainActor final class ComposeSessionTests: XCTestCase {
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func scope(board: String = "kitchen", hub: String = "https://hub.test", connection: UUID = UUID()) throws -> ComposeScope {
        let deployment = try DeploymentURL(hub)
        return ComposeScope(identity:.init(deploymentID:deployment.description,installationID:"installed-A",principalID:"admin"),
            connectionID:connection,target:try BoardTarget(deployment:deployment,boardID:board),rows:6,cols:22)
    }
    private func reply(_ text: String, physical: Bool = false) throws -> TemplatePreviewResult {
        var value: [String:Any] = ["rendered":text,"lines":[text],"line_count":1,"charset":"ascii",
            "charset_issues":[],"canvas_issues":[],"layers":[]]
        if physical { value["layers"] = [["physical_frame_version":1,"x":0,"y":0,"width":2,"height":1,
            "rgba":Data([1,2,3,255,254,128,64,255]).base64EncodedString()]] }
        return try TemplatePreviewResult(rawData:JSONSerialization.data(withJSONObject:value))
    }
    func testIdleDebounceCapturesExactLatestInputAndFullTarget() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate(), target = try scope()
        let session = ComposeSession(scope:target,sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        session.update(.init(text:"H")); await settle()
        let input = ComposeInput(text:"Hi {{weather.temp}}",lineMetadata:[.init(alignment:"right",wrap:true)],
            selection:.init(lowerUTF16:3,upperUTF16:3),duration:.minutes(15),silence:.hold)
        session.update(input); await settle()
        XCTAssertEqual(clock.requested.last,.milliseconds(250)); XCTAssertTrue(renderer.inputs.isEmpty)
        clock.advance(); await settle()
        XCTAssertEqual(renderer.inputs.count,1); XCTAssertEqual(renderer.inputs[0].scope,target)
        XCTAssertEqual(renderer.inputs[0].input,input)
        renderer.answer(try reply("Hi 70")); await settle()
        XCTAssertFalse(session.previewIsStale)
    }
    func testCoalescedOldInputReplyCannotReplaceLastGoodRichFrame() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        session.update(.init(text:"FIRST")); await settle(); clock.advance(); await settle()
        let good = try reply("FIRST",physical:true); renderer.answer(good); await settle()
        session.update(.init(text:"OLD")); await settle(); clock.advance(); await settle()
        for text in ["NEW","NEWEST"] { session.update(.init(text:text)); await settle(); clock.advance(); await settle() }
        XCTAssertEqual(renderer.inputs.count,2)
        renderer.answer(try reply("OLD")); await settle()
        XCTAssertEqual(session.preview?.rawData,good.rawData,"Superseded response cannot replace useful last-known evidence")
        XCTAssertTrue(session.previewIsStale); XCTAssertEqual(renderer.inputs.count,3)
        XCTAssertEqual(renderer.inputs[2].input.text,"NEWEST")
        let latest = try reply("NEWEST",physical:true); renderer.answer(latest); await settle()
        XCTAssertEqual(session.preview?.rawData,latest.rawData)
        XCTAssertEqual(session.preview?.surface,latest.surface); XCTAssertEqual(session.preview?.layers.count,1)
        XCTAssertFalse(session.previewIsStale)
    }
    func testTargetConnectionAndHubChangesRejectPreviousScopeReplies() async throws {
        for changed in [try scope(board:"desk"),try scope()] {
            let clock = ManualSleeper(), renderer = ComposeRenderGate()
            let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
            session.update(.init(text:"CAPTURE")); await settle(); clock.advance(); await settle()
            session.changeScope(changed); await settle(); clock.advance(); await settle()
            renderer.answer(try reply("WRONG")); await settle()
            XCTAssertNil(session.preview); XCTAssertEqual(renderer.inputs.count,2)
            XCTAssertEqual(renderer.inputs[1].scope,changed)
            renderer.answer(try reply("CURRENT")); await settle()
            XCTAssertEqual(session.preview?.lines,["CURRENT"])
        }
    }
    func testIdentityChangeCannotForwardFormerHubsTextOrFrame() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        session.update(.init(text:"PRIVATE TO FIRST HUB")); await settle(); clock.advance(); await settle()
        session.changeScope(try scope(hub:"https://other.test")); await settle(); clock.advance(); await settle()
        XCTAssertEqual(session.input.text,"")
        XCTAssertEqual(renderer.inputs.count,1,"Do not forward the previous household's unsent input to a new hub")
        renderer.answer(try reply("OLD HUB")); await settle()
        XCTAssertNil(session.preview); XCTAssertNil(session.prepare())
        session.close(); await settle()
        while renderer.waiting > 0 { renderer.answer(try reply("DISCARDED")); await settle() }
    }
    func testFailedPreviewKeepsEvidenceAndRequiresExplicitRetry() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        session.update(.init(text:"KEEP")); await settle(); clock.advance(); await settle()
        renderer.answer(try reply("KEEP",physical:true)); await settle()
        session.update(.init(text:"UNAVAILABLE")); await settle(); clock.advance(); await settle()
        renderer.fail(); await settle()
        XCTAssertEqual(session.preview?.lines,["KEEP"]); XCTAssertTrue(session.previewIsStale)
        XCTAssertNotNil(session.previewFailure)
        clock.advance(); await settle(); XCTAssertEqual(renderer.inputs.count,2)
        session.retryPreview(); await settle(); XCTAssertEqual(renderer.inputs.count,3)
        renderer.answer(try reply("RECOVERED")); await settle(); XCTAssertNil(session.previewFailure)
    }
    #if DEBUG
    func testLatencyExcludesDeliberateDebounceWithoutRelaxingPostDebounceBudget() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        var now = 10.0
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },monotonicNow:{ now },render:{ try await renderer.render($0) })
        session.update(.init(text:"TIMED")); await settle()
        now = 10.25; clock.advance(); await settle()
        now = 10.35; renderer.answer(try reply("TIMED")); await settle()
        XCTAssertEqual(try XCTUnwrap(session.postDebouncePreviewSeconds),0.10,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(session.inputToPreviewSeconds),0.35,accuracy:0.00001)
    }
    #endif
    func testOfflineAndCloseKeepInputButDoNotAdoptLatePreviewOrSend() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        session.update(.init(text:"UNSENT")); await settle(); clock.advance(); await settle()
        session.setOnline(false)
        XCTAssertNil(session.prepare())
        renderer.answer(try reply("LATE")); await settle(); XCTAssertNil(session.preview)
        session.setOnline(true); await settle(); clock.advance(); await settle()
        XCTAssertEqual(renderer.inputs.count,1,"Reconnect cannot submit or automatically replay an operation")
        session.close(); XCTAssertEqual(session.input.text,"UNSENT"); XCTAssertNil(session.prepare())
    }
    func testPreparedIntentIsCapturedOnceAndRevokedByEditsOrScopeChange() async throws {
        let clock = ManualSleeper()
        let session = ComposeSession(scope:try scope(),sleep:{ try await clock.sleep($0) },render:{ _ in throw FiestaBoardError.previewUnsupported })
        let input = ComposeInput(text:"FINAL {{x}}",lineMetadata:[.init(alignment:"center",wrap:true)],
            duration:.untilCancel,silence:.override)
        session.update(input)
        let action = try XCTUnwrap(session.prepare())
        XCTAssertEqual(action.input,input); XCTAssertEqual(action.scope,session.scope)
        XCTAssertNotNil(session.consume(action)); XCTAssertNil(session.consume(action),"One captured intent is never replayed")
        let old = try XCTUnwrap(session.prepare()); session.update(.init(text:"EDITED"))
        XCTAssertNil(session.consume(old))
        let wrongTarget = try XCTUnwrap(session.prepare()); session.changeScope(try scope(board:"desk"))
        XCTAssertNil(session.consume(wrongTarget)); session.close(); await settle()
    }
    func testAbsoluteIntentMustRemainFutureAtPreparationAndConsumption() async throws {
        let session = ComposeSession(scope:try scope(),render:{ _ in throw FiestaBoardError.previewUnsupported })
        let now = Date(timeIntervalSince1970:100)
        session.update(.init(text:"EXPIRING",duration:.until(now.addingTimeInterval(30))))
        let action = try XCTUnwrap(session.prepare(now:now))
        XCTAssertNil(session.consume(action,now:now.addingTimeInterval(31)),"Expired intent must not become indefinite or a new minute")
        XCTAssertNil(session.prepare(now:now.addingTimeInterval(31)))
        session.update(.init(text:"TOO LONG",duration:.until(now.addingTimeInterval(28801))))
        XCTAssertNil(session.prepare(now:now))
        session.close(); await settle()
    }
}

extension ComposeSessionTests {
    func testMalformedContentOrScopeCannotPrepareOrRequestPreview() async throws {
        let clock = ManualSleeper(), renderer = ComposeRenderGate()
        let target = try scope()
        let session = ComposeSession(scope:target,sleep:{ try await clock.sleep($0) },render:{ try await renderer.render($0) })
        for input in [ComposeInput(text:"   "),ComposeInput(text:"TWO\nLINES",lineMetadata:[.init()]),
                      ComposeInput(text:"ONE",lineMetadata:[.init(alignment:"sideways")]),
                      ComposeInput(text:"TOO LONG",duration:.minutes(481))] {
            session.update(input); await settle(); clock.advance(); await settle()
            XCTAssertNil(session.prepare()); XCTAssertTrue(renderer.inputs.isEmpty)
        }
        session.update(.init(text:"TWO\nLINES"))
        XCTAssertEqual(session.input.lineMetadata.count,2,"Default formatting must preserve every source row")
        session.changeScope(.init(identity:.init(deploymentID:"https://wrong.test",installationID:"installed-A",principalID:"admin"),
            connectionID:target.connectionID,target:target.target,rows:6,cols:22))
        await settle(); clock.advance(); await settle()
        XCTAssertNil(session.prepare()); XCTAssertTrue(renderer.inputs.isEmpty)
        session.close(); await settle()
    }
}

extension ComposeSessionTests {
    func testDurableBufferRestoresExactInputAndVerifiedTargetOfflineWithoutRendering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstScope = try scope(board: "led-two"), buffer = ComposeBufferStore(directory: directory)
        let first = ComposeSession(scope: firstScope, render: { _ in XCTFail("No render before idle"); throw FiestaBoardError.previewUnsupported })
        _ = try await first.bindBuffer(buffer)
        first.update(.init(text: "Hi {{weather.temp}}", lineMetadata: [.init(alignment: "right", wrap: true)],
            selection: .init(lowerUTF16: 3, upperUTF16: 3), duration: .untilCancel, silence: .override))
        _ = try await first.persistBuffer(); first.close()
        let current = try scope(), led = try scope(board: "led-two", connection: current.connectionID)
        let restored = ComposeSession(scope: current, online: false, render: { _ in XCTFail("Offline restore must not render or send"); throw FiestaBoardError.networkUnavailable })
        let didRestore = try await restored.bindBuffer(ComposeBufferStore(directory: directory), resolveTarget: { $0 == "led-two" ? led : nil })
        XCTAssertTrue(didRestore); XCTAssertEqual(restored.input, first.input)
        XCTAssertEqual(restored.scope, led); XCTAssertNil(restored.prepare()); XCTAssertTrue(restored.previewIsStale)
    }
    func testUnknownSavedTargetDoesNotTrustOrInventCachedGeometry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try scope(), buffer = ComposeBufferStore(directory: directory), lease = try await buffer.open(target.identity)
        _ = try await buffer.save(.init(identity: target.identity, revision: 9, text: "KEPT", targetID: "removed",
            targetPresentation: .init(id: "removed", name: "Removed display", deviceType: "note", rows: 3, cols: 15)), using: lease)
        let session = ComposeSession(scope: target, online: true, render: { _ in throw FiestaBoardError.networkUnavailable })
        _ = try await session.bindBuffer(buffer, resolveTarget: { _ in nil })
        XCTAssertEqual(session.input.text, "KEPT"); XCTAssertEqual(session.scope, target)
        XCTAssertEqual(session.unavailableBufferedTargetID, "removed")
        XCTAssertNil(session.prepare(), "An unavailable saved target must not silently send to the default display")
        _ = try await session.persistBuffer()
        let retained = try await buffer.load(target.identity)
        XCTAssertEqual(retained?.targetID, "removed", "Saving must retain an unresolved target until an explicit display choice")
        session.changeScope(target) // Explicitly choosing the current display resolves the missing target.
        XCTAssertNotNil(session.prepare())
        let updated = try await session.persistBuffer()
        XCTAssertNotNil(updated)
        let chosen = try await buffer.load(target.identity)
        XCTAssertEqual(chosen?.targetID, "kitchen")
        XCTAssertNil(chosen?.targetPresentation, "Removed display facts must not follow an explicit target choice")
    }
    func testAcknowledgedBufferRevisionCannotClearNewerUnsavedTyping() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = ComposeBufferStore(directory: directory), target = try scope()
        let session = ComposeSession(scope: target, online: false, render: { _ in throw FiestaBoardError.networkUnavailable })
        _ = try await session.bindBuffer(buffer); session.update(.init(text: "SENDING"))
        let observed = try await session.persistBuffer(), saved = try XCTUnwrap(observed)
        session.update(.init(text: "NEW TYPING"))
        let cleared = try await session.clearBuffer(matchingRevision: saved)
        XCTAssertFalse(cleared)
        _ = try await session.persistBuffer()
        let restored = try await buffer.load(target.identity)
        XCTAssertEqual(restored?.text, "NEW TYPING")
    }
    func testRevokedOrChangedPrincipalSessionCannotSaveButDraftIsRetained() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = ComposeBufferStore(directory: directory), target = try scope()
        let session = ComposeSession(scope: target, online: false, render: { _ in throw FiestaBoardError.networkUnavailable })
        _ = try await session.bindBuffer(buffer); session.update(.init(text: "PRIVATE")); _ = try await session.persistBuffer()
        await session.revokeBuffer(); session.update(.init(text: "AFTER REVOCATION"))
        let rejected = try await session.persistBuffer()
        XCTAssertNil(rejected)
        let retained = try await buffer.load(target.identity)
        XCTAssertEqual(retained?.text, "PRIVATE")
        let other = try scope(hub: "https://other.test")
        session.changeScope(other)
        XCTAssertEqual(session.input.text, "")
        let rejectedAgain = try await session.persistBuffer()
        XCTAssertNil(rejectedAgain)
    }
    func testFreshWriterContinuesDurableRevisionAfterRelaunchAndClearCannotResurrect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = ComposeBufferStore(directory: directory), target = try scope(), lease = try await buffer.open(target.identity)
        _ = try await buffer.save(.init(identity: target.identity, revision: 50, text: "OLD"), using: lease)
        let session = ComposeSession(scope: target, online: false, render: { _ in throw FiestaBoardError.networkUnavailable })
        _ = try await session.bindBuffer(buffer); session.update(.init(text: "NEW"))
        let observed = try await session.persistBuffer(), saved = try XCTUnwrap(observed)
        XCTAssertGreaterThan(saved, 50)
        let cleared = try await session.clearBuffer(matchingRevision: saved)
        XCTAssertTrue(cleared)
        let late = try await session.persistBuffer(), restored = try await buffer.load(target.identity)
        XCTAssertNil(late); XCTAssertNil(restored)
    }
}

private actor DelayedComposeRemoval: ComposeBufferPersisting {
    let store: ComposeBufferStore
    private var removed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    init(directory: URL) { store = ComposeBufferStore(directory: directory) }
    func open(_ identity: ComposeBufferIdentity) async throws -> ComposeBufferLease { try await store.open(identity) }
    func load(_ identity: ComposeBufferIdentity) async throws -> ComposeBufferSnapshot? { try await store.load(identity) }
    func save(_ snapshot: ComposeBufferSnapshot, using lease: ComposeBufferLease) async throws -> Bool { try await store.save(snapshot, using: lease) }
    func revoke(_ lease: ComposeBufferLease) async throws { try await store.revoke(lease) }
    func clear(using lease: ComposeBufferLease, matchingRevision: UInt64) async throws -> ComposeBufferLease? {
        let result = try await store.clear(using: lease, matchingRevision: matchingRevision)
        removed = true; waiter?.resume(); waiter = nil
        await withCheckedContinuation { paused = $0 }
        return result
    }
    func waitForRemoval() async { if removed { return }; await withCheckedContinuation { waiter = $0 } }
    func resume() { paused?.resume(); paused = nil }
}

extension ComposeSessionTests {
    func testTypingWhileAcknowledgedClearReturnsStillPersistsTheNewDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = DelayedComposeRemoval(directory: directory), target = try scope()
        let session = ComposeSession(scope: target, online: false, render: { _ in throw FiestaBoardError.networkUnavailable })
        _ = try await session.bindBuffer(buffer); session.update(.init(text: "SENT"))
        let observed = try await session.persistBuffer(), revision = try XCTUnwrap(observed)
        let clearing = Task { try await session.clearBuffer(matchingRevision: revision) }
        await buffer.waitForRemoval()
        session.update(.init(text: "TYPED DURING READBACK"))
        // The normal edit-save task can run before the clear result returns.
        // Clearing must finish that save after adopting its replacement lease.
        _ = try await session.persistBuffer()
        await buffer.resume(); let clearedCurrent = try await clearing.value
        XCTAssertFalse(clearedCurrent)
        let restored = try await buffer.load(target.identity)
        XCTAssertEqual(restored?.text, "TYPED DURING READBACK")
    }
}

extension ComposeSessionTests {
    func testCachedTargetPresentationNeverBecomesLiveAuthorityOnReconnect() async throws {
        let verified = try scope(), clock = ManualSleeper(), renderer = ComposeRenderGate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = ComposeBufferStore(directory: directory)
        let presentation = ComposeBufferTarget(id: verified.target.boardID, name: "Cached kitchen", deviceType: "flagship", rows: 6, cols: 22)
        let cached = ComposeScope(identity: verified.identity, connectionID: verified.connectionID, target: verified.target,
            rows: verified.rows, cols: verified.cols, verifiedOnline: false, presentation: presentation)
        let session = ComposeSession(scope: cached, online: false, sleep: { try await clock.sleep($0) }, render: { try await renderer.render($0) })
        _ = try await session.bindBuffer(buffer)
        session.update(.init(text: "KEPT OFFLINE")); _ = try await session.persistBuffer()
        let retained = try await buffer.load(verified.identity)
        XCTAssertEqual(retained?.targetPresentation, presentation)
        session.setOnline(true); session.retryPreview(); await settle(); clock.advance(); await settle()
        XCTAssertTrue(renderer.inputs.isEmpty); XCTAssertNil(session.prepare(), "Network availability cannot promote cached metadata to write authority")
        session.changeScope(verified)
        XCTAssertNotNil(session.prepare(), "Current authenticated target resolution can restore authority for the same retained input")
        session.close()
    }
}

extension ComposeSessionTests {
    func testUnresolvedBufferedDisplayCannotRenderUsingFallbackTargetBeforeExplicitChoice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try scope(), buffer = ComposeBufferStore(directory: directory), lease = try await buffer.open(target.identity)
        _ = try await buffer.save(.init(identity: target.identity, revision: 1, text: "FOR REMOVED DISPLAY", targetID: "removed"), using: lease)
        let clock = ManualSleeper()
        var targets: [String] = []
        let session = ComposeSession(scope: target, sleep: { try await clock.sleep($0) }, render: { request in
            targets.append(request.scope.target.boardID); return try self.reply("ACTUAL RESULT")
        })
        _ = try await session.bindBuffer(buffer)
        session.update(.init(text: "NEW TEXT FOR REMOVED DISPLAY")); await settle(); clock.advance(); await settle()
        session.retryPreview(); await settle()
        XCTAssertTrue(targets.isEmpty, "Typing/retry must not evaluate a retained removed-display draft against the fallback target")
        XCTAssertTrue(session.previewIsStale); XCTAssertNil(session.preview)
        session.changeScope(target); await settle(); clock.advance(); await settle()
        XCTAssertEqual(targets, ["kitchen"], "Explicit display choice can start a correctly captured read")
        session.close()
    }
    func testBindingOlderBufferNeverOverwritesInputAlreadyTypedByCurrentOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try scope(), buffer = ComposeBufferStore(directory: directory), lease = try await buffer.open(target.identity)
        _ = try await buffer.save(.init(identity: target.identity, revision: 50, text: "OLDER DRAFT", targetID: target.target.boardID), using: lease)
        let session = ComposeSession(scope: target, online: false, render: { _ in throw FiestaBoardError.networkUnavailable })
        session.update(.init(text: "CURRENT TYPING"))
        let restored = try await session.bindBuffer(buffer)
        XCTAssertFalse(restored); XCTAssertEqual(session.input.text, "CURRENT TYPING")
        _ = try await session.persistBuffer()
        let saved = try await buffer.load(target.identity)
        XCTAssertEqual(saved?.text, "CURRENT TYPING"); XCTAssertGreaterThan(saved?.revision ?? 0, 50)
        session.close()
    }
}
