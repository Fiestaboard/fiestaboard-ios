import XCTest
@testable import FiestaBoardDocuments

final class LineMetadataSpliceTests: XCTestCase {
    private func entry(_ alignment: String, _ wrap: Bool) -> LosslessJSON {
        .object(["alignment": .string(alignment), "wrap": .bool(wrap)])
    }
    private func page(_ json: String) throws -> PageDocument { try PageDocument(data: Data(json.utf8)) }

    func testMiddleInsertKeepsNeighboursAndAddsDefault() {
        let old = ["A", "B", "C"]
        let new = ["A", "B", "", "C"]  // Return at the end of row 2
        let spliced = LineMetadataSplice.splice(old: old, new: new, metadata: .array([entry("left", false), entry("center", true), entry("right", false)]))
        XCTAssertEqual(spliced, .array([entry("left", false), entry("center", true), LineMetadataSplice.defaultEntry, entry("right", false)]))
    }

    func testMiddleSplitOfARowInsertsAfterTheEditedRow() {
        // Return in the middle of "HELLO": row 1 becomes "HE", a new row "LLO" follows.
        let spliced = LineMetadataSplice.splice(old: ["X", "HELLO", "Z"], new: ["X", "HE", "LLO", "Z"],
                                               metadata: .array([entry("left", false), entry("center", false), entry("right", true)]))
        guard case .array(let values) = spliced else { return XCTFail() }
        XCTAssertEqual(values.count, 4)
        XCTAssertEqual(values.first, entry("left", false))
        XCTAssertEqual(values.last, entry("right", true), "The row after the split keeps its own metadata")
    }

    func testMiddleDeleteRemovesTheJoinedRowsEntry() {
        let spliced = LineMetadataSplice.splice(old: ["A", "B", "C", "D"], new: ["A", "BC", "D"],
                                               metadata: .array([entry("left", false), entry("center", false), entry("right", false), entry("left", true)]))
        XCTAssertEqual(spliced, .array([entry("left", false), entry("center", false), entry("left", true)]))
    }

    func testAbsentAndNullStayAsTheyAre() {
        XCTAssertNil(LineMetadataSplice.splice(old: ["A"], new: ["A", "B"], metadata: nil))
        XCTAssertEqual(LineMetadataSplice.splice(old: ["A", "B"], new: ["A"], metadata: .null), .null)
    }

    func testShorterArrayIsNeverPadded() {
        let short: LosslessJSON = .array([entry("center", false)])
        // Insert beyond its end: unchanged.
        XCTAssertEqual(LineMetadataSplice.splice(old: ["A", "B", "C"], new: ["A", "B", "C", "D"], metadata: short), short)
        // Delete beyond its end: unchanged.
        XCTAssertEqual(LineMetadataSplice.splice(old: ["A", "B", "C"], new: ["A", "B"], metadata: short), short)
        // Insert inside: one default inserted, nothing padded to the row count.
        XCTAssertEqual(LineMetadataSplice.splice(old: ["A", "B", "C"], new: ["", "A", "B", "C"], metadata: short),
                       .array([LineMetadataSplice.defaultEntry, entry("center", false)]))
    }

    func testEqualRowCountLeavesMetadataBytesUntouched() {
        let metadata: LosslessJSON = .array([.object(["alignment": .string("center"), "future": .number("1.50")])])
        XCTAssertEqual(LineMetadataSplice.splice(old: ["A"], new: ["B"], metadata: metadata), metadata)
    }

    func testDocumentReplaceRowsIsOneLosslessChange() throws {
        var document = try page(#"{"type":"template","template":["a","B"],"line_metadata":[{"alignment":"center","wrap":true,"x":1.50},{"alignment":"right"}],"unknown":12345678901234567890}"#)
        try document.replaceTemplateRows(["a", "NEW", "B"])
        XCTAssertEqual(document.templateLines, ["a", "NEW", "B"])
        XCTAssertEqual(document.lineAlignment(at: 0), "center")
        XCTAssertEqual(document.lineAlignment(at: 1), "left")
        XCTAssertEqual(document.lineAlignment(at: 2), "right")
        let text = String(decoding: try document.serializedData(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""x":1.50"#)); XCTAssertTrue(text.contains("12345678901234567890"))
        XCTAssertTrue(text.contains(#""a""#), "Untouched lowercase row is byte-identical")
    }

    func testDocumentReplaceRowsKeepsAbsentMetadataAbsent() throws {
        var document = try page(#"{"type":"template","template":["{center}A"]}"#)
        try document.replaceTemplateRows(["{center}A", "B"])
        XCTAssertNil(document.root["line_metadata"])
        XCTAssertEqual(document.lineAlignment(at: 0), "center")
        XCTAssertThrowsError(try document.replaceTemplateRows(["A\nB"]))
    }

    func testSessionReplaceRowsIsOneUndoStep() throws {
        var session = try DocumentEditingSession(data: Data(#"{"type":"template","template":["","","","","",""]}"#.utf8))
        try session.replaceTemplateRows(["HE", "LLO", "", "", "", "", ""])
        XCTAssertEqual(session.undoActionName, "Typing")
        try session.undo()
        XCTAssertEqual(session.document.templateLines, ["", "", "", "", "", ""])
        XCTAssertFalse(session.canUndo)
    }

    /// W4 (real 10.3.2, WEB-P4): `/templates/render` answers 422 to `null` entries in
    /// `line_metadata`. A render request never carries one: it goes out as the full left/no-wrap
    /// object; an entry that is neither is still refused locally. The stored document is unchanged.
    func testRenderRequestsNeverCarryNullMetadataEntries() throws {
        let document = try page(#"{"type":"template","template":["","","HELLO"],"line_metadata":[null,null,{"alignment":"center","wrap":false}],"device_type":"flagship"}"#)
        let request = try LosslessJSON.parse(document.evaluationData(boardID: "kitchen", preview: true))
        guard case .object(let body) = request, case .array(let entries)? = body["line_metadata"] else { return XCTFail("no metadata") }
        XCTAssertEqual(entries, [LineMetadataSplice.defaultEntry, LineMetadataSplice.defaultEntry, entry("center", false)])
        XCTAssertFalse(String(decoding: try document.evaluationData(boardID: "kitchen", preview: true), as: UTF8.self).contains("null"))
        guard case .array(let stored)? = document.root["line_metadata"] else { return XCTFail() }
        XCTAssertEqual(stored.first, .null, "the document keeps its bytes")
        // A top-level null stays null (10.3.2 accepts `line_metadata: null`, as the corpus's
        // `page_lobby` case shows); only entries inside the array must be objects.
        let bare = try page(#"{"type":"template","template":["A"],"line_metadata":null,"device_type":"flagship"}"#)
        guard case .object(let bareBody) = try LosslessJSON.parse(bare.evaluationData(boardID: "kitchen", preview: true)) else { return XCTFail() }
        XCTAssertTrue(bareBody["line_metadata"] == nil || bareBody["line_metadata"] == .null)
        // Aligning a row of a page without metadata writes whole objects for every row up to it.
        var aligned = bare
        try aligned.setLineAlignment(at: 0, alignment: "center")
        guard case .array(let written)? = aligned.root["line_metadata"] else { return XCTFail() }
        XCTAssertTrue(written.allSatisfy { if case .object = $0 { true } else { false } })
        let other = try page(#"{"type":"template","template":["A"],"line_metadata":[7],"device_type":"flagship"}"#)
        XCTAssertThrowsError(try other.evaluationData(boardID: "kitchen", preview: true))
        XCTAssertEqual(LineMetadataSplice.requestShape(.null), .null)
    }
}
