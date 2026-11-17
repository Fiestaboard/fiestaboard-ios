import Foundation
import XCTest
@testable import FiestaBoardDocuments

final class StructuralEditingTests: XCTestCase {
    func testEmptyTemplateAcceptsFirstRowWithoutMaterializingMetadata() throws {
        var document = try PageDocument(data: Data(#"{"type":"template","template":[],"line_metadata":null}"#.utf8))
        XCTAssertEqual(document.editableTemplateLines, [])
        try document.insertTemplateLine(at: 0, with: "FIRST")
        XCTAssertEqual(document.templateLines, ["FIRST"])
        XCTAssertEqual(document.root["line_metadata"], .null)
    }
    func testStructureCarriesExactMetadataAndUndoRecovery() throws {
        let data = Data(#"{"type":"template","template":["A","B"],"line_metadata":[{"alignment":"right","future":1.000e+99},{"wrap":true,"future":922337203685477580712345}]}"#.utf8)
        var session = try DocumentEditingSession(data: data)
        let original = session.document
        try session.duplicateTemplateLine(at: 0)
        try session.moveTemplateLine(from: 2, to: 0)
        try session.insertTemplateLine(at: 1, with: "NEW")
        try session.removeTemplateLine(at: 2)
        XCTAssertEqual(session.document.templateLines, ["B", "NEW", "A"])
        guard case .array(let metadata) = session.document.root["line_metadata"], case .array(let before) = original.root["line_metadata"] else { return XCTFail() }
        XCTAssertEqual(metadata[0], before[1]); XCTAssertEqual(metadata[2], before[0])
        XCTAssertEqual(metadata[1], .object(["alignment": .string("left"), "wrap": .bool(false)]))
        let snapshot = try session.snapshot(identity: DraftIdentity(deploymentID: "demo", pageID: "p"))
        var recovered = try DocumentEditingSession(data: data)
        try recovered.recover(snapshot)
        XCTAssertEqual(recovered.document, session.document)
        for _ in 0..<4 { try session.undo() }
        XCTAssertEqual(session.document, original)
        for _ in 0..<4 { try session.redo() }
        XCTAssertEqual(session.document, recovered.document)
    }
    func testUnsupportedMetadataShapesRejectStructureWithoutTruncation() throws {
        // "[]" is no longer unsupported: a shorter-than-template array is editable (PLAN §2.2; LosslessRoundTripTests).
        for metadata in [#"[{"alignment":"future"}]"#, #"[{"wrap":1}]"#, "[null]", "{}", #"[{},{}]"#] {
            var document = try PageDocument(data: Data("{\"type\":\"template\",\"template\":[\"A\"],\"line_metadata\":\(metadata)}".utf8))
            let before = document
            XCTAssertThrowsError(try document.insertTemplateLine(at: 0, with: "B"))
            XCTAssertThrowsError(try document.removeTemplateLine(at: 0))
            XCTAssertThrowsError(try document.duplicateTemplateLine(at: 0))
            XCTAssertThrowsError(try document.moveTemplateLine(from: 0, to: 0))
            XCTAssertEqual(document, before)
        }
    }
    func testFormattingMigratesEffectiveLegacySettingsWithoutChangingOtherRows() throws {
        for metadata in ["", ",\"line_metadata\":null"] {
            var document = try PageDocument(data: Data("{\"type\":\"template\",\"template\":[\"{center}A\",\"{wrap}{RIGHT}B\",\"{right}{wrap}C\",\"{WRAP}{center}D\"]\(metadata)}".utf8))
            try document.setLineWrap(at: 0, wrap: true)
            XCTAssertEqual(document.templateLines, ["A", "B", "{wrap}C", "{WRAP}{center}D"])
            XCTAssertEqual(document.root["line_metadata"], .array([
                .object(["alignment": .string("center"), "wrap": .bool(true)]),
                .object(["alignment": .string("right"), "wrap": .bool(true)]),
                .object(["alignment": .string("right"), "wrap": .bool(false)]),
                .object(["alignment": .string("left"), "wrap": .bool(false)])]))
        }
    }
    func testFormattingMaterializesAllRowsAndFailedOperationsAreAtomic() throws {
        var document = try PageDocument(data: Data(#"{"type":"template","template":["A","B"]}"#.utf8))
        try document.setLineAlignment(at: 1, alignment: "center")
        try document.setLineWrap(at: 0, wrap: true)
        XCTAssertEqual(document.root["line_metadata"], .array([.object(["alignment": .string("left"), "wrap": .bool(true)]), .object(["alignment": .string("center"), "wrap": .bool(false)])]))
        let before = document
        XCTAssertThrowsError(try document.insertTemplateLine(at: 9, with: "X"))
        XCTAssertThrowsError(try document.insertTemplateLine(at: 0, with: "X\nY"))
        XCTAssertThrowsError(try document.moveTemplateLine(from: 0, to: 3))
        XCTAssertThrowsError(try document.setLineAlignment(at: 0, alignment: "invalid"))
        XCTAssertEqual(document, before)
    }

    /// PLAN B20/§2.4: a geometry change writes only the shape's keys; everything else is byte-identical.
    func testSetGeometryIsLossless() throws {
        let raw = #"{"id":"p","revision":"r1","name":"N","type":"template","device_type":"flagship","template":["lower","B"],"line_metadata":[{"alignment":"center","x":1.50}],"grid_rows":null,"future":12345678901234567890}"#
        let original = try PageDocument(data: Data(raw.utf8))
        var document = original
        XCTAssertEqual(document.geometry, .flagship)
        try document.setGeometry(.noteArray(wide: 2, tall: 1))
        XCTAssertEqual(document.geometry, .noteArray(wide: 2, tall: 1))
        XCTAssertEqual(TemplateGeometry(document: document)?.columns, 30)
        guard case .object(let changed) = try document.changedFields(from: original) else { return XCTFail() }
        XCTAssertEqual(Set(changed.keys), ["device_type", "notes_wide", "notes_tall"])
        let text = String(decoding: try document.serializedData(), as: UTF8.self)
        for kept in [#""lower""#, #""x":1.50"#, "12345678901234567890", #""grid_rows":null"#, #""revision":"r1""#] { XCTAssertTrue(text.contains(kept), kept) }
        try document.setGeometry(.note)
        XCTAssertEqual(TemplateGeometry(document: document)?.rows, 3)
        XCTAssertTrue(PageGeometry.note.shrinks(from: .flagship))
        XCTAssertFalse(PageGeometry.flagship.shrinks(from: .note))
        try document.setGeometry(.panel(rows: 12, cols: 29))
        XCTAssertEqual(document.root["grid_cols"], .number("29"))
        let before = document
        XCTAssertThrowsError(try document.setGeometry(.panel(rows: 1, cols: 29)))
        XCTAssertThrowsError(try document.setGeometry(PageGeometry(deviceType: "future")))
        XCTAssertEqual(document, before)
        var session = try DocumentEditingSession(data: Data(raw.utf8))
        try session.setGeometry(.note)
        try session.undo()
        XCTAssertEqual(session.document, original, "one undo step restores the shape")
        var padded = try DocumentEditingSession(data: Data(#"{"type":"template","template":["A","","","B","",""]}"#.utf8))
        try padded.setGeometry(.note)
        XCTAssertEqual(padded.document.templateLines, ["A", "", "", "B"], "only trailing empty rows past the board go")
    }

    /// PLAN B24/§2.4: a canvas edit writes only `canvases`; unknown canvas, content and shape keys,
    /// every untouched number's lexeme and every other page key are byte-identical.
    func testSetCanvasesIsLossless() throws {
        let raw = ##"{"id":"p","revision":"r1","name":"N","type":"template","device_type":"panel","grid_rows":10,"grid_cols":16,"template":["lower {{date_time.time}}"],"line_metadata":null,"canvases":[{"id":"sun","area":{"row":1,"col":1,"rows":5,"cols":8},"scale":1,"bleed":[],"text":"hide","future_canvas":{"n":1.000e+99},"content":{"size":[32,30],"background":null,"palette":{"a":"yellow"},"pixels":["aa"],"future_content":[null],"shapes":[{"type":"gradient","from":"#000033","to":"#3366ff","angle":90.0},{"type":"rect","x":1,"y":2,"w":3,"h":4,"fill":"red","future_shape":922337203685477580712345}]}},{"id":"keep","area":{"row":6,"col":9,"rows":2,"cols":2},"source":"{{plugin.art}}"}],"future":12345678901234567890}"##
        let original = try PageDocument(data: Data(raw.utf8))
        var session = try DocumentEditingSession(data: Data(raw.utf8))
        XCTAssertTrue(original.canvasesAreEditable)
        XCTAssertEqual(original.legacyCanvases.map(\.id), ["sun", "keep"])
        var canvases = original.legacyCanvases
        canvases[0].shapes[1] = CanvasShape.moved(CanvasShape(canvases[0].shapes[1])!, dx: 2, dy: 0).json
        canvases[0].area = CanvasArea(row: 1, col: 1, rows: 5, cols: 9)
        try session.setCanvases(canvases, action: "Move shape")
        guard case .object(let changed) = try session.document.changedFields(from: original) else { return XCTFail() }
        XCTAssertEqual(Set(changed.keys), ["canvases"])
        let text = String(decoding: try session.document.serializedData(), as: UTF8.self)
        for kept in ["1.000e+99", #""future_content":[null]"#, #""angle":90.0"#, "922337203685477580712345",
                     #""source":"{{plugin.art}}""#, #""line_metadata":null"#, "12345678901234567890", #""lower {{date_time.time}}""#] {
            XCTAssertTrue(text.contains(kept), kept)
        }
        guard case .array(let after) = session.document.root["canvases"], case .array(let before) = original.root["canvases"] else { return XCTFail() }
        XCTAssertEqual(after[1], before[1], "an untouched canvas is byte-identical")
        XCTAssertEqual(CanvasShape(LegacyCanvas(after[0])!.shapes[1])!.object["x"], .number("3"))
        XCTAssertEqual(LegacyCanvas(after[0])!.shapes[0], LegacyCanvas(before[0])!.shapes[0], "a preserved gradient is untouched")
        try session.undo()
        XCTAssertEqual(try session.document.serializedData(), try original.serializedData(), "one undo step")
        // Absent / null stay absent / null when nothing is added; adding writes an array.
        for source in [#"{"type":"template","template":["A"]}"#, #"{"type":"template","template":["A"],"canvases":null}"#] {
            var document = try PageDocument(data: Data(source.utf8))
            let before = document
            try document.setCanvases([LegacyCanvas]())
            XCTAssertEqual(document, before)
            try document.setCanvases([LegacyCanvas.make(id: "canvas1", area: CanvasArea(row: 1, col: 1, rows: 3, cols: 11))])
            XCTAssertEqual(document.legacyCanvases.count, 1)
        }
        // Unsupported shapes refuse the edit and leave the document unchanged.
        for source in [#"{"type":"template","template":["A"],"canvases":{}}"#, #"{"type":"template","template":["A"],"canvases":[1]}"#, #"{"type":"single","canvases":[]}"#] {
            var document = try PageDocument(data: Data(source.utf8))
            let before = document
            XCTAssertFalse(document.canvasesAreEditable)
            XCTAssertThrowsError(try document.setCanvases([LegacyCanvas]()))
            XCTAssertEqual(document, before)
        }
        var full = original
        XCTAssertThrowsError(try full.setCanvases(Array(repeating: original.legacyCanvases[0], count: 9)), "a page holds at most 8")
    }
}
