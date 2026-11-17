#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import XCTest
@testable import FiestaBoardRender

@MainActor
final class BoardViewportRenderTests: XCTestCase {
    #if canImport(UIKit)
    func testBothTechnologiesAndWholeNotesRenderAtPhoneAndTabletWidths() throws {
        let models = [DisplayModel.flap(rows: 6, cols: 22),
            DisplayModel(summary: BoardSummaryFields(deviceType: "note_array", rows: 3, cols: 45), stored: nil),
            LedRasterizerTests.model(width: 64, height: 32)]
        for model in models {
            for width in [370.0, 1116.0] {
                let frame = BoardFrame(rows: model.rows, cols: model.cols, message: "HELLO")
                let image = RenderHarness.image(BoardViewport(frame: frame, model: model), size: CGSize(width: width, height: 300))
                XCTAssertEqual(image.cgImage?.width, Int(width))
                XCTAssertEqual(image.cgImage?.height, 300)
            }
        }
    }

    func testExplicitPartialNoteModelRetainsItsLastRowAndColumns() throws {
        // The wire decoder intentionally normalizes Note arrays. Construct the
        // lower-level render model explicitly so this is a real partial-grid test.
        var partial = DisplayModel.flap(rows: 6, cols: 45, deviceType: "note_array")
        partial.rows = 4
        partial.cols = 34
        let geometry = BoardViewportGeometry(rows: partial.rows, cols: partial.cols, viewportWidth: 200, notes: true)
        let bounds = geometry.bounds(page: 5)
        XCTAssertEqual(bounds.rows, 3..<4)
        XCTAssertEqual(bounds.cols, 30..<34)
        let layout = BoardLayout.make(rows: bounds.rows.count, cols: bounds.cols.count,
            cells: [[.character("L"), .character("A"), .character("S"), .character("T")]], tileHeight: 13, noteArray: true)
        XCTAssertEqual(layout.tiles.count, 4)
        let image = RenderHarness.image(BoardCanvas(layout: layout), size: CGSize(width: 200, height: 100))
        XCTAssertNotNil(image.cgImage)
    }

    #endif

    /// Draw cost is a frame budget check, not a physical display refresh measurement.
    /// The CI result remains authoritative; I26 measures actual hardware pacing.
    func testSixtyFPSDrawBudgetOnFlagship() throws { try drawBudget(rows: 6, cols: 22, fps: 60) }
    func testFortyFiveFPSDrawBudgetOnLargeBoard() throws { try drawBudget(rows: 12, cols: 29, fps: 45) }

    private func drawBudget(rows: Int, cols: Int, fps: Double) throws {
        var samples: [Double] = []
        var index = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 30
        measure(metrics: [XCTClockMetric()], options: options) {
            let layout = BoardLayout.make(rows: rows, cols: cols,
                cells: Array(repeating: Array(repeating: .character(index.isMultiple(of: 2) ? "A" : "B"), count: cols), count: rows), tileHeight: 13)
            let start = CACurrentMediaTime()
            let renderer = ImageRenderer(content: BoardCanvas(layout: layout))
            renderer.scale = 3
            XCTAssertNotNil(renderer.cgImage)
            if index > 0 { samples.append(CACurrentMediaTime() - start) }
            index += 1
        }
        let p95 = samples.sorted()[Int(Double(samples.count - 1) * 0.95)]
        print("I4 draw p95 \(rows)x\(cols): \(p95)s, budget \(1 / fps)s")
        XCTAssertLessThanOrEqual(p95, 1 / fps)
    }
}
#endif
