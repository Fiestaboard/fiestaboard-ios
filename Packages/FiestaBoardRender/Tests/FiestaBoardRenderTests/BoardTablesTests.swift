import XCTest
@testable import FiestaBoardRender
final class BoardTablesTests: XCTestCase {
    func testExactPunctuationBlankAndPigmentCodes() {
        XCTAssertEqual(BoardTables.cell(forCode: 37, code62: .degree), .character("!"))
        XCTAssertEqual(BoardTables.cell(forCode: 44, code62: .degree), .character("-"))
        for code in [0, 43, 45, 51, 57, 58, 61] { XCTAssertEqual(BoardTables.cell(forCode: code, code62: .degree), .blank) }
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .heart), .character("♥"))
        XCTAssertEqual(BoardTables.cell(forCode: 62, code62: .degree), .character("°"))
        for (code, color) in [(63, BoardColor.red), (64, .orange), (65, .yellow), (66, .green), (67, .blue), (68, .violet), (69, .white), (70, .black), (71, .black)] {
            XCTAssertEqual(BoardTables.cell(forCode: code, code62: .degree), .color(color))
        }
    }
}
