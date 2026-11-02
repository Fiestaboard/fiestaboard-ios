import XCTest
import FiestaBoardKit
@testable import FiestaBoard

/// B16: `charset_issues` as the editor lists them, grouped per row and per reason (P5, the
/// same wording as Android AND-P5), and validate errors at the server's 0-based column.
@MainActor final class CharsetIssuesFormattingTests: XCTestCase {
    private func issue(_ row: Int, _ col: Int, _ value: String, _ reason: String, _ fallback: String) -> TemplateCharsetIssue {
        TemplateCharsetIssue(row: row, col: col, token: .init(kind: "char", value: value), reason: reason, fallback: .init(kind: "char", value: fallback))
    }

    func testIssuesAreGroupedPerRowAndReason() throws {
        // Re-recorded (P5): one line per row and reason replaces one line per character.
        // The wire shape: FiestaUI `CharsetValidationIssue`, tokens keyed by `type`.
        let json = #"[{"row":1,"col":0,"token":{"type":"char","value":"l"},"reason":"case","fallback":{"type":"char","value":"L"}},"#
            + #"{"row":0,"col":3,"token":{"type":"color","code":"63"},"reason":"tile","fallback":{"type":"char","value":" "}}]"#
        let decoded = try JSONDecoder().decode([TemplateCharsetIssue].self, from: Data(json.utf8))
        XCTAssertEqual(decoded[0].token?.kind, "char")
        XCTAssertEqual(decoded[1].token?.code, "63")
        let lower = "lower row kept".enumerated().filter { $0.element != " " }.map { issue(1, $0.offset, String($0.element), "case", $0.element.uppercased()) }
        XCTAssertEqual(lower.count, 12)
        let issues = lower + [issue(3, 2, "é", "char", "?"), issue(3, 5, "ñ", "char", "?"), issue(3, 7, "é", "char", "?")] + [decoded[1]]
        XCTAssertEqual(EditorStrings.charsetIssueGroups(issues), [
            "Line 1: the red tile can't be shown; the board draws a blank (1).",
            "Line 2: lowercase letters show as capitals on this board (12).",
            "Line 4: “é” and “ñ” can't be shown; the board draws ? (3).",
        ])
    }

    func testOtherReasonsReadPlainly() {
        let icon = TemplateCharsetIssue(row: 0, col: 4, token: .init(kind: "char", value: " ", icon: "bus"), reason: "icon", fallback: .init(kind: "char", value: " "))
        let span = TemplateCharsetIssue(row: 1, col: 0, token: .init(kind: "char", value: "7", color: "red"), reason: "colorSpan", fallback: .init(kind: "char", value: "7"))
        let many = ["à", "ü", "ø", "ß"].enumerated().map { issue(2, $0.offset, $0.element, "char", "?") }
        XCTAssertEqual(EditorStrings.charsetIssueGroups([span, icon] + many), [
            "Line 1: the bus icon can't be shown; the board draws a blank (1).",
            "Line 2: colored text shows without its color on this board (1).",
            "Line 3: “à”, “ü”, “ø” and 1 more can't be shown; the board draws ? (4).",
        ])
    }

    func testValidateErrorAtColumnZeroReadsAsColumnOne() throws {
        let issue = try JSONDecoder().decode(TemplateValidationIssue.self, from: Data(#"{"line":1,"column":0,"message":"Formula #NAME?: Unknown function: BOGUS"}"#.utf8))
        XCTAssertEqual(EditorStrings.validationIssue(issue), "Line 1, column 1: Formula #NAME?: Unknown function: BOGUS")
    }
}
