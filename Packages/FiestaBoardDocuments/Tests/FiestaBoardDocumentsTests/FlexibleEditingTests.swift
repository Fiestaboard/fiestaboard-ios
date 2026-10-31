import Foundation
import XCTest
@testable import FiestaBoardDocuments

final class FlexibleEditingTests: XCTestCase {
    let raw = Data(#"{"id":"p","name":"Flexible","type":"flexible","document_protocol":"page-document-v2","edit_protocol":"page-revision-v1","revision":"original","blocks":[{"id":"text1","kind":"text","text":"A👩‍💻B","extension":{"large":900719925474099312345678,"null":null}},{"id":"draw","kind":"canvas","canvas":{"source":null,"content":{"size":[32,16],"pixels":["a"],"palette":{"a":"white"},"shapes":[{"type":"rect","x":0,"y":0,"w":8,"h":8,"fill":"red","opaque":900719925474099312345678}]}}},{"id":"future","kind":"future","opaque":null}],"style":null}"#.utf8)

    func testNestedMutationPreservesOpaqueSiblingsExactNumbersAndNulls() throws {
        var session = try DocumentEditingSession(data: raw)
        try session.editFlexible { try $0.setFlexibleValue(.shape("draw", 0), key: "x", value: .number("2")) }
        try session.editFlexible { try $0.insertFlexibleBlock(kind: "spacer", id: "space", at: 1) }
        try session.editFlexible { try $0.moveFlexibleBlock(id: "draw", to: 0) }
        let data = try session.document.serializedData()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("900719925474099312345678"))
        XCTAssertEqual(session.document.flexibleBlocks.map(\.id), ["draw", "text1", "space", "future"])
        XCTAssertEqual(session.document.root["style"], .null)
        XCTAssertNil(session.document.root["layout"])
        XCTAssertTrue(session.document.flexibleIssues.isEmpty)
        for _ in 0..<3 { try session.undo() }
        XCTAssertEqual(session.document, try PageDocument(data: raw))
        for _ in 0..<3 { try session.redo() }
        XCTAssertEqual(try session.document.serializedData(), data)
    }
    func testInvalidNumericIntermediatesSurviveCheckpointAndBlockWholeDocument() throws {
        for value in ["", "-", ".", "1.", "01", "1e", "NaN"] {
            var session = try DocumentEditingSession(data: raw)
            try session.editFlexible { try $0.setFlexibleValue(.shape("draw", 0), key: "w", value: FlexibleNumber.draft(value)) }
            XCTAssertEqual(session.document.flexibleValue(.shape("draw", 0), key: "w"), .string(value))
            XCTAssertTrue(session.document.flexibleIssues.contains { $0.blockID == "draw" && $0.key == "w" })
            let snapshot = try session.snapshot(identity: DraftIdentity(deploymentID: "demo", pageID: "p"))
            var reopened = try DocumentEditingSession(data: raw)
            try reopened.recover(snapshot)
            XCTAssertEqual(reopened.document, session.document)
            XCTAssertThrowsError(try reopened.document.flexibleEvaluationData(boardID: "b"))
            try reopened.editFlexible { try $0.setFlexibleValue(.shape("draw", 0), key: "w", value: FlexibleNumber.draft("12")) }
            XCTAssertTrue(reopened.document.flexibleIssues.isEmpty)
        }
        for value in ["-1", "1.0", "1e2", "0"] { XCTAssertEqual(FlexibleNumber.draft(value), .number(value)) }
    }
    func testNativeTextSelectionInsertionPreservesUTF16AndDoesNotAppend() throws {
        var document = try PageDocument(data: raw)
        try document.insertFlexibleText(blockID: "text1", source: "{{weather.temperature}}", selection: NSRange(location: 1, length: "👩‍💻".utf16.count))
        XCTAssertEqual(document.flexibleValue(.block("text1"), key: "text"), .string("A{{weather.temperature}}B"))
        XCTAssertThrowsError(try document.insertFlexibleText(blockID: "text1", source: "X", selection: NSRange(location: 999, length: 0)))
    }
    func testUnknownShapeAndFutureProtocolStayLocalReadOnly() throws {
        var document = try PageDocument(data: raw)
        try document.setFlexibleValue(.shape("draw", 0), key: "x", value: .string("{{x}}"))
        XCTAssertTrue(document.flexibleIssues.isEmpty)
        let future = try PageDocument(data: Data(#"{"type":"flexible","document_protocol":"page-document-v3","blocks":[{"id":"t","kind":"text","text":"A"}]}"#.utf8))
        XCTAssertFalse(future.supportsFlexibleEditing)
        var unsupported = future
        XCTAssertThrowsError(try unsupported.insertFlexibleBlock(kind: "text", id: "new", at: 0))
        let unknown = try PageDocument(data: Data(#"{"name":"P","type":"flexible","document_protocol":"page-document-v2","blocks":[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"future","opaque":900719925474099312345678}]}}}]}"#.utf8))
        XCTAssertFalse(unknown.flexibleIssues.isEmpty)
        XCTAssertThrowsError(try unknown.flexibleEvaluationData(boardID: "b"))
    }
    func testShapeActionsAndPreviewAuthorPayloadAreBoundedAndLossless() throws {
        var session = try DocumentEditingSession(data: raw)
        try session.editFlexible { try $0.insertFlexibleShape(blockID: "draw", kind: "text") }
        try session.editFlexible { try $0.moveFlexibleShape(blockID: "draw", from: 1, to: 0) }
        try session.editFlexible { try $0.removeFlexibleShape(blockID: "draw", at: 1) }
        let payload = try LosslessJSON.parse(session.document.flexibleEvaluationData(boardID: "b"))
        guard case .object(let root) = payload, case .object(let page) = root["page"] else { return XCTFail() }
        XCTAssertEqual(root["board_id"], .string("b"))
        XCTAssertNil(page["revision"]); XCTAssertNil(page["id"]); XCTAssertNil(page["template"]); XCTAssertNil(page["device_type"])
        XCTAssertEqual(page["blocks"], session.document.root["blocks"])
        for _ in 0..<3 { try session.undo() }
        XCTAssertEqual(session.document, try PageDocument(data: raw))
    }
}

extension FlexibleEditingTests {
    func testExplicitContainerRepairAndInheritancePreserveUndoAndNullDistinction() throws {
        let broken = Data(#"{"name":"P","type":"flexible","document_protocol":"page-document-v2","style":"broken","blocks":[{"id":"c","kind":"canvas","canvas":{"content":"broken","opaque":900719925474099312345678}}]}"#.utf8)
        var session = try DocumentEditingSession(data: broken)
        XCTAssertFalse(session.document.flexibleIssues.isEmpty)
        try session.editFlexible { try $0.resetFlexibleContainer(.pageStyle, inherit: true) }
        try session.editFlexible { try $0.resetFlexibleContainer(.content("c"), inherit: false) }
        XCTAssertEqual(session.document.root["style"], .null)
        XCTAssertNil(session.document.root["layout"])
        XCTAssertTrue(session.document.flexibleIssues.isEmpty)
        XCTAssertEqual(session.document.flexibleValue(.canvas("c"), key: "opaque"), .number("900719925474099312345678"))
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document, try PageDocument(data: broken))
    }
    func testEmptyFlexibleDocumentCanAddFirstBlockAndCanvasSourceKeepsFallback() throws {
        var document = try PageDocument(data: Data(#"{"name":"P","type":"flexible","document_protocol":"page-document-v2","blocks":null}"#.utf8))
        try document.insertFlexibleBlock(kind: "canvas", id: "c", at: 0)
        let before = document.flexibleContainerValue(.content("c"))
        try document.setFlexibleValue(.canvas("c"), key: "source", value: .string("{{plugin.canvas}}"))
        XCTAssertEqual(document.flexibleContainerValue(.content("c")), before)
        XCTAssertTrue(document.flexibleIssues.isEmpty)
        try document.setFlexibleValue(.canvas("c"), key: "source", value: nil)
        XCTAssertEqual(document.flexibleContainerValue(.content("c")), before)
    }
}

extension FlexibleEditingTests {
    func testUndoRedoCarryActionNameAndAffectedShapeForNativeFocus() throws {
        var session = try DocumentEditingSession(data: raw)
        try session.editFlexible(action: "Move rectangle", focus: .shape("draw", 0)) {
            try $0.setFlexibleValue(.shape("draw", 0), key: "x", value: .number("3"))
        }
        XCTAssertEqual(session.undoActionName, "Move rectangle")
        try session.undo()
        XCTAssertEqual(session.historyFocus, .shape("draw", 0))
        XCTAssertEqual(session.redoActionName, "Move rectangle")
        try session.redo()
        XCTAssertEqual(session.document.flexibleValue(.shape("draw", 0), key: "x"), .number("3"))
        XCTAssertEqual(session.historyFocus, .shape("draw", 0))
    }
}

extension FlexibleEditingTests {
    func testWholeDocumentRejectsInvalidKnownFieldsInRetainedSiblings() throws {
        let blocks = [
            #"[{"id":42,"kind":"text","text":"A"}]"#,
            #"[{"id":"s","kind":"spacer","text":42}]"#,
            #"[{"id":"u","kind":"future","text":42}]"#,
            #"[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"text","x":0,"y":0,"text":"A","color":null}]}}}]"#,
            #"[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"text","x":0,"y":0,"text":"A","color":"white","font":null}]}}}]"#,
            #"[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"line","x1":0,"y1":0,"x2":1,"y2":1,"stroke":null}]}}}]"#,
            #"[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"gradient","from":"red","to":"blue","angle":null}]}}}]"#,
        ]
        for blocks in blocks {
            let data = Data((#"{"name":"P","type":"flexible","document_protocol":"page-document-v2","blocks":"# + blocks + "}").utf8)
            let document = try PageDocument(data: data)
            XCTAssertFalse(document.flexibleIssues.isEmpty, blocks)
            XCTAssertThrowsError(try document.flexibleEvaluationData(boardID: "b"))
        }
        let layout = try PageDocument(data: Data(#"{"name":"P","type":"flexible","document_protocol":"page-document-v2","blocks":[{"id":"s","kind":"spacer"}],"layout":{"kind":null}}"#.utf8))
        XCTAssertFalse(layout.flexibleIssues.isEmpty)
    }
    func testColorVocabularyMatchesCoreEightBoardColorsAndPreservesExpressions() throws {
        var document = try PageDocument(data: raw)
        for color in ["red", "orange", "yellow", "green", "blue", "violet", "white", "black", "#12AbEF", "{{plugin.color}}"] {
            try document.setFlexibleValue(.blockStyle("text1"), key: "color", value: .string(color))
            XCTAssertTrue(document.flexibleIssues.isEmpty, color)
        }
        for color in ["purple", "cyan", "magenta"] {
            try document.setFlexibleValue(.blockStyle("text1"), key: "color", value: .string(color))
            XCTAssertFalse(document.flexibleIssues.isEmpty, color)
        }
        try document.setFlexibleValue(.blockStyle("text1"), key: "color", value: nil)
        try document.setFlexibleValue(.content("draw"), key: "background", value: .string("{{plugin.background}}"))
        XCTAssertTrue(document.flexibleIssues.isEmpty)
    }
}
