import XCTest
import FiestaBoardKit
import FiestaBoardDocuments
@testable import FiestaBoardEditorState

@MainActor private final class ComposeRenderGate {
    var inputs: [ComposePreviewInput] = []
    private var replies: [CheckedContinuation<TemplatePreviewResult, any Error>] = []
    func render(_ input: ComposePreviewInput) async throws -> TemplatePreviewResult {
        inputs.append(input)
        return try await withCheckedThrowingContinuation { replies.append($0) }
    }
    func answer(_ value: TemplatePreviewResult) { replies.removeFirst().resume(returning:value) }
    func fail() { replies.removeFirst().resume(throwing:FiestaBoardError.networkUnavailable) }
}

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
        for changed in [try scope(board:"desk"),try scope(),try scope(hub:"https://other.test")] {
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
