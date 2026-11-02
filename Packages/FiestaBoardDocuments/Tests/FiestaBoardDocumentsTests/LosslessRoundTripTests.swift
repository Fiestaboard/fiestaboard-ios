import XCTest
@testable import FiestaBoardDocuments

/// PLAN B28 / §2.2: a page with lowercase text and a `line_metadata` shorter than `template` opens in
/// the document editor; editing one row leaves every other byte of the page as it was.
final class LosslessRoundTripTests: XCTestCase {
    private let raw = #"{"id":"p","revision":"r7","name":"Desk","type":"template","device_type":"note","template":["lower row kept","{{date_time.time}}","{center}C"],"line_metadata":[{"alignment":"center","wrap":false,"x":1.50}],"future":12345678901234567890,"n":1.000}"#

    private func text(_ document: PageDocument) throws -> String { String(decoding: try document.serializedData(), as: UTF8.self) }

    func testShortMetadataIsEditableAndReadsLikeTheServer() throws {
        let document = try PageDocument(data: Data(raw.utf8))
        XCTAssertEqual(document.editableTemplateLines, ["lower row kept", "{{date_time.time}}", "{center}C"])
        XCTAssertEqual(document.lineAlignment(at: 0), "center")
        // Rows without an entry are read from their legacy prefixes, as `templates/engine.py` does.
        XCTAssertEqual(document.lineAlignment(at: 1), "left")
        XCTAssertEqual(document.lineAlignment(at: 2), "center")
        XCTAssertFalse(document.lineWrap(at: 1))
        // The empty array is short too.
        XCTAssertNotNil(try PageDocument(data: Data(#"{"type":"template","template":["a"],"line_metadata":[]}"#.utf8)).editableTemplateLines)
    }

    func testUntouchedRowsAndCaseAreByteIdentical() throws {
        let original = try PageDocument(data: Data(raw.utf8))
        var document = original
        // Edit one *other* row (row 2), as the document editor commits it: the whole row list.
        try document.replaceTemplateRows(["lower row kept", "NEW {{date_time.time}}", "{center}C"])
        XCTAssertEqual(document.root["line_metadata"], original.root["line_metadata"], "No row count change: metadata bytes untouched")
        try document.setLineAlignment(at: 1, alignment: "right")
        let out = try text(document)
        for kept in [#""lower row kept""#, #""{center}C""#, #""x":1.50"#, "12345678901234567890", #""n":1.000"#, #""revision":"r7""#] {
            XCTAssertTrue(out.contains(kept), "\(kept) must survive byte-identical")
        }
        // Entries are written only up to the changed row; the untouched row 3 gets none.
        guard case .array(let metadata) = document.root["line_metadata"] else { return XCTFail("metadata") }
        XCTAssertEqual(metadata.count, 2)
        guard case .array(let before) = original.root["line_metadata"] else { return XCTFail("before") }
        XCTAssertEqual(metadata[0], before[0])
        XCTAssertEqual(metadata[1], .object(["alignment": .string("right"), "wrap": .bool(false)]))
        // Only template and line_metadata are reported as changed.
        guard case .object(let changed) = try document.changedFields(from: original) else { return XCTFail("changed") }
        XCTAssertEqual(Set(changed.keys), ["template", "line_metadata"])
    }

    func testPaddingKeepsTheEffectiveFormattingOfRowsThatGainAnEntry() throws {
        var document = try PageDocument(data: Data(raw.utf8))
        try document.setLineWrap(at: 2, wrap: true)
        // Row 2 had no prefix: its text is untouched. Row 3's `{center}` moves into its entry.
        XCTAssertEqual(document.templateLines, ["lower row kept", "{{date_time.time}}", "C"])
        XCTAssertEqual(document.lineAlignment(at: 2), "center")
        XCTAssertTrue(document.lineWrap(at: 2))
        XCTAssertEqual(document.lineAlignment(at: 1), "left")
    }

    func testStructuralEditsPastAShortArrayNeverTrap() throws {
        var document = try PageDocument(data: Data(raw.utf8))
        try document.insertTemplateLine(at: 3, with: "D")
        try document.duplicateTemplateLine(at: 2)
        try document.removeTemplateLine(at: 4)
        try document.moveTemplateLine(from: 2, to: 0)
        XCTAssertEqual(document.templateLines?.count, 4)
        XCTAssertEqual(document.lineAlignment(at: 0), "center")
        try document.replaceTemplateRows(["A", "B"])
        XCTAssertEqual(document.templateLines, ["A", "B"])
    }

    func testDeskNoteFixtureShapeIsEditable() throws {
        let note = #"{"id":"note","name":"Desk Note","type":"template","device_type":"note","template":["HELLO","{{date_time.time}}","{{red}} LOVE {{red}}"],"line_metadata":[{"alignment":"center","wrap":false},{"alignment":"center","wrap":false}]}"#
        let document = try PageDocument(data: Data(note.utf8))
        XCTAssertEqual(document.editableTemplateLines?.count, 3)
        XCTAssertEqual(TemplateGeometry(document: document), TemplateGeometry(document: document))
        XCTAssertEqual(TemplateGeometry(document: document)?.rows, 3)
        XCTAssertEqual(TemplateGeometry(document: document)?.columns, 15)
    }

    func testSessionRoundTripIsOneUndoStepAndLossless() throws {
        var session = try DocumentEditingSession(data: Data(raw.utf8))
        let original = session.document
        try session.replaceTemplateRows(["lower row kept", "X", "{center}C"])
        try session.undo()
        XCTAssertEqual(try text(session.document), try text(original))
    }
}
