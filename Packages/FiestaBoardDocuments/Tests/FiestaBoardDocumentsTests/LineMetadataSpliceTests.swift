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
}
