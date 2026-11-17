import XCTest
@testable import FiestaBoardRender

final class BoardViewportTests: XCTestCase {
    func testEdgeHintsTrackStartMiddleAndEndAndIgnoreBounce() {
        XCTAssertEqual(BoardViewportEdges(offset: 0, contentWidth: 600, viewportWidth: 200), .init(leading: false, trailing: true))
        XCTAssertEqual(BoardViewportEdges(offset: 200, contentWidth: 600, viewportWidth: 200), .init(leading: true, trailing: true))
        XCTAssertEqual(BoardViewportEdges(offset: 400, contentWidth: 600, viewportWidth: 200), .init(leading: true, trailing: false))
        XCTAssertEqual(BoardViewportEdges(offset: -25, contentWidth: 600, viewportWidth: 200), .init(leading: false, trailing: true))
        XCTAssertEqual(BoardViewportEdges(offset: 425, contentWidth: 600, viewportWidth: 200), .init(leading: true, trailing: false))
        XCTAssertEqual(BoardViewportEdges(offset: 0, contentWidth: 180, viewportWidth: 200), .init(leading: false, trailing: false))
    }

    func testReadableTilesNeverShrinkBelowThirteenPoints() {
        let geometry = BoardViewportGeometry(rows: 12, cols: 29, viewportWidth: 180, tileHeight: 13)
        XCTAssertEqual(geometry.tileHeight, 13)
        XCTAssertEqual(geometry.contentWidth, 317)
        XCTAssertTrue(geometry.scrolls)
        XCTAssertEqual(geometry.noteCount, 1)
    }

    func testNotePagingUsesWholeNotesAndClampsAccessibleActions() {
        let geometry = BoardViewportGeometry(rows: 3, cols: 45, viewportWidth: 180, tileHeight: 13, notes: true)
        XCTAssertEqual(geometry.noteCount, 3)
        XCTAssertEqual(geometry.columnsPerPage, 15)
        XCTAssertEqual(geometry.next(after: 0), 1)
        XCTAssertEqual(geometry.next(after: 2), 2)
        XCTAssertEqual(geometry.previous(before: 0), 0)
        XCTAssertEqual(geometry.previous(before: 2), 1)
        XCTAssertEqual(geometry.label(page: 1), "Note 2 of 3")
    }

    func testPartialNotesDoNotInventCells() {
        let geometry = BoardViewportGeometry(rows: 4, cols: 34, viewportWidth: 200, notes: true)
        XCTAssertEqual(geometry.noteCount, 6)
        XCTAssertEqual(geometry.bounds(page: 5).rows, 3..<4)
        XCTAssertEqual(geometry.bounds(page: 5).cols, 30..<34)
        XCTAssertEqual(geometry.bounds(page: 99).cols, 30..<34)
    }

    func testInvalidInputsRemainFiniteAndBounded() {
        let geometry = BoardViewportGeometry(rows: Int.max, cols: Int.max, viewportWidth: .nan, tileHeight: .infinity)
        XCTAssertEqual(geometry.rows, BoardFrame.maxDimension)
        XCTAssertEqual(geometry.cols, BoardFrame.maxDimension)
        XCTAssertTrue(geometry.contentWidth.isFinite)
        XCTAssertGreaterThanOrEqual(geometry.tileHeight, 13)
    }

    func testWholePointMetricsMatchTvReferenceAtFortySixPoints() {
        let layout = BoardLayout.make(rows: 12, cols: 29, cells: [], tileHeight: 46)
        XCTAssertEqual(layout.tiles.count, 348)
        XCTAssertEqual(layout.tiles[0].width, 32)
        XCTAssertEqual(layout.tiles[1].x, 39)
        XCTAssertEqual(layout.width, 1124)
        XCTAssertEqual(layout.height, 629)
    }

    func testSmallLEDEnlargementUsesInnerBezelWidthAndPreservesAspect() {
        let sizing = MatrixViewportSizing(pixelWidth: 32, pixelHeight: 8, availableWidth: 370, maximumHeight: 240)
        XCTAssertEqual(sizing.pitch, 354.0 / 32, accuracy: 0.0001)
        XCTAssertEqual(sizing.contentWidth, 354, accuracy: 0.0001)
        XCTAssertEqual(sizing.contentHeight, 88.5, accuracy: 0.0001)
        XCTAssertEqual(sizing.viewportWidth, 370)
        XCTAssertEqual(sizing.viewportHeight, 104.5, accuracy: 0.0001)
        XCTAssertFalse(sizing.horizontalOverflow)
        XCTAssertFalse(sizing.verticalOverflow)
    }

    func testNarrowLEDViewportKeepsTwoPointPitchAndHorizontalOverflow() {
        let sizing = MatrixViewportSizing(pixelWidth: 32, pixelHeight: 8, availableWidth: 40, maximumHeight: 240)
        XCTAssertEqual(sizing.pitch, 2)
        XCTAssertEqual(sizing.contentWidth, 64)
        XCTAssertEqual(sizing.viewportWidth, 40)
        XCTAssertTrue(sizing.horizontalOverflow)
        XCTAssertFalse(sizing.verticalOverflow)
    }

    func testTallLEDEnlargementRespectsCappedViewportHeight() {
        let sizing = MatrixViewportSizing(pixelWidth: 16, pixelHeight: 80, availableWidth: 370, maximumHeight: 240)
        XCTAssertEqual(sizing.pitch, 2.8, accuracy: 0.0001)
        XCTAssertEqual(sizing.contentWidth, 44.8, accuracy: 0.0001)
        XCTAssertEqual(sizing.contentHeight, 224, accuracy: 0.0001)
        XCTAssertEqual(sizing.viewportHeight, 240)
        XCTAssertFalse(sizing.verticalOverflow)
    }

    func testLargeLEDKeepsBothAxesScrollableInsteadOfShrinkingOrClippingRaster() {
        let sizing = MatrixViewportSizing(pixelWidth: 512, pixelHeight: 256, availableWidth: 370, maximumHeight: 240)
        XCTAssertEqual(sizing.pitch, 2)
        XCTAssertEqual(sizing.contentWidth, 1024)
        XCTAssertEqual(sizing.contentHeight, 512)
        XCTAssertEqual(sizing.viewportHeight, 240)
        XCTAssertTrue(sizing.horizontalOverflow)
        XCTAssertTrue(sizing.verticalOverflow)
    }

    func testUnspecifiedOrNonfiniteWidthDoesNotInventAnEnlargement() {
        for width: Double? in [nil, .nan, .infinity] {
            let sizing = MatrixViewportSizing(pixelWidth: 32, pixelHeight: 8, availableWidth: width, maximumHeight: 240)
            XCTAssertEqual(sizing.pitch, 2)
            XCTAssertEqual(sizing.viewportWidth, 80)
            XCTAssertEqual(sizing.viewportHeight, 32)
        }
    }

    func testDD24SquareDotsRoundOnlyAtSixDevicePixels() {
        XCTAssertEqual(LedDot.cornerRadius(dot: 2, scale: 2), 0)
        XCTAssertEqual(LedDot.cornerRadius(dot: 2, scale: 3), 0.3, accuracy: 0.0001)
        XCTAssertEqual(LedDot.cornerRadius(dot: 6, scale: 1), 0.9, accuracy: 0.0001)
    }
}
