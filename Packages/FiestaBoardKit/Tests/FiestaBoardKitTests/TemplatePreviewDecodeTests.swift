import XCTest
@testable import FiestaBoardKit

/// PLAN §3.3: `TemplatePreviewResult` fully decodes `charset_issues`, `canvas_issues` and `layers`
/// (verified 10.3.2 shapes, §2.3) while keeping every existing count and failure rule.
final class TemplatePreviewDecodeTests: XCTestCase {
    func testOptionalMembersDecodeFully() throws {
        let raw = ##"{"rendered":"HÉ","lines":["HÉ"],"line_count":1,"charset":"vestaboard","charset_issues":[{"row":0,"col":1,"token":{"kind":"char","value":"É"},"reason":"unsupported","fallback":{"kind":"char","value":"E"}},{"unexpected":true}],"canvas_issues":[{"canvas_id":"c1","path":"shapes[0].x","message":"#NAME? x"}],"layers":[{"x":0,"y":0,"width":1,"height":1,"rgba":"AAAA/w=="}]}"##
        let result = try TemplatePreviewResult(rawData: Data(raw.utf8))
        XCTAssertEqual(result.charsetIssueCount, 2, "Counts stay exact")
        XCTAssertEqual(result.charsetIssues.count, 1, "Unmatched elements are skipped, not fatal")
        XCTAssertEqual(result.charsetIssues.first?.row, 0)
        XCTAssertEqual(result.charsetIssues.first?.col, 1)
        XCTAssertEqual(result.charsetIssues.first?.token?.value, "É")
        XCTAssertEqual(result.charsetIssues.first?.fallback?.value, "E")
        XCTAssertEqual(result.canvasIssues, [TemplateCanvasIssue(canvasID: "c1", path: "shapes[0].x", message: "#NAME? x")])
        XCTAssertEqual(result.layers.first?.width, 1)
        XCTAssertEqual(result.layers.first?.rgba, "AAAA/w==")
    }

    func testAbsentAndNullMembersAreEmpty() throws {
        for raw in [#"{"rendered":"A","lines":["A"],"line_count":1}"#,
                    #"{"rendered":"A","lines":["A"],"line_count":1,"charset":null,"charset_issues":null}"#] {
            let result = try TemplatePreviewResult(rawData: Data(raw.utf8))
            XCTAssertEqual(result.charsetIssues, []); XCTAssertEqual(result.canvasIssues, []); XCTAssertEqual(result.layers, [])
        }
    }
}
