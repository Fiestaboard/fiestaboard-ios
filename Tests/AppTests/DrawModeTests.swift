import XCTest
import FiestaBoardDocuments
import FiestaBoardRender
@testable import FiestaBoard

/// Draw mode's hit-testing and stroke bookkeeping (PLAN B23, iOS-F1).
@MainActor final class DrawModeTests: XCTestCase {
    func testTileUnderAPointFollowsTheBoardGeometry() throws {
        let model = DisplayModel.flap(rows: 6, cols: 22)
        let aspect = BoardFrameView.flapAspect(model)
        let size = CGSize(width: 400, height: 400 / aspect)
        // Tile centres in tile-height units: bezel 0.40+0.10 / 0.55+0.10, tile 0.70 wide, gutter 0.145.
        let h = Double(size.width) / (22 * 0.845 - 0.145 + 1.0)
        func centre(_ row: Int, _ col: Int) -> CGPoint {
            CGPoint(x: h * (0.5 + Double(col) * 0.845 + 0.35), y: h * (0.65 + Double(row) * 1.145 + 0.5))
        }
        XCTAssertEqual(DrawModeController.cell(at: centre(0, 0), size: size, model: model), CellPaint(row: 0, col: 0))
        XCTAssertEqual(DrawModeController.cell(at: centre(5, 21), size: size, model: model), CellPaint(row: 5, col: 21))
        XCTAssertEqual(DrawModeController.cell(at: centre(2, 9), size: size, model: model), CellPaint(row: 2, col: 9))
        XCTAssertNil(DrawModeController.cell(at: CGPoint(x: -40, y: -40), size: size, model: model), "Outside the board")
    }

    func testFastDragsFillTheCellsBetweenAndRepeatsAreIgnored() {
        let draw = DrawModeController()
        draw.add(CellPaint(row: 0, col: 0))
        draw.add(CellPaint(row: 0, col: 0))
        draw.add(CellPaint(row: 0, col: 4))
        XCTAssertEqual(draw.pending.map(\.col), [0, 1, 2, 3, 4])
        draw.add(CellPaint(row: 2, col: 4))
        XCTAssertEqual(draw.pending.last, CellPaint(row: 2, col: 4))
        XCTAssertTrue(draw.pending.contains(CellPaint(row: 1, col: 4)))
        draw.brush = .color("blue")
        let stroke = draw.finish(rows: ["HELLO"], cols: 22)
        XCTAssertEqual(stroke?.rows.first, "{{blue}}{{blue}}{{blue}}{{blue}}{{blue}}")
        XCTAssertEqual(stroke?.paintedRows, [0, 1, 2])
        XCTAssertTrue(draw.pending.isEmpty, "Finishing clears the stroke")
    }
}
