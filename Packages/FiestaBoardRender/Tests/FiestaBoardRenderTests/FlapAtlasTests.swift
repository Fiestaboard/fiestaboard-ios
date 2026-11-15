// Ported from fiestaboard-appletv@a3df9c9 Tests/FlapAtlasTests.swift. MIT.
#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardRender

@MainActor
final class FlapAtlasTests: XCTestCase {
    func testRetinaAtlasFitsTextureDimensionsAndKeepsLastDrumFaces() throws {
        for height in [80.0, 120.0] {
            let atlas = try XCTUnwrap(FlapAtlas(tileHeight: height, palette: .black, code62: .degree, scale: 2))
            let face = try XCTUnwrap(atlas.image(code: 68, phase: nil))
            XCTAssertLessThanOrEqual(atlas.maximumTextureDimension, 4096)
            let pixel = try XCTUnwrap(UIImage(cgImage: face).pixel(x: face.width / 2, y: Int(Double(face.height) * 0.35)))
            XCTAssertGreaterThan(pixel.r, 120); XCTAssertGreaterThan(pixel.b, 120)
            XCTAssertLessThanOrEqual(atlas.byteCount, 64 * 1024 * 1024)
        }
    }

    func testPreparedFramesKeepPigmentAndMechanicalHalfFaces() throws {
        let atlas = try XCTUnwrap(FlapAtlas(tileHeight: 80, palette: .black, code62: .degree, scale: 1))
        let still = UIImage(cgImage: try XCTUnwrap(atlas.image(code: 63, phase: nil)))
        let face = try XCTUnwrap(still.pixel(x: Int(still.size.width / 2), y: 30))
        XCTAssertEqual(Int(face.r), 235, accuracy: 2)
        XCTAssertEqual(Int(face.g), 64, accuracy: 2)
        let falling = UIImage(cgImage: try XCTUnwrap(atlas.image(code: 63, phase: 6)))
        let top = try XCTUnwrap(falling.pixel(x: Int(falling.size.width / 2), y: 20))
        let bottom = try XCTUnwrap(falling.pixel(x: Int(falling.size.width / 2), y: 62))
        XCTAssertGreaterThan(top.g, 140, "orange revealed above")
        XCTAssertGreaterThan(bottom.r, 160, "red remains below"); XCTAssertLessThan(bottom.g, 110)
    }

    func testDrumRetainsSecondBlackPositionBeforeWrappingToBlank() {
        let start = Date(timeIntervalSince1970: 0)
        let transition = BoardFlipTransition(from: [.color(.black)], to: [.character("A")], code62: .degree, startedAt: start)
        XCTAssertEqual(transition.sample(index: 0, at: start.addingTimeInterval(0.10)).drumCode, 71)
    }
}

/// Adapted from tvOS `PanelPreviewThumbnailTests`: the static thumbnail path
/// takes a `BoardFrame` + `DisplayModel` instead of a panel.
@MainActor
final class PanelPreviewThumbnailTests: XCTestCase {
    func testThumbnailPaintsBothDisplayKindsAtTheRequestedResolution() throws {
        for matrix in [false, true] {
            let model = matrix
                ? DisplayModel(summary: BoardSummaryFields(deviceType: "panel", rows: 10, cols: 16, deviceModel: "divoom_pixoo64"), stored: nil)
                : DisplayModel.flap(rows: 3, cols: 6)
            let frame = BoardFrame(rows: model.rows, cols: model.cols,
                                   codes: Array(repeating: Array(repeating: 63, count: model.cols), count: model.rows))
            let renderer = ImageRenderer(content: BoardThumbnail(frame: frame, model: model).frame(width: 400, height: 220))
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(cgImage.width, 800); XCTAssertEqual(cgImage.height, 440)
            let image = UIImage(cgImage: cgImage)
            var red = 0
            for y in stride(from: 0, to: cgImage.height, by: 5) {
                for x in stride(from: 0, to: cgImage.width, by: 5) {
                    if let p = image.pixel(x: x, y: y), p.r > 150, p.g < 120, p.b < 120 { red += 1 }
                }
            }
            XCTAssertGreaterThan(red, 100, "The \(matrix ? "matrix" : "flap") thumbnail must contain the board")
        }
    }

    func testThumbnailsAreStatic() {
        // BoardThumbnail never animates or spins (FiestaUI StaticBoardDisplay).
        let view = BoardThumbnail(frame: .empty(rows: 1, cols: 1), model: .flap(rows: 1, cols: 1))
        let mirror = Mirror(reflecting: view.body)
        XCTAssertNotNil(mirror)
        RenderHarness.render(view)
    }
}
#endif

// Packing is pure geometry, so these controls also run on the macOS host.
#if !canImport(UIKit)
import XCTest
@testable import FiestaBoardRender
#endif

final class FlapAtlasPackingTests: XCTestCase {
    func testRetinaPackingBoundsEachRenderAndPreservesEveryCodeAndPhase() throws {
        for height in [13.0, 80, 120] {
            let packing = try XCTUnwrap(FlapAtlas.Packing(tileHeight: height, scale: 2))
            XCTAssertGreaterThanOrEqual(packing.renderScale, 1)
            XCTAssertLessThanOrEqual(packing.renderScale, 2)
            XCTAssertGreaterThan(packing.renderScale, 1, "Retina height=\(height)")
            XCTAssertLessThanOrEqual(packing.sheetWidth, 2048)
            XCTAssertLessThanOrEqual(packing.sheetHeight, 2048)
            XCTAssertLessThanOrEqual(packing.codesPerSheet, 12)
            XCTAssertEqual(packing.sheetCount, 78)
            XCTAssertLessThanOrEqual(packing.byteCount, 60 * 1024 * 1024)
            XCTAssertEqual(packing.byteCount, packing.sheetCount * packing.sheetWidth * packing.sheetHeight * 4)
            var positions: Set<Int> = []
            for phase in 0...FlapAtlas.phases {
                for code in 0..<72 {
                    let position = packing.position(code: code, phase: phase)
                    XCTAssertEqual(position.x % packing.cellWidth, 0)
                    XCTAssertGreaterThanOrEqual(position.x, 0)
                    XCTAssertLessThanOrEqual(position.x + packing.cellWidth, packing.sheetWidth)
                    XCTAssertTrue(positions.insert(position.sheet * 12 + position.x / packing.cellWidth).inserted)
                }
            }
            XCTAssertEqual(positions.count, 72 * 13)
        }
    }

    func testPackingRejectsInvalidInputWithoutNanConversions() {
        for height in [0.0, -1, 121, .nan, .infinity] {
            XCTAssertNil(FlapAtlas.Packing(tileHeight: height, scale: 2))
        }
        XCTAssertNil(FlapAtlas.Packing(tileHeight: 80, scale: .nan))
        XCTAssertNil(FlapAtlas.Packing(tileHeight: 80, scale: .infinity))
    }
}
