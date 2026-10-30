import Foundation
import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState
@MainActor final class StructuralModelTests: XCTestCase {
    func testStructureAndMetadataOnlyPatchCarryOriginalRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = Data(#"{"id":"p","name":"P","type":"template","template":["A"],"line_metadata":[{"future":1.230e+99}],"edit_protocol":"page-revision-v1","revision":"original"}"#.utf8)
        var captured: PageSavePatch?
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { patch in captured = patch; throw FiestaBoardError.rejected(status: 422) })
        let model = try LocalPageEditorModel(rawDocumentData: raw, identity: DraftIdentity(deploymentID: "demo", pageID: "p"), draftStore: LocalDraftStore(directory: directory), remote: remote)
        model.setLineAlignment(0, alignment: "right")
        XCTAssertTrue(model.hasServerChanges); XCTAssertTrue(model.canSaveToServer)
        XCTAssertEqual(model.lineAlignment(0), "right"); XCTAssertFalse(model.lineWrap(0))
        await model.saveToServer()
        XCTAssertEqual(captured?.expectedRevision, "original")
        XCTAssertNil(captured?.name); XCTAssertNil(captured?.template)
        XCTAssertTrue(String(decoding: try XCTUnwrap(captured?.lineMetadataData), as: UTF8.self).contains("1.230e+99"))
        model.duplicateLine(0); model.insertLine(after: nil); model.moveLine(0, to: 2); model.removeLine(1)
        model.setLineWrap(0, wrap: true)
        XCTAssertEqual(model.lines, ["A", ""])
        XCTAssertTrue(model.canSaveToServer)
        await model.saveToServer()
        XCTAssertEqual(captured?.template, ["A", ""])
        XCTAssertEqual(captured?.expectedRevision, "original")
        model.endEditingSession()
        let frozen = model.readOnlyDocumentText
        model.insertLine(after: 0); model.removeLine(0); model.moveLine(0, to: 1); model.duplicateLine(0)
        model.setLineAlignment(0, alignment: "left"); model.setLineWrap(0, wrap: false)
        XCTAssertEqual(model.readOnlyDocumentText, frozen)
    }
    func testEveryStructuralAndFormattingMutationInvalidatesEvaluation() async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "b")
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse },
            validate: { _, _ in try TemplateValidationResult(rawData: Data(#"{"valid":true,"errors":[]}"#.utf8)) },
            preview: { _, _ in try TemplatePreviewResult(rawData: Data(#"{"rendered":"A","lines":["A"],"line_count":1}"#.utf8)) })
        let model = try LocalPageEditorModel(rawDocumentData: Data(#"{"type":"template","template":["A","B"]}"#.utf8), identity: DraftIdentity(deploymentID: "demo", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory), remote: remote, boards: [EditorBoardChoice(name: "B", target: target)])
        model.chooseBoard("b")
        let operations: [() -> Void] = [
            { model.insertLine(after: 0) }, { model.removeLine(1) }, { model.duplicateLine(0) },
            { model.moveLine(2, to: 0) }, { model.setLineAlignment(0, alignment: "center") },
            { model.setLineWrap(0, wrap: true) }, { model.undo() }, { model.redo() }
        ]
        for operation in operations {
            await model.evaluate(preview: false); await model.evaluate(preview: true)
            XCTAssertNotNil(model.validation); XCTAssertNotNil(model.preview)
            operation()
            XCTAssertNil(model.validation); XCTAssertNil(model.preview)
        }
    }
    func testEmptyTemplateEditableButMustAddRowBeforeServerSave() throws {
        let model = try LocalPageEditorModel(rawDocumentData: Data(#"{"type":"template","template":[],"edit_protocol":"page-revision-v1","revision":"r1"}"#.utf8), identity: DraftIdentity(deploymentID: "demo", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory), remote: EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse }))
        XCTAssertEqual(model.lines, [])
        model.insertLine(after: nil)
        XCTAssertEqual(model.lines, [""]); XCTAssertTrue(model.canSaveToServer)
        model.removeLine(0)
        model.setName("Edited")
        XCTAssertFalse(model.canSaveToServer)
    }
}
