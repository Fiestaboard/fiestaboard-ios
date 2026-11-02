import Foundation
import XCTest
@testable import FiestaBoardDocuments

/// The editor's own canvas drawing (a port of `src/canvas/{geometry,raster}.py`) and the Draw
/// tab's palette encoding (web `encodePixels`).
final class CanvasRasterTests: XCTestCase {
    private let pixoo = CanvasBoard(width: 64, height: 64, glyphWidth: 3, glyphHeight: 5)

    private func canvas(_ json: String) throws -> LegacyCanvas {
        LegacyCanvas(try LosslessJSON.parse(Data(json.utf8)))!
    }

    func testPlacementMatchesTheServerGeometry() throws {
        // Pixoo 64×64, 3×5 font: 16 × 10 cells, origin (0, 2) (`grid_layout`).
        XCTAssertEqual(pixoo.cols, 16); XCTAssertEqual(pixoo.rows, 10)
        XCTAssertEqual(pixoo.originX, 0); XCTAssertEqual(pixoo.originY, 2)
        let c = try canvas(##"{"id":"a","area":{"row":1,"col":1,"rows":5,"cols":8}}"##)
        XCTAssertEqual(CanvasPlacement.of(c, board: pixoo), CanvasPlacement(x: 0, y: 2, width: 31, height: 29, scale: 1))
        var bled = c; bled.bleed = ["top", "left"]; bled.scale = 2
        // Rect (0,0)-(31,31): 31×31 → 15×15 blocks of 2, centred with the odd pixel right/bottom.
        XCTAssertEqual(CanvasPlacement.of(bled, board: pixoo), CanvasPlacement(x: 0, y: 0, width: 15, height: 15, scale: 2))
        XCTAssertNil(CanvasPlacement.of(try canvas(##"{"id":"a","area":{"row":0,"col":0,"rows":5,"cols":8}}"##), board: pixoo))
    }

    func testRectCircleLineAndPixelsDrawLikeTheServer() throws {
        let c = try canvas(##"{"id":"a","area":{"row":1,"col":1,"rows":1,"cols":1},"content":{"size":[8,8],"background":"black","palette":{"a":"#00ff00"},"pixels":["a"],"shapes":[{"type":"rect","x":2,"y":2,"w":3,"h":2,"fill":"red"},{"type":"line","x1":7,"y1":0,"x2":7,"y2":7,"stroke":"#fff"},{"type":"circle","cx":"{{x.y}}","cy":1,"r":1,"fill":"blue"}]}}"##)
        let px = CanvasRaster.rasterize(c, width: 8, height: 8)
        func at(_ x: Int, _ y: Int) -> [UInt8] { Array(px[((y * 8 + x) * 4)..<((y * 8 + x) * 4 + 4)]) }
        XCTAssertEqual(at(0, 0), [0, 255, 0, 255], "pixels draw last")
        XCTAssertEqual(at(1, 0), [0x1a, 0x1a, 0x1a, 255], "background")
        XCTAssertEqual(at(2, 2), [0xeb, 0x40, 0x34, 255]); XCTAssertEqual(at(4, 3), [0xeb, 0x40, 0x34, 255])
        XCTAssertEqual(at(5, 2), [0x1a, 0x1a, 0x1a, 255], "rect covers [round(x), round(x+w))")
        XCTAssertEqual(at(7, 5), [255, 255, 255, 255])
        XCTAssertEqual(at(1, 1), [0x1a, 0x1a, 0x1a, 255], "a shape with an expression is left to the server")
    }

    func testDrawTabEncodesPaletteKeys() throws {
        var c = try canvas(##"{"id":"a","area":{"row":1,"col":1,"rows":5,"cols":8},"content":{"palette":{"a":"yellow","z":"#123456"},"pixels":["a."],"shapes":[{"type":"rect","x":0,"y":0,"w":1,"h":1,"fill":"z"}],"future":true}}"##)
        var grid = CanvasPixels.decode(c, width: 3, height: 2)
        XCTAssertEqual(grid[0][0], CanvasRGBA.parse("yellow"))
        XCTAssertNil(grid[0][1])
        grid[1][2] = CanvasRGBA.parse("#ff0000")
        try CanvasPixels.encode(grid, into: &c)
        XCTAssertEqual(c.pixels, ["a..", "..b"], "yellow keeps its key, red takes the first free one")
        XCTAssertEqual(c.palette["a"], .string("yellow"))
        XCTAssertEqual(c.palette["b"], .string("#ff0000"))
        XCTAssertEqual(c.palette["z"], .string("#123456"), "a key a shape names is kept")
        XCTAssertEqual(c.content?["future"], .bool(true))
        XCTAssertEqual(c.content?["size"], .array([.number("3"), .number("2")]), "the pad pins size")
        // Clear: no pixels, unreferenced keys dropped.
        try CanvasPixels.encode(grid.map { $0.map { _ in nil } }, into: &c)
        XCTAssertEqual(c.pixels, [])
        XCTAssertNil(c.palette["a"])
        // At most 62 colours.
        let many = [(0..<63).map { CanvasRGBA(UInt8($0), 0, 0) as CanvasRGBA? }]
        XCTAssertThrowsError(try CanvasPixels.encode(many, into: &c))
    }

    func testLayersAndHiddenCells() throws {
        let c = try canvas(##"{"id":"a","area":{"row":1,"col":1,"rows":2,"cols":2},"text":"hide","content":{"size":[4,4],"background":"red"}}"##)
        let layers = CanvasRaster.layers([c], board: pixoo)
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].x, 0); XCTAssertEqual(layers[0].y, 2)
        XCTAssertEqual(layers[0].width, 7); XCTAssertEqual(layers[0].height, 11)
        XCTAssertEqual(CanvasRaster.hiddenCells([c], rows: 10, cols: 16), [[0, 0], [0, 1], [1, 0], [1, 1]])
    }
}
