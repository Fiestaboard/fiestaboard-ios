import XCTest
@testable import FiestaBoardDocuments

final class TemplateSyntaxTests: XCTestCase {
    func testBothFamiliesRoundTripWithoutNormalization() {
        let examples = ["", "e\u{301} é \u{200B} 😀", "A{{RED}}{{fill_space_repeat:a:b}}Z", "{{weather:sf.temperature|pad:3}}", "{{= 1 + 1 }}", "{{red:{{demo.temp}}°}}", "{{black/white:A{{red:B}}C}}", "{{icon:sun}}", "broken {{red", "{{{future}}}", "{63}{red}"]
        for source in examples {
            let result = TemplateSyntax.fragments(source)
            XCTAssertEqual(Array(result.map(\.source).joined().utf8), Array(source.utf8), source)
        }
    }
    func testBalancedLEDSpanDoesNotEatAdjacentVariable() {
        let result = TemplateSyntax.fragments("{{red:{{demo.temp}}°}}{{weather:sf.temp}}")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kind, .span)
        XCTAssertEqual(result[1].kind, .expression)
        XCTAssertEqual(result[0].source, "{{red:{{demo.temp}}°}}")
    }
    func testAtomKindsAndIncompleteSyntax() {
        XCTAssertEqual(TemplateSyntax.fragments("{{RED}}{{fill_space}}{{= x }}{{icon:sun}}{{black/white:OPEN}}{blue}").map(\.kind), [.tile, .fill, .formula, .icon, .span, .tile])
        XCTAssertEqual(TemplateSyntax.fragments("before {{unfinished").map(\.kind), [.text])
        XCTAssertEqual(TemplateSyntax.fragments("{{{future}}}").map(\.kind), [.text])
    }
    func testUTF16MappingPreservesTokenBoundaryAndEmoji() {
        let source = "😀{{weather.temp}}e\u{301}"
        // Rich storage: surrogate pair, one attachment, two scalars.
        XCTAssertEqual(TemplateSyntax.sourceOffset(displayOffset: 3, in: source), 18)
        XCTAssertEqual(TemplateSyntax.displayOffset(sourceOffset: 18, in: source), 3)
        XCTAssertEqual(TemplateSyntax.sourceOffset(displayOffset: 5, in: source), 20)
        XCTAssertEqual(TemplateSyntax.displayOffset(sourceOffset: 8, in: source), 2)
    }
}

final class TemplateGeometryTests: XCTestCase {
    func testExactBoardGeometryAndUnknownShapes() throws {
        for (json, rows, columns) in [
            (#"{"device_type":"flagship"}"#, 6, 22),
            (#"{"device_type":"note"}"#, 3, 15),
            (#"{"device_type":"note_array","notes_wide":3,"notes_tall":2}"#, 6, 45),
            (#"{"device_type":"panel","grid_rows":12,"grid_cols":64}"#, 12, 64)
        ] {
            let geometry = TemplateGeometry(document: try PageDocument(data: Data(json.utf8)))
            XCTAssertEqual(geometry?.rows, rows); XCTAssertEqual(geometry?.columns, columns)
        }
        for json in [#"{"device_type":"panel","grid_rows":1,"grid_cols":10}"#, #"{"device_type":"panel","grid_rows":3,"grid_cols":9}"#, #"{"device_type":"future"}"#, #"{"device_type":"panel"}"#, #"{"device_type":"panel","grid_rows":1,"grid_cols":99999}"#, #"{"device_type":"note_array","notes_wide":0}"#] {
            XCTAssertNil(TemplateGeometry(document: try PageDocument(data: Data(json.utf8))))
        }
    }
}
