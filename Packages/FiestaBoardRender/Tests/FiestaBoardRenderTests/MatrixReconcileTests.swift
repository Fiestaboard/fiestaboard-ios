import XCTest
@testable import FiestaBoardRender

final class MatrixReconcileTests: XCTestCase {
    func testCanonicalRasterMatchesKeptPhoneRasterForBothFontGrids() throws {
        for (font, width, height) in [("3x5", 7, 5), ("5x7", 11, 7)] {
            let display = try JSONDecoder().decode(MatrixDisplay.self, from: JSONSerialization.data(withJSONObject: [
                "geometry": ["kind": "pixels", "width": width, "height": height], "font": font]))
            let cells: [[BoardCell]] = [[.character("A"), .character("B")]]
            let canonical = MatrixRaster.make(display: display, cells: cells)
            let model = LedRasterizerTests.model(width: width, height: height, font: font)
            let legacy = LedRasterizer.raster(BoardFrame(rows: 1, cols: 2, codes: [[1, 2]]), model: model)
            XCTAssertEqual(canonical.rgb, legacy.rgb, font)
            XCTAssertEqual(canonical.lit, legacy.lit, font)
        }
    }

    func testCanonicalRasterClipsMalformedPhoneLayers() throws {
        let display = try JSONDecoder().decode(MatrixDisplay.self, from: Data("{\"geometry\":{\"kind\":\"pixels\",\"width\":5,\"height\":7}}".utf8))
        let raster = MatrixRaster.make(display: display, cells: [], layers: [
            PixelLayer(x: 0, y: 0, w: 2, h: 1, rgba: Data([255, 0, 0, 255])),
            PixelLayer(x: Int.min, y: 0, w: Int.min, h: 1, rgba: Data())])
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 0xff0000)
        XCTAssertNil(raster.pixel(x: 1, y: 0))
    }

    func testCanonicalWordRasterRetainsPhonePixelAPI() {
        let raster = MatrixRaster(width: 2, height: 1, pixels: [0xff0000, 0], text: "A")
        XCTAssertEqual(raster.rgb, [255, 0, 0, 0, 0, 0])
        XCTAssertEqual(raster.lit, [true, false])
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 0xff0000)
        XCTAssertNil(raster.pixel(x: 1, y: 0))
        XCTAssertEqual(raster.spoken(message: nil), "A")
    }

    func testNoteBezelGeometryPreservesEveryTileAndCutsPartialNoteOpen() {
        let layout = BoardLayout.make(rows: 4, cols: 34, cells: [], tileHeight: 46, noteArray: true)
        XCTAssertEqual(layout.tiles.count, 136)
        XCTAssertEqual(layout.notes.count, 6)
        XCTAssertEqual(layout.tiles[0].x, 28, accuracy: 0.0001)
        XCTAssertTrue(layout.notes.last?.openRight == true)
        XCTAssertTrue(layout.notes.last?.openBottom == true)
        XCTAssertEqual(layout.bezelBorder, 4)
        XCTAssertEqual(layout.bezelRadius, 18)
    }
}
