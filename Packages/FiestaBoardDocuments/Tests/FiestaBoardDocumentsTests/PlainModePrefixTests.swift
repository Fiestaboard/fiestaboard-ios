import XCTest
@testable import FiestaBoardDocuments

/// PLAN B18: Plain mode shows `{wrap}`/`{left}`/`{center}`/`{right}` prefixes where set; `{wrap}` is
/// stripped first, then the alignment, case-insensitively; prefixes win.
final class PlainModePrefixTests: XCTestCase {
    private func page(_ json: String) throws -> PageDocument { try PageDocument(data: Data(json.utf8)) }

    func testDecodeOrderAndCase() {
        XCTAssertEqual(PlainModePrefix.decode("{WRAP}{Center}HI").alignment, "center")
        XCTAssertTrue(PlainModePrefix.decode("{wrap}{right}HI").wrap)
        XCTAssertEqual(PlainModePrefix.decode("{wrap}{right}HI").content, "HI")
        // Alignment first, then wrap: wrap is not a prefix any more (stripped first only).
        XCTAssertEqual(PlainModePrefix.decode("{center}{wrap}HI").content, "{wrap}HI")
        XCTAssertNil(PlainModePrefix.decode("HI").alignment)
        XCTAssertEqual(PlainModePrefix.encode("HI", alignment: "center", wrap: true), "{wrap}{center}HI")
        XCTAssertEqual(PlainModePrefix.encode("HI", alignment: "left", wrap: false), "HI")
    }

    func testPlainRowsShowMetadataAsPrefixes() throws {
        let document = try page(#"{"type":"template","template":["A","B","{right}C"],"line_metadata":[{"alignment":"center","wrap":true},{"alignment":"left","wrap":false}]}"#)
        XCTAssertEqual(document.plainRows, ["{wrap}{center}A", "B", "{right}C"])
    }

    func testEditingPrefixesInPlainWritesMetadataAndPrefixesWin() throws {
        var document = try page(#"{"type":"template","template":["A","B","{right}C"],"line_metadata":[{"alignment":"center","wrap":true,"x":1.50},{"alignment":"left","wrap":false}]}"#)
        try document.replacePlainRows(["{wrap}{center}A", "{RIGHT}B", "{right}C!"])
        XCTAssertEqual(document.templateLines, ["A", "B", "{right}C!"])
        XCTAssertEqual(document.lineAlignment(at: 1), "right")
        XCTAssertEqual(document.lineAlignment(at: 2), "right", "a row without an entry keeps its prefix in its text")
        let text = String(decoding: try document.serializedData(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""x":1.50"#), "untouched entry is byte-identical")
        // Removing a prefix in Plain resets the row (prefixes win).
        try document.replacePlainRows(["A", "{right}B", "{right}C!"])
        XCTAssertEqual(document.lineAlignment(at: 0), "left")
        XCTAssertFalse(document.lineWrap(at: 0))
    }

    func testPlainRoundTripWithoutChangesIsANoOp() throws {
        let original = try page(#"{"type":"template","template":["a","{center}b"]}"#)
        var document = original
        try document.replacePlainRows(document.plainRows!)
        XCTAssertEqual(document, original)
        try document.replacePlainRows(["a", "{center}b", "{wrap}c"])
        XCTAssertNil(document.root["line_metadata"], "absent metadata stays absent; prefixes stay in the text")
        XCTAssertEqual(document.lineWrap(at: 2), true)
    }

    func testClearingARowResetsItsAlignmentAndWrap() throws {
        var document = try page(#"{"type":"template","template":["A","B"],"line_metadata":[{"alignment":"center","wrap":true,"x":1},{"alignment":"right","wrap":false}]}"#)
        try document.replaceTemplateRows(["", "B"])
        XCTAssertEqual(document.lineAlignment(at: 0), "left")
        XCTAssertFalse(document.lineWrap(at: 0))
        XCTAssertEqual(document.lineAlignment(at: 1), "right")
        guard case .array(let entries) = document.root["line_metadata"], case .object(let first) = entries[0] else { return XCTFail() }
        XCTAssertEqual(first["x"], .number("1"), "other keys are kept")
    }
}
