import Foundation
import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState

@MainActor final class FlexibleModelTests: XCTestCase {
    let raw = Data(#"{"id":"p","name":"P","type":"flexible","document_protocol":"page-document-v2","edit_protocol":"page-revision-v1","revision":"original","blocks":[{"id":"t","kind":"text","text":"ABC","large":900719925474099312345678},{"id":"c","kind":"canvas","canvas":{"content":{"size":[32,16],"shapes":[{"type":"rect","x":0,"y":0,"w":8,"h":8}]}}}],"style":null}"#.utf8)
    func make(_ remote: EditorRemoteActions? = nil, boards: [EditorBoardChoice] = []) throws -> LocalPageEditorModel {
        try LocalPageEditorModel(rawDocumentData: raw, identity: DraftIdentity(deploymentID: "fixture", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), remote: remote, boards: boards)
    }
    func testFlexibleSaveAdoptsReceiptReopensAndNextEditIsImmediatelyUnsaved() async throws {
        var patches: [PageSavePatch] = []
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { patch in
            patches.append(patch)
            let original = try PageDocument(data: self.raw)
            var root = original.root
            root["blocks"] = try LosslessJSON.parse(XCTUnwrap(patch.blocksData))
            root["revision"] = .string("acknowledged")
            return EditorSaveResult(data: try LosslessJSON.object(root).serializedData())
        })
        let model = try make(remote)
        model.setFlexible(.block("t"), key: "text", value: .string("Edited"))
        model.setFlexible(.shape("c", 0), key: "x", value: .number("3"))
        XCTAssertTrue(model.canSaveToServer)
        await model.saveToServer()
        XCTAssertEqual(patches.count, 1); XCTAssertEqual(patches.first?.expectedRevision, "original")
        XCTAssertNil(patches.first?.template); XCTAssertNil(patches.first?.styleData)
        XCTAssertFalse(model.hasServerChanges); XCTAssertEqual(model.serverSnapshotStatus, "Saved")
        let reopened = try LocalPageEditorModel(rawDocumentData: Data(model.readOnlyDocumentText.utf8), identity: model.identity, draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory))
        XCTAssertEqual(reopened.flexibleText(.block("t"), key: "text"), "Edited")
        model.setFlexible(.shape("c", 0), key: "w", value: .string("-"))
        XCTAssertEqual(model.serverSnapshotStatus, "Unsaved"); XCTAssertFalse(model.canSaveToServer)
        let checkpointed = await model.saveDraft(); XCTAssertTrue(checkpointed)
        XCTAssertEqual(model.flexibleText(.shape("c", 0), key: "w"), "-")
        model.setFlexible(.shape("c", 0), key: "w", value: .number("9"))
        XCTAssertTrue(model.canSaveToServer)
    }
    func testFutureProtocolCannotMutateEvenNameOrHistory() throws {
        let future = Data(#"{"id":"p","name":"Future","type":"flexible","document_protocol":"page-document-v99","blocks":[{"id":"t","kind":"text","text":"A"}]}"#.utf8)
        let model = try LocalPageEditorModel(rawDocumentData: future, identity: DraftIdentity(deploymentID: "fixture", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory))
        let before = model.readOnlyDocumentText
        model.setName("Unsafe")
        XCTAssertEqual(model.readOnlyDocumentText, before); XCTAssertFalse(model.canUndo)
    }
    func testConflictDoesNotRetryAndRetainsOriginalRevision() async throws {
        var count = 0
        let model = try make(EditorRemoteActions(disabledReason: { nil }, save: { patch in count += 1; XCTAssertEqual(patch.expectedRevision, "original"); throw FiestaBoardError.pageConflict }))
        model.setFlexible(.block("t"), key: "text", value: .string("Edited"))
        await model.saveToServer(); await model.saveToServer()
        XCTAssertEqual(count, 1); XCTAssertEqual(model.remoteStatus, .conflict)
        XCTAssertEqual(model.baselineRevision, "original")
    }
    func testHiddenInvalidFieldBlocksPreviewAndRepairUndoRedo() async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://fixture.test"), boardID: "b")
        var calls = 0
        let model = try make(EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse }, previewFlexible: { _, _ in calls += 1; return try Self.reply() }), boards: [EditorBoardChoice(name: "B", target: target)])
        model.chooseBoard("b")
        model.setFlexible(.shape("c", 0), key: "x", value: .string("1."))
        XCTAssertFalse(model.canEvaluate)
        await model.evaluate(preview: true); XCTAssertEqual(calls, 0)
        model.setFlexible(.shape("c", 0), key: "x", value: .number("1"))
        await model.evaluate(preview: true); XCTAssertEqual(calls, 1); XCTAssertNotNil(model.flexiblePreview)
        model.undo(); XCTAssertFalse(model.canEvaluate); XCTAssertNil(model.flexiblePreview)
        model.redo(); XCTAssertTrue(model.canEvaluate)
    }
    static func reply() throws -> FlexiblePreviewResult { try FlexiblePreviewResult(rawData: Data(#"{"available":true,"page_id":"unsaved","message":"A","lines":["A"],"display_type":"template","raw":{},"layout_issues":[]}"#.utf8)) }
}

extension FlexibleModelTests {
    func testInvalidHiddenCanvasSurvivesActualLocalCheckpointAndExplicitRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draftStore = LocalDraftStore(directory: directory)
        let identity = DraftIdentity(deploymentID: "fixture", pageID: "p")
        let model = try LocalPageEditorModel(rawDocumentData: raw, identity: identity, draftStore: draftStore)
        model.setFlexible(.shape("c", 0), key: "w", value: FlexibleNumber.draft("01"))
        model.setFlexible(.block("t"), key: "text", value: .string("Other selected content"))
        let saved = await model.saveDraft()
        XCTAssertTrue(saved); XCTAssertEqual(model.serverSnapshotStatus, "Unsaved")
        let reopened = try LocalPageEditorModel(rawDocumentData: raw, identity: identity, draftStore: draftStore)
        await reopened.checkRecovery(); XCTAssertTrue(reopened.canRecover)
        reopened.recoverDraft()
        XCTAssertEqual(reopened.flexibleText(.shape("c", 0), key: "w"), "01")
        XCTAssertEqual(reopened.flexibleText(.block("t"), key: "text"), "Other selected content")
        XCTAssertTrue(reopened.flexibleIssues.contains { $0.blockID == "c" && $0.key == "w" })
        XCTAssertEqual(reopened.baselineRevision, "original")
        reopened.setFlexible(.shape("c", 0), key: "w", value: .number("8"))
        XCTAssertTrue(reopened.flexibleIssues.isEmpty)
        reopened.undo()
        XCTAssertEqual(reopened.historyFocus, .shape("c", 0))
        XCTAssertEqual(reopened.flexibleText(.shape("c", 0), key: "w"), "01")
    }
    func testUnknownFlexibleSaveNeverDisplaysSavedOrRetriesWithoutReadback() async throws {
        var attempts = 0
        let model = try make(EditorRemoteActions(disabledReason: { nil }, save: { _ in
            attempts += 1; throw FiestaBoardError.unknownMutationOutcome
        }))
        model.setFlexible(.block("t"), key: "text", value: .string("Pending"))
        await model.saveToServer(); await model.saveToServer()
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.serverSnapshotStatus, "Unknown save result")
        XCTAssertEqual(model.baselineRevision, "original")
        XCTAssertEqual(model.flexibleText(.block("t"), key: "text"), "Pending")
    }
}
