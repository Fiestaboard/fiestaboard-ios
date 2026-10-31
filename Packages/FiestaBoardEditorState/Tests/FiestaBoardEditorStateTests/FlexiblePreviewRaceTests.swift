import Foundation
import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState

@MainActor final class FlexiblePreviewRaceTests: XCTestCase {
    func testOutOfOrderEditTargetAndEndedSessionCannotPublishPreview() async throws {
        for transition in ["edit", "target", "end", "newer"] {
            let gate = FlexiblePreviewGate()
            let target = try BoardTarget(deployment: DeploymentURL("https://fixture.test"), boardID: "b")
            let second = try BoardTarget(deployment: target.deployment, boardID: "other")
            let remote = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse }, previewFlexible: { _, _ in try await gate.run() })
            let model = try make(remote, boards: [EditorBoardChoice(name: "B", target: target), EditorBoardChoice(name: "Other", target: second)])
            model.chooseBoard("b")
            let pending = Task { await model.evaluate(preview: true) }
            await gate.waitForCalls(1)
            switch transition {
            case "edit": model.setFlexible(.block("t"), key: "text", value: .string("Newer edit"))
            case "target": model.chooseBoard("other")
            case "end": model.endEditingSession()
            default:
                let next = Task { await model.evaluate(preview: true) }
                await gate.waitForCalls(2)
                await gate.release(1, status: 200)
                await next.value
                XCTAssertNotNil(model.flexiblePreview)
            }
            await gate.release(0, status: 200)
            await pending.value
            if transition == "newer" { XCTAssertNotNil(model.flexiblePreview) } else { XCTAssertNil(model.flexiblePreview) }
        }
    }
    func testDeletedTargetInFlightKeepsNewEditsClearsPreviewAndRequiresCurrentReselection() async throws {
        let gate = FlexiblePreviewGate()
        let target = try BoardTarget(deployment: DeploymentURL("https://fixture.test"), boardID: "b")
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse }, previewFlexible: { _, _ in try await gate.run() })
        let model = try make(remote, boards: [EditorBoardChoice(name: "B", target: target)])
        model.chooseBoard("b")
        let pending = Task { await model.evaluate(preview: true) }
        await gate.waitForCalls(1)
        model.setFlexible(.block("t"), key: "text", value: .string("Retain while previewing"))
        await gate.release(0, status: 404)
        await pending.value
        XCTAssertEqual(model.flexibleText(.block("t"), key: "text"), "Retain while previewing")
        XCTAssertNil(model.selectedBoardID); XCTAssertNil(model.flexiblePreview)
        XCTAssertFalse(model.canEvaluate); XCTAssertTrue(model.hasServerChanges)
        XCTAssertEqual(model.remoteStatus, .idle)
        model.chooseBoard("b")
        XCTAssertNil(model.selectedBoardID, "A known-deleted board cannot immediately be selected from stale choices")
    }
    func test422AndOfflinePreviewDoNotBecomeUnknownPageWrite() async throws {
        for failure in [FiestaBoardError.rejected(status: 422), .networkUnavailable] {
            let target = try BoardTarget(deployment: DeploymentURL("https://fixture.test"), boardID: "b")
            let model = try make(EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse }, previewFlexible: { _, _ in throw failure }), boards: [EditorBoardChoice(name: "B", target: target)])
            model.chooseBoard("b"); await model.evaluate(preview: true)
            XCTAssertEqual(model.remoteStatus, .idle); XCTAssertEqual(model.selectedBoardID, "b")
            XCTAssertNotNil(model.message); XCTAssertNil(model.flexiblePreview)
        }
    }
    private func make(_ remote: EditorRemoteActions, boards: [EditorBoardChoice]) throws -> LocalPageEditorModel {
        try LocalPageEditorModel(rawDocumentData: Data(#"{"id":"p","name":"P","type":"flexible","document_protocol":"page-document-v2","edit_protocol":"page-revision-v1","revision":"r","blocks":[{"id":"t","kind":"text","text":"A"}]}"#.utf8), identity: DraftIdentity(deploymentID: "fixture", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), remote: remote, boards: boards)
    }
}
private actor FlexiblePreviewGate {
    private var calls: [CheckedContinuation<FlexiblePreviewResult, any Error>?] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func run() async throws -> FlexiblePreviewResult {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(continuation)
            let ready = observers.filter { $0.0 <= calls.count }; observers.removeAll { $0.0 <= calls.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if calls.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func release(_ index: Int, status: Int) {
        guard let continuation = calls[index] else { return }
        calls[index] = nil
        if status != 200 { continuation.resume(throwing: FiestaBoardError.rejected(status: status)); return }
        continuation.resume(returning: try! FlexiblePreviewResult(rawData: Data(#"{"available":true,"page_id":"unsaved","message":"A","lines":["A"],"display_type":"panel","raw":{},"layout_issues":[]}"#.utf8)))
    }
}
