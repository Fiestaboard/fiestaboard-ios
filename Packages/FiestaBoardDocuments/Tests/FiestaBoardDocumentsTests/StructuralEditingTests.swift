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
}
