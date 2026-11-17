#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
import Darwin
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
        // CPU is diagnostic: the unchanged draw-only wall p95 remains the gate.
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
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
        print("I4 draw wall samples \(rows)x\(cols): \(samples)")
        print("I4 draw p95 \(rows)x\(cols): \(p95)s, budget \(1 / fps)s")
        XCTAssertLessThanOrEqual(p95, 1 / fps)
    }
}

/// Separate diagnostic workload: the original draw-budget test above is unchanged.
/// Whole-process CPU includes every thread. Stage-only canvases isolate work but
/// do not reproduce the full SwiftUI lifecycle and their times are not additive.
/// Keep the Z prefix so these extra draws follow the existing renderer assertions.
@MainActor
final class ZBoardViewportDrawDiagnosticsTests: XCTestCase {
    func testReportPairedWallAndProcessCPUForLargeBoardStages() throws {
        for stage in Stage.allCases {
            var pairs: [[String: Double]] = []
            for index in 0..<12 {
                let layout = BoardLayout.make(rows: 12, cols: 29,
                    cells: Array(repeating: Array(repeating: .character(index.isMultiple(of: 2) ? "A" : "B"), count: 29), count: 12),
                    tileHeight: 13)
                let cpuStart = try processCPUSeconds()
                let wallStart = CACurrentMediaTime()
                let image: CGImage?
                if stage == .complete {
                    let renderer = ImageRenderer(content: BoardCanvas(layout: layout))
                    renderer.scale = 3
                    image = renderer.cgImage
                } else {
                    let renderer = ImageRenderer(content: StageCanvas(layout: layout, stage: stage))
                    renderer.scale = 3
                    image = renderer.cgImage
                }
                let wall = CACurrentMediaTime() - wallStart
                let cpu = try processCPUSeconds() - cpuStart
                XCTAssertNotNil(image)
                pairs.append(["iteration": Double(index), "wall_ms": wall * 1000, "process_cpu_ms": cpu * 1000])
            }
            let data = try JSONSerialization.data(withJSONObject: pairs, options: [.sortedKeys])
            print("I4 draw diagnostic \(stage.rawValue) paired samples: \(String(decoding: data, as: UTF8.self))")
        }
    }

    private func processCPUSeconds() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }

    private enum Stage: String, CaseIterable {
        case complete, surfaces, content, seams
    }

    private struct StageCanvas: View {
        let layout: BoardLayout
        let stage: Stage

        var body: some View {
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                let palette = FlapPalette.black
                switch stage {
                case .complete:
                    break // The complete diagnostic uses production BoardCanvas above.
                case .surfaces:
                    for tile in layout.tiles {
                        context.fill(Path(roundedRect: CGRect(x: tile.x, y: tile.y,
                            width: tile.width, height: tile.height), cornerRadius: tile.radius),
                            with: .color(Color(rgb: palette.surface)))
                    }
                case .content:
                    let font = BoardFont.glyph(size: layout.fontSize)
                    var resolved: [Character: GraphicsContext.ResolvedText] = [:]
                    for tile in layout.tiles {
                        FlapTilePainter.drawContent(tile: tile, cell: tile.cell, palette: palette,
                            font: font, in: &context, resolved: &resolved)
                    }
                case .seams:
                    let seam = FlapTilePainter.seam(forTileHeight: layout.tileHeight)
                    var gaps = Path(), highlights = Path()
                    for tile in layout.tiles {
                        let top = (tile.y + tile.height / 2).rounded()
                        gaps.addRect(CGRect(x: tile.x, y: top, width: tile.width, height: seam.thickness))
                        highlights.addRect(CGRect(x: tile.x, y: top + seam.thickness,
                            width: tile.width, height: seam.thickness))
                    }
                    context.fill(gaps, with: .color(Color.black.opacity(0.55 * seam.ink)))
                    context.fill(highlights, with: .color(Color.white.opacity(0.10 * seam.ink)))
                }
            }
            .frame(width: layout.width, height: layout.height)
        }
    }
}
#endif
