import XCTest
@testable import FiestaBoardRender


extension BoardLayoutTests {
    /// B3: a 2×2 Note array is 6×30 with a visibly wider gutter after column 15 and after row 3.
    func testNoteArraySeams() {
        let model = DisplayModel(summary: BoardSummaryFields(deviceType: "note_array", rows: 6, cols: 30,
                                                             deviceModel: "vestaboard_note_array"),
                                 stored: ["notes_wide": 2, "notes_tall": 2])
        XCTAssertEqual(model.geometry, .noteArray(wide: 2, tall: 2))
        XCTAssertEqual(model.rows, 6); XCTAssertEqual(model.cols, 30)
        let layout = BoardLayout.make(rows: 6, cols: 30, cells: [], tileHeight: 100, seams: model.seams)
        XCTAssertEqual(layout.tiles.count, 180)
        func tile(_ r: Int, _ c: Int) -> TileRect { layout.tiles[r * 30 + c] }
        let normalGap = tile(0, 1).x - (tile(0, 0).x + tile(0, 0).width)
        let seamGap = tile(0, 15).x - (tile(0, 14).x + tile(0, 14).width)
        XCTAssertEqual(normalGap, 14.5, accuracy: 1e-9)
        XCTAssertGreaterThan(seamGap, normalGap * 1.8, "column seam after the 15th column")
        let normalRow = tile(1, 0).y - (tile(0, 0).y + tile(0, 0).height)
        let seamRow = tile(3, 0).y - (tile(2, 0).y + tile(2, 0).height)
        XCTAssertGreaterThan(seamRow, normalRow * 1.8, "row seam after the 3rd row")
        XCTAssertEqual(tile(0, 16).x - (tile(0, 15).x + tile(0, 15).width), normalGap, accuracy: 1e-9)
        let size = BoardLayout.size(rows: 6, cols: 30, tileHeight: 100, seams: model.seams)
        XCTAssertEqual(size.width, layout.width); XCTAssertEqual(size.height, layout.height)
        XCTAssertEqual(layout.width, tile(5, 29).x + tile(5, 29).width + NoteArray.paddingRatio * 100, accuracy: 1e-9)
        // A single Note and a Flagship have no seams.
        XCTAssertNil(DisplayModel.flap(rows: 3, cols: 15, deviceType: "note").seams)
        XCTAssertNil(DisplayModel.flap(rows: 6, cols: 22).seams)
    }
}

final class DisplayModelTests: XCTestCase {
    func testUnknownModelFallsBackToFlap() {
        let model = DisplayModel(summary: BoardSummaryFields(deviceType: "flagship", rows: 4, cols: 20, deviceModel: "acme_unknown"),
                                 stored: nil)
        XCTAssertEqual(model.technology, .splitFlap)
        XCTAssertEqual(model.geometry, .cells(rows: 4, cols: 20))
        XCTAssertEqual(model.rows, 4); XCTAssertEqual(model.cols, 20)
        XCTAssertTrue(model.isFallback)
        XCTAssertEqual(model.color, .tiles)
    }

    func testMergeOfSummaryAndStoredAppearance() {
        let kitchen = DisplayModel(summary: BoardSummaryFields(deviceType: "flagship", rows: 6, cols: 22, deviceModel: "vestaboard_flagship", charset: "vestaboard_v1"),
                                   stored: ["board_color": "black", "code62_glyph": "degree"])
        XCTAssertEqual(kitchen.code62, .degree); XCTAssertFalse(kitchen.isFallback)
        let hall = DisplayModel(summary: BoardSummaryFields(deviceType: "flagship", rows: 6, cols: 22, deviceModel: "vestaboard_flagship", charset: "vestaboard_v2"),
                                stored: ["code62_glyph": "heart"])
        XCTAssertEqual(hall.code62, .heart)
        let desk = DisplayModel(summary: BoardSummaryFields(deviceType: "note", rows: 3, cols: 15, deviceModel: "vestaboard_note"),
                                stored: ["board_color": "white", "code62_glyph": "degree"])
        XCTAssertEqual(desk.boardColor, .white); XCTAssertEqual(desk.code62, .heart, "Notes always carry the heart")
        XCTAssertEqual(desk.flapPalette, .white)
        let tv = DisplayModel(summary: BoardSummaryFields(deviceType: "panel", rows: 12, cols: 29, deviceModel: "vestaboard_panel"),
                              stored: ["grid_rows": 12, "grid_cols": 29])
        XCTAssertEqual(tv.geometry, .panel(rows: 12, cols: 29)); XCTAssertEqual(tv.code62, .heart)
        let noStored = DisplayModel(summary: BoardSummaryFields(deviceType: "flagship", rows: 6, cols: 22, deviceModel: "vestaboard_flagship"), stored: nil)
        XCTAssertEqual(noStored.boardColor, .black); XCTAssertEqual(noStored.code62, .degree)
    }

    func testLedModelsDeriveTheCharacterGrid() {
        let pixoo = DisplayModel(summary: BoardSummaryFields(deviceType: "panel", rows: 10, cols: 16, deviceModel: "divoom_pixoo64"),
                                 stored: ["device_model": "divoom_pixoo64"])
        XCTAssertEqual(pixoo.technology, .ledMatrix)
        XCTAssertEqual(pixoo.geometry, .pixels(w: 64, h: 64))
        XCTAssertEqual(pixoo.font, .f3x5)
        XCTAssertEqual(pixoo.rows, 10); XCTAssertEqual(pixoo.cols, 16)
        XCTAssertTrue(pixoo.preservesCase)
        let spec: [String: Any] = ["technology": "led_matrix", "geometry": ["kind": "pixels", "width": 32, "height": 16],
                                   "color": ["kind": "monochrome", "color": "#ff3b1f"], "font": "5x7"]
        let marquee = DisplayModel(summary: BoardSummaryFields(deviceType: "panel", rows: 2, cols: 5), stored: ["device_model_spec": spec])
        XCTAssertEqual(marquee.color, .monochrome(hex: 0xff3b1f))
        XCTAssertEqual(marquee.rows, 2); XCTAssertEqual(marquee.cols, 5)
    }
}

final class BoardFrameTests: XCTestCase {
    func testCodesResolveWithTheBoardsGlyph() {
        let frame = BoardFrame(rows: 1, cols: 3, codes: [[8, 62, 63]])
        XCTAssertEqual(frame.boardCells(model: .flap(rows: 1, cols: 3)), [[.character("H"), .character("°"), .color(.red)]])
        XCTAssertEqual(frame.boardCells(model: .flap(rows: 1, cols: 3, code62: .heart)), [[.character("H"), .character("♥"), .color(.red)]])
    }

    func testMessageMarkupFollowsParseLine() {
        let cells = BoardMessageParser.cells("hi {red}{63}{/red}{purple} {icon:heart} {red/blue:ok} {x}", rows: 2, cols: 16, preserveCase: false)
        XCTAssertEqual(cells.count, 2); XCTAssertEqual(cells[0].count, 16)
        XCTAssertEqual(cells[0][0], .char("H"))
        XCTAssertEqual(cells[0][3], .color(63)); XCTAssertEqual(cells[0][4], .color(63)); XCTAssertEqual(cells[0][5], .color(68))
        XCTAssertEqual(cells[0][7], .char("♥"))
        XCTAssertEqual(cells[0][9].value, "O"); XCTAssertEqual(cells[0][9].color, "red"); XCTAssertEqual(cells[0][9].background, "blue")
        XCTAssertEqual(cells[0][12].value, "{", "unknown markup stays literal")
        XCTAssertEqual(BoardMessageParser.line("Hi", preserveCase: true).map(\.value), ["H", "i"])
    }

    func testCellsWinOverCodesAndMessage() {
        let frame = BoardFrame(rows: 1, cols: 1, codes: [[1]], cells: [[.char("Z")]], message: "Q")
        XCTAssertEqual(frame.boardCells(model: .flap(rows: 1, cols: 1)), [[.character("Z")]])
        XCTAssertEqual(BoardFrame.fromLines(["AB {63}"], rows: 1, cols: 4).boardCells(model: .flap(rows: 1, cols: 4)),
                       [[.character("A"), .character("B"), .blank, .color(.red)]])
    }

    func testSpeechReadsTheFlaps() {
        let model = DisplayModel.flap(rows: 2, cols: 5)
        XCTAssertEqual(BoardSpeech.spoken(BoardFrame(rows: 2, cols: 5, codes: [[8, 9, 0, 0, 0], [63, 0, 0, 0, 0]]), model: model), "HI")
        XCTAssertEqual(BoardSpeech.spoken(.empty(rows: 2, cols: 5), model: model), "Blank")
    }
}
