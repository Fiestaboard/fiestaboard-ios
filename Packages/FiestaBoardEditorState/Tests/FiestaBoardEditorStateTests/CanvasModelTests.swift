import Foundation
import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState

/// PLAN B24/§2.4: canvas edits are an editable field of legacy pages and save as raw `canvases`.
@MainActor final class CanvasModelTests: XCTestCase {
    func testCanvasEditSavesOnlyCanvasesWithTheOriginalRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raw = Data(##"{"id":"p","name":"P","type":"template","device_type":"panel","grid_rows":10,"grid_cols":16,"template":["HI"],"canvases":[{"id":"sun","area":{"row":1,"col":1,"rows":5,"cols":8},"content":{"shapes":[{"type":"rect","x":1,"y":1,"w":4,"h":4,"fill":"red","future":1.230e+99}]}}],"edit_protocol":"page-revision-v1","revision":"original"}"##.utf8)
        var captured: PageSavePatch?
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { patch in captured = patch; throw FiestaBoardError.rejected(status: 422) })
        let model = try LocalPageEditorModel(rawDocumentData: raw, identity: DraftIdentity(deploymentID: "demo", pageID: "p"), draftStore: LocalDraftStore(directory: directory), remote: remote)
        XCTAssertTrue(model.canvasesAreEditable)
        XCTAssertFalse(model.hasServerChanges)
        var canvases = model.canvases
        canvases[0].shapes[0] = CanvasShape.moved(CanvasShape(canvases[0].shapes[0])!, dx: 11.4, dy: 0).json
        model.setCanvases(canvases, action: "Move shape")
        XCTAssertEqual(model.undoActionName, "Move shape")
        XCTAssertTrue(model.hasServerChanges); XCTAssertTrue(model.canSaveToServer)
        await model.saveToServer()
        let sent = String(decoding: try XCTUnwrap(captured?.canvasesData), as: UTF8.self)
        XCTAssertTrue(sent.contains(#""x":12"#), sent)
        XCTAssertTrue(sent.contains("1.230e+99"))
        XCTAssertNil(captured?.template); XCTAssertNil(captured?.lineMetadataData); XCTAssertTrue(captured?.geometryData.isEmpty == true)
        XCTAssertEqual(captured?.expectedRevision, "original")
        model.undo()
        XCTAssertFalse(model.hasServerChanges)
    }
    func testFlexiblePagesHaveNoLegacyCanvases() throws {
        let raw = Data(#"{"type":"flexible","document_protocol":"page-document-v2","blocks":[{"id":"a","kind":"spacer"}]}"#.utf8)
        let model = try LocalPageEditorModel(rawDocumentData: raw, identity: DraftIdentity(deploymentID: "demo", pageID: "p"), draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory))
        XCTAssertTrue(model.canvases.isEmpty)
        XCTAssertFalse(model.canvasesAreEditable)
    }
}
