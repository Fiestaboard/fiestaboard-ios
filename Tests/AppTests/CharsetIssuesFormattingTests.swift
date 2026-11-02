import XCTest
import FiestaBoardKit
@testable import FiestaBoard

/// B16 (W4): `charset_issues` as the editor lists them, and validate errors at the server's
/// 0-based column (10.3.2 reports a formula error at column 0).
@MainActor final class CharsetIssuesFormattingTests: XCTestCase {
    func testIssuesReadAsLinesWithAFallbackAndAreCapped() throws {
        // The wire shape: FiestaUI `CharsetValidationIssue`, tokens keyed by `type`.
        let json = #"[{"row":1,"col":0,"token":{"type":"char","value":"l"},"reason":"case","fallback":{"type":"char","value":"L"}},"#
            + #"{"row":0,"col":3,"token":{"type":"color","code":"63"},"reason":"tile","fallback":{"type":"char","value":" "}}]"#
        let issues = try JSONDecoder().decode([TemplateCharsetIssue].self, from: Data(json.utf8))
        XCTAssertEqual(issues[0].token?.kind, "char")
        XCTAssertEqual(issues[1].token?.code, "63")
        XCTAssertEqual(EditorStrings.charsetIssueLines(issues), [
            "Line 2, column 1: this board can't show “l” and draws “L” instead.",
            "Line 1, column 4: this board can't show 63 tile and draws a blank instead.",
        ])
        let many = (0..<7).map { TemplateCharsetIssue(row: 0, col: $0, token: .init(kind: "char", value: "x"), reason: "case", fallback: .init(kind: "char", value: "X")) }
        let lines = EditorStrings.charsetIssueLines(many)
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines.last, "…and 2 more")
    }

    func testValidateErrorAtColumnZeroReadsAsColumnOne() throws {
        let issue = try JSONDecoder().decode(TemplateValidationIssue.self, from: Data(#"{"line":1,"column":0,"message":"Formula #NAME?: Unknown function: BOGUS"}"#.utf8))
        XCTAssertEqual(EditorStrings.validationIssue(issue), "Line 1, column 1: Formula #NAME?: Unknown function: BOGUS")
    }
}
