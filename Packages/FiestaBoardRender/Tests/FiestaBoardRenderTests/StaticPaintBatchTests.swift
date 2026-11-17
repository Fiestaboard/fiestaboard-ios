#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
import CoreGraphics
import XCTest
@testable import FiestaBoardRender

@MainActor final class StaticPaintBatchTests: XCTestCase {
    func testLargeBoardMatchesIndependentPaintIncludingMonochromeAtEveryScale() throws {
        let cycle: [BoardCell] = [.character("A"), .character("B"), .character("♥"), .blank, .color(.red)]
        let cells = (0..<12).map { row in (0..<29).map { col in cycle[(row * 29 + col) % cycle.count] } }
        let layout = BoardLayout.make(rows: 12, cols: 29, cells: cells, tileHeight: 13)
        XCTAssertTrue(BoardCanvas.canBatchStatic(layout))
        for palette in [FlapPalette.black, .white, .black.monochrome(0x66cc33)] {
            for scale in [1.0, 2.0, 3.0] {
                XCTAssertEqual(try pixels(layout, palette: palette, scale: scale, batch: true),
                               try pixels(layout, palette: palette, scale: scale, batch: false),
                               "large board, scale=\(scale), palette=\(palette)")
            }
        }
    }

    func testStaticBatchMatchesIndependentPerTilePaintAtEveryScaleAndPalette() throws {
        let cycle: [BoardCell] = [.character("A"), .character("B"), .character("♥"), .blank]
            + (63...71).map { BoardTables.cell(forCode: $0, code62: .degree) }
        for palette in [FlapPalette.black, .white] {
            for scale in [1.0, 2.0, 3.0] {
                for (rows, cols, height, notes, stretch) in [(3, 4, 13.0, false, 1.0), (3, 4, 80.0, false, 1.0), (4, 17, 13.0, true, 1.0), (3, 4, 13.0, false, 1.15)] {
                    let cells = (0..<rows).map { y in (0..<cols).map { x in cycle[(y * cols + x) % cycle.count] } }
                    let layout = BoardLayout.make(rows: rows, cols: cols, cells: cells, tileHeight: height, seams: notes ? .notes : nil, stretch: stretch)
                    let expected = try pixels(layout, palette: palette, scale: scale, batch: false)
                    let actual = try pixels(layout, palette: palette, scale: scale, batch: true)
                    XCTAssertTrue(expected.contains(where: { $0 != 0 }), "The independent oracle must paint")
                    XCTAssertEqual(actual, expected, "palette=\(palette.whiteHardware), scale=\(scale), size=\(height), notes=\(notes), stretch=\(stretch)")
                }
            }
        }
    }

    func testOverlappingAndTinyLayoutsPreservePerTileCompositing() throws {
        let overlap = BoardLayout(tiles: [
            TileRect(row: 0, col: 0, x: 0, y: 0, width: 20, height: 30, radius: 2, cell: .character("A")),
            TileRect(row: 0, col: 1, x: 10, y: 8, width: 20, height: 30, radius: 2, cell: .color(.red))
        ], width: 40, height: 40, tileHeight: 30)
        XCTAssertTrue(BoardCanvas.canBatchStatic(BoardLayout.make(rows: 12, cols: 29, cells: [], tileHeight: 13)))
        let tiny = BoardLayout.make(rows: 4, cols: 4, cells: [], tileHeight: 2)
        XCTAssertFalse(BoardCanvas.canBatchStatic(overlap))
        XCTAssertFalse(BoardCanvas.canBatchStatic(tiny))
        for layout in [overlap, tiny] {
            let expected = try pixels(layout, palette: .black, scale: 3, batch: false)
            let renderer = ImageRenderer(content: BoardCanvas(layout: layout))
            renderer.scale = 3
            XCTAssertEqual(try normalized(try XCTUnwrap(renderer.cgImage)), expected)
        }
    }

    private func pixels(_ layout: BoardLayout, palette: FlapPalette, scale: Double, batch: Bool) throws -> Data {
        let content = Canvas { context, _ in
            BoardCanvas.paintNoteBezels(layout, palette: palette, in: &context)
            if batch {
                BoardCanvas.paintStatic(layout, palette: palette, in: &context)
            } else {
                // Independent oracle: the original per-tile ordering, including
                // surface/content/seam, rather than calling the optimized path.
                let font = BoardFont.glyph(size: layout.fontSize)
                var resolved: [Character: GraphicsContext.ResolvedText] = [:]
                let seam = FlapTilePainter.seam(forTileHeight: layout.tileHeight)
                for tile in layout.tiles {
                    FlapTilePainter.draw(tile: tile, cell: tile.cell, palette: palette, font: font, in: &context, resolved: &resolved)
                    FlapTilePainter.drawSeam(tile: tile, seam: seam, palette: palette, in: &context)
                }
            }
        }.frame(width: layout.width, height: layout.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return try normalized(try XCTUnwrap(renderer.cgImage))
    }

    private func normalized(_ image: CGImage) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Data(bytes)
    }
}
#endif
