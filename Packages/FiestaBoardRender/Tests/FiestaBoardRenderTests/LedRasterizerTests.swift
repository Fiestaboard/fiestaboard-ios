import Foundation
import XCTest
@testable import FiestaBoardRender

final class LedRasterizerTests: XCTestCase {

    static func model(width: Int, height: Int, font: String = "3x5", monochrome: String? = nil,
                      tileGap: String = "gap", blockPadding: Int = 0) -> DisplayModel {
        var spec: [String: Any] = ["technology": "led_matrix", "font": font, "geometry": ["width": width, "height": height]]
        if let monochrome { spec["color"] = ["kind": "monochrome", "color": monochrome] }
        return DisplayModel(summary: BoardSummaryFields(deviceType: nil, rows: 0, cols: 0),
                            stored: ["device_model_spec": spec,
                                     "led_layout": ["tile_gap": tileGap, "block_padding": blockPadding]])
    }

    static func rgba(_ pixels: [(UInt8, UInt8, UInt8, UInt8)]) -> Data {
        Data(pixels.flatMap { [$0.0, $0.1, $0.2, $0.3] })
    }

    func testLayersCompositeWithAlpha() {
        let model = Self.model(width: 4, height: 4)
        // 2×2 layer hanging off the top-left corner: only its bottom-right pixel is on the matrix.
        let clipped = PixelLayer(x: -1, y: -1, w: 2, h: 2, rgba: Self.rgba([
            (255, 0, 0, 255), (255, 0, 0, 255), (255, 0, 0, 255), (0, 255, 0, 128),
        ]))
        // 2×1 layer at the bottom-right edge: first pixel transparent, second past the edge.
        let edge = PixelLayer(x: 3, y: 3, w: 2, h: 1, rgba: Self.rgba([(0, 0, 255, 0), (0, 0, 255, 255)]))
        // A later layer overwrites an earlier one; no blending.
        let over = PixelLayer(x: 1, y: 1, w: 1, h: 1, rgba: Self.rgba([(10, 20, 30, 1)]))
        let raster = LedRasterizer.raster(BoardFrame(rows: 0, cols: 0, layers: [clipped, edge, over]), model: model)
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 0x00ff00, "alpha 128 overwrites with its RGB, unblended")
        XCTAssertNil(raster.pixel(x: 3, y: 3), "alpha 0 leaves what is under")
        XCTAssertEqual(raster.pixel(x: 1, y: 1), 0x0a141e, "alpha 1 still overwrites")
        let litCount = raster.lit.filter { $0 }.count
        XCTAssertEqual(litCount, 2, "clipped pixels never wrap into the matrix")
    }

    func testLayerWithShortRgbaIsTransparentWhereBytesAreMissing() {
        let layer = PixelLayer(x: 0, y: 0, w: 2, h: 1, rgba: Self.rgba([(255, 255, 255, 255)]))
        let raster = LedRasterizer.raster(BoardFrame(rows: 0, cols: 0, layers: [layer]), model: Self.model(width: 4, height: 2))
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 0xffffff)
        XCTAssertNil(raster.pixel(x: 1, y: 0))
    }

    func testMonochromeLayerThresholdsByLuma() {
        let model = Self.model(width: 3, height: 1, monochrome: "#ffb000")
        // Bright → panel colour; dark (alpha > 0) → unlit, overwriting what is under; alpha 0 → untouched.
        let base = PixelLayer(x: 0, y: 0, w: 3, h: 1, rgba: Self.rgba([(255, 255, 255, 255), (255, 255, 255, 255), (255, 255, 255, 255)]))
        let top = PixelLayer(x: 0, y: 0, w: 3, h: 1, rgba: Self.rgba([(200, 200, 200, 255), (60, 60, 60, 255), (0, 0, 0, 0)]))
        let raster = LedRasterizer.raster(BoardFrame(rows: 0, cols: 0, layers: [base, top]), model: model)
        XCTAssertEqual(raster.pixel(x: 0, y: 0), 0xffb000)
        XCTAssertNil(raster.pixel(x: 1, y: 0))
        XCTAssertEqual(raster.pixel(x: 2, y: 0), 0xffb000)
        // The threshold is exactly 299r + 587g + 114b >= 127500.
        XCTAssertTrue(299 * 128 + 587 * 128 + 114 * 128 >= 127_500)
        XCTAssertFalse(299 * 127 + 587 * 127 + 114 * 127 >= 127_500)
    }

    func testMonochromeRecolorsEverything() {
        let model = Self.model(width: 32, height: 8, monochrome: "#ff3b1f")
        let frame = BoardFrame(rows: 0, cols: 0, message: "{red:HI}{66}{icon:sun}♥A")
        let raster = LedRasterizer.raster(frame, model: model)
        let colours = Set((0..<raster.height).flatMap { y in (0..<raster.width).compactMap { raster.pixel(x: $0, y: y) } })
        XCTAssertEqual(colours, [0xff3b1f], "spans, tiles, icons and the heart all light in the panel colour")
        let rgb = LedRasterizer.raster(frame, model: Self.model(width: 32, height: 8))
        let rgbColours = Set((0..<rgb.height).flatMap { y in (0..<rgb.width).compactMap { rgb.pixel(x: $0, y: y) } })
        XCTAssertTrue(rgbColours.isSuperset(of: [0xeb4034, 0x7ed321, 0xf8e71c, 0xffffff]), "RGB keeps each colour")
    }

    func testMonochromeBlockIsInverseVideo() {
        let model = Self.model(width: 3, height: 5, monochrome: "#ffb000")
        let raster = LedRasterizer.raster(BoardFrame(rows: 0, cols: 0, message: "{black/white:I}"), model: model)
        // 3x5 "I" is ###/.#./.#./.#./###: the glyph pixels are unlit, the rest of the box lit.
        XCTAssertNil(raster.pixel(x: 0, y: 0))
        XCTAssertEqual(raster.pixel(x: 0, y: 1), 0xffb000)
        XCTAssertNil(raster.pixel(x: 1, y: 2))
    }

    func testPrecedenceCellsThenCodesThenMessage() {
        let model = Self.model(width: 3, height: 5)
        let red = BoardFrame(rows: 1, cols: 1, codes: [[63]], cells: [[.color(66)]], message: "{67}")
        XCTAssertEqual(LedRasterizer.raster(red, model: model).pixel(x: 1, y: 1), 0x7ed321, "cells win")
        let codes = BoardFrame(rows: 1, cols: 1, codes: [[63]], message: "{67}")
        XCTAssertEqual(LedRasterizer.raster(codes, model: model).pixel(x: 1, y: 1), 0xeb4034, "codes beat message")
        let message = BoardFrame(rows: 1, cols: 1, message: "{67}")
        XCTAssertEqual(LedRasterizer.raster(message, model: model).pixel(x: 1, y: 1), 0x4a90d9)
    }

    func testCodesDrawCharactersAndCode62Heart() {
        let model = Self.model(width: 7, height: 5)
        let raster = LedRasterizer.raster(BoardFrame(rows: 1, cols: 2, codes: [[1, 62]]), model: model)
        XCTAssertEqual(raster.pixel(x: 1, y: 0), 0xffffff, "A")
        let heart = (0..<5).flatMap { y in (4..<7).compactMap { raster.pixel(x: $0, y: y) } }
        XCTAssertFalse(heart.isEmpty)
        XCTAssertTrue(heart.allSatisfy { $0 == 0xeb4034 }, "the heart is red")
    }

    func testMessageKeepsCaseOnLed() {
        let model = Self.model(width: 3, height: 5)
        let lower = LedRasterizer.raster(BoardFrame(rows: 1, cols: 1, message: "a"), model: model)
        let upper = LedRasterizer.raster(BoardFrame(rows: 1, cols: 1, message: "A"), model: model)
        XCTAssertNotEqual(lower, upper)
    }

    func testBlackTilesAndSpansAreUnlit() {
        let model = Self.model(width: 11, height: 5)
        let raster = LedRasterizer.raster(BoardFrame(rows: 1, cols: 3, message: "{70}{black}{black:A}"), model: model)
        XCTAssertFalse(raster.lit.contains(true))
    }

    func testTileGapFillLightsTheGutterBetweenTwoTiles() {
        let gap = LedRasterizer.raster(BoardFrame(rows: 1, cols: 2, message: "{63}{63}"), model: Self.model(width: 7, height: 5))
        XCTAssertNil(gap.pixel(x: 3, y: 2))
        let fill = LedRasterizer.raster(BoardFrame(rows: 1, cols: 2, message: "{63}{63}"),
                                        model: Self.model(width: 7, height: 5, tileGap: "fill"))
        XCTAssertEqual(fill.pixel(x: 3, y: 2), 0xeb4034)
    }

    func testParseLineMarkup() {
        let tokens = LedMarkup.parseLine("{red:a{63}}{/red}{icon:storm}{icon:heart}❤{foo:x}", preserveCase: false)
        XCTAssertEqual(tokens.first, LedToken(isTile: false, value: "A", code: "", color: "red"))
        XCTAssertEqual(tokens[1].isTile, true)
        XCTAssertEqual(tokens[1].code, "63")
        XCTAssertNil(tokens[1].color, "a tile inside a span is a plain tile (parseLine)")
        XCTAssertEqual(tokens[2].icon, "bolt")
        XCTAssertEqual(tokens[2].code, "64", "an icon token is its tile fallback")
        XCTAssertEqual(tokens[3].value, "♥")
        XCTAssertEqual(tokens[4].value, "♥", "❤ normalises to ♥")
        XCTAssertEqual(tokens.dropFirst(5).map(\.value).joined(), "{FOO:X}", "an unknown marker is literal")
    }

    func testDotsViewBuilds() {
        let raster = LedRasterizer.raster(BoardFrame(rows: 1, cols: 1, message: "A"), model: Self.model(width: 3, height: 5))
        _ = MatrixDotsView(raster: raster, appearance: .round).body
    }
}
