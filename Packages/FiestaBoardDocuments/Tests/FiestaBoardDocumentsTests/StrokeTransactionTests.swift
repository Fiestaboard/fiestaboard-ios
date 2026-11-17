import XCTest
@testable import FiestaBoardDocuments

/// Draw mode (PLAN B23): the semantics of the web's `draw-mode.ts` and `stroke-transaction.ts`
/// (`FiestaBoard@v10.3.2`), and the one-undo-step commit with alignment/wrap restore.
final class StrokeTransactionTests: XCTestCase {
    // MARK: draw-mode.ts

    func testColorTokensAreOneCellAndDynamicTokensAreDropped() {
        XCTAssertEqual(DrawMode.cells("A{{red}}B"), ["A", "{{red}}", "B"])
        // Single-brace markers, numeric codes and the purple alias are colour cells too.
        XCTAssertEqual(DrawMode.cells("{red}{63}{{purple}}{71}"), ["{{red}}", "{{red}}", "{{violet}}", "{{black}}"])
        XCTAssertEqual(DrawMode.cells("{{ RED }}"), ["{{red}}"], "Colour tokens are trimmed and case-folded")
        XCTAssertEqual(DrawMode.cells("T {{weather.temperature}}!"), ["T", " ", "!"])
        XCTAssertTrue(DrawMode.isPositional("HI {{red}} {blue}"))
        XCTAssertFalse(DrawMode.isPositional("HI {{weather.temperature}}"))
        XCTAssertFalse(DrawMode.isPositional("{{= IF(1>0,\"A\",\"B\") }}"))
        XCTAssertFalse(DrawMode.isPositional("A{{fill_space}}B"))
        // A `{token}` that is not a colour stays literal, character by character.
        XCTAssertEqual(DrawMode.cells("{sun}"), ["{", "s", "u", "n", "}"])
    }

    func testCellsToLineTrimsTrailingBlanks() {
        XCTAssertEqual(DrawMode.line(["A", " ", "{{red}}", " ", " "]), "A {{red}}")
        XCTAssertEqual(DrawMode.line([" ", " "]), "")
    }

    func testPaintLinePadsCutsAndOverwrites() {
        XCTAssertEqual(DrawMode.paint("", [(col: 3, cell: "{{red}}")], cols: 22), "   {{red}}")
        XCTAssertEqual(DrawMode.paint("HELLO", [(col: 1, cell: "{{blue}}")], cols: 22), "H{{blue}}LLO")
        XCTAssertEqual(DrawMode.paint("ABCDEF", [(col: 9, cell: "X")], cols: 4), "ABCD", "Cut at the board width; off-board paints ignored")
        XCTAssertEqual(DrawMode.paint("AB", [(col: 1, cell: " ")], cols: 22), "A", "The eraser writes a blank, trimmed at the end")
        XCTAssertEqual(DrawMode.paint("T {{weather.temperature}}!", [(col: 0, cell: "{{red}}")], cols: 22), "{{red}} !",
                       "Painting a row drops its variables (positional rows have no dynamic width)")
    }

    func testBrushCells() {
        XCTAssertEqual(DrawMode.cell(for: .color("red")), "{{red}}")
        XCTAssertEqual(DrawMode.cell(for: .color("purple")), "{{violet}}")
        XCTAssertEqual(DrawMode.cell(for: .eraser), " ")
        XCTAssertEqual(DrawMode.cell(for: .character("a")), "A", "Stamps are uppercased")
        XCTAssertEqual(DrawMode.cell(for: .character("°")), "°")
        XCTAssertEqual(DrawMode.cell(for: .character("~")), " ", "A character the board can't draw erases")
        XCTAssertEqual(DrawMode.characters.count, 56)
        XCTAssertEqual(DrawMode.colors.count, 8)
    }

    func testStageLineUsesSingleBraceMarkers() {
        XCTAssertEqual(DrawMode.stageLine("A{{red}}{blue}"), "A{red}{blue}")
    }

    // MARK: stroke-transaction.ts

    func testStrokeRewritesOnlyTouchedRowsAndExtendsBelowTheLastRow() throws {
        let rows = ["KEEP {{weather.temperature}}", "B", "C"]
        let paints = [CellPaint(row: 1, col: 0), CellPaint(row: 1, col: 1), CellPaint(row: 4, col: 2)]
        let stroke = try XCTUnwrap(StrokeTransaction(rows: rows, paints: paints, brush: .color("red"), cols: 22))
        XCTAssertEqual(stroke.rows, ["KEEP {{weather.temperature}}", "{{red}}{{red}}", "C", "", "  {{red}}"])
        XCTAssertEqual(stroke.paintedRows, [1, 4])
        XCTAssertNil(StrokeTransaction(rows: rows, paints: [], brush: .eraser, cols: 22), "No cells, no stroke")
        XCTAssertNil(StrokeTransaction(rows: rows, paints: [CellPaint(row: 0, col: 30)], brush: .eraser, cols: 22), "Off the board")
    }

    func testPreviewComposesPaintedLocalAndServerRows() {
        let rows = ["HI {{red}}", "{{weather.temperature}}", "CENTRED"]
        let lines = StrokeTransaction.preview(rows: rows, serverLines: ["SRV0", "72", "  CENTRED"],
                                              alignment: { $0 == 2 ? "center" : "left" }, wrap: { _ in false },
                                              pending: [CellPaint(row: 1, col: 1)], brush: .color("blue"), boardRows: 4, cols: 22)
        XCTAssertEqual(lines, ["HI {red}", " {blue}", "  CENTRED", ""],
                       "Positional left rows are drawn locally; the painted row shows its committed result; centred rows keep the server's")
    }

    // MARK: Commit: one undo step, alignment/wrap forced and restored

    func testStrokeIsOneUndoStepThatRestoresTextAlignmentAndWrap() throws {
        let data = Data(#"{"type":"template","template":["HELLO","{{weather.temperature}}"],"line_metadata":[{"alignment":"center","wrap":true},{"alignment":"right","wrap":false}]}"#.utf8)
        var session = try DocumentEditingSession(data: data)
        let before = session.document
        let stroke = try XCTUnwrap(StrokeTransaction(rows: before.templateLines!, paints: [CellPaint(row: 0, col: 0), CellPaint(row: 1, col: 3)],
                                                     brush: .color("red"), cols: 22))
        try session.applyStroke(stroke)
        XCTAssertEqual(session.document.templateLines, ["{{red}}ELLO", "   {{red}}"])
        XCTAssertEqual(session.document.lineAlignment(at: 0), "left"); XCTAssertFalse(session.document.lineWrap(at: 0))
        XCTAssertEqual(session.document.lineAlignment(at: 1), "left"); XCTAssertFalse(session.document.lineWrap(at: 1))
        XCTAssertEqual(session.undoActionName, "Paint")
        try session.undo()
        XCTAssertEqual(session.document, before, "One undo restores the text and each row's alignment and wrap")
        try session.redo()
        XCTAssertEqual(session.document.templateLines, ["{{red}}ELLO", "   {{red}}"])
    }

    func testStrokeOnALeftPageKeepsAbsentMetadataAbsent() throws {
        var document = try PageDocument(data: Data(#"{"type":"template","template":["A","B"]}"#.utf8))
        let stroke = try XCTUnwrap(StrokeTransaction(rows: ["A", "B"], paints: [CellPaint(row: 1, col: 2)], brush: .character("x"), cols: 22))
        try document.applyStroke(stroke)
        XCTAssertEqual(document.templateLines, ["A", "B X"])
        XCTAssertNil(document.root["line_metadata"], "Left/no-wrap rows need no entry")
    }
}
