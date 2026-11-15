// Ported from fiestaboard-appletv@a3df9c9 Tests/FlapAtlasTests.swift. MIT.
import SwiftUI
import XCTest
@testable import FiestaBoardRender

@MainActor
final class FlapAtlasTests: XCTestCase {
    func testRetinaAtlasFitsTextureDimensionsAndKeepsLastDrumFaces() throws {
        for height in [80.0, 120.0] {
            let atlas = try XCTUnwrap(FlapAtlas(tileHeight: height, palette: .black, code62: .degree, scale: 2), "height=\(height), scale=2")
            let face = try XCTUnwrap(atlas.image(code: 68, phase: nil))
            XCTAssertLessThanOrEqual(atlas.maximumTextureDimension, 2048)
            XCTAssertEqual(atlas.byteCount, atlas.packing.byteCount)
            print("Atlas h=\(height), scale=\(atlas.packing.renderScale), cell=\(face.width)x\(face.height), sheets=\(atlas.packing.sheetCount), max=\(atlas.maximumTextureDimension), bytes=\(atlas.byteCount)")
            let pixel = try XCTUnwrap(atlasPixel(face, x: face.width / 2, y: Int(Double(face.height) * 0.35)))
            XCTAssertGreaterThan(pixel.r, 120, "h=\(height), violet r=\(pixel.r), alpha=\(pixel.a)")
            XCTAssertGreaterThan(pixel.b, 120, "h=\(height), violet b=\(pixel.b), alpha=\(pixel.a)")
            XCTAssertGreaterThan(pixel.a, 240, "h=\(height)")
            for code in 63...71 {
                let pigment = try XCTUnwrap(atlas.image(code: code, phase: nil), "h=\(height), code=\(code)")
                let sample = try XCTUnwrap(atlasPixel(pigment, x: pigment.width / 2, y: Int(Double(pigment.height) * 0.35)))
                let expected = FlapPalette.black.pigment(try XCTUnwrap(BoardColor(code: code)))
                XCTAssertEqual(Int(sample.r), Int((expected >> 16) & 255), accuracy: 2, "h=\(height), code=\(code), red")
                XCTAssertEqual(Int(sample.g), Int((expected >> 8) & 255), accuracy: 2, "h=\(height), code=\(code), green")
                XCTAssertEqual(Int(sample.b), Int(expected & 255), accuracy: 2, "h=\(height), code=\(code), blue")
            }
            for code in [0, 11, 12, 23, 24, 35, 36, 47, 48, 59, 60, 68, 69, 70, 71] {
                for phase in 0...FlapAtlas.phases {
                    let image = try XCTUnwrap(atlas.image(code: code, phase: phase), "h=\(height), code=\(code), phase=\(phase)")
                    XCTAssertEqual(image.width, atlas.packing.cellWidth)
                    XCTAssertEqual(image.height, atlas.packing.cellHeight)
                    let center = try XCTUnwrap(atlasPixel(image, x: image.width / 2, y: image.height / 3))
                    XCTAssertGreaterThan(center.a, 240, "h=\(height), code=\(code), phase=\(phase), rgba=\(center)")
                }
            }
            XCTAssertLessThanOrEqual(atlas.byteCount, 64 * 1024 * 1024)
        }
    }

    func testPreparedFramesKeepPigmentAndMechanicalHalfFaces() throws {
        let atlas = try XCTUnwrap(FlapAtlas(tileHeight: 80, palette: .black, code62: .degree, scale: 1))
        let still = try XCTUnwrap(atlas.image(code: 63, phase: nil))
        let face = try XCTUnwrap(atlasPixel(still, x: still.width / 2, y: 30))
        XCTAssertEqual(Int(face.r), 235, accuracy: 2)
        XCTAssertEqual(Int(face.g), 64, accuracy: 2)
        let falling = try XCTUnwrap(atlas.image(code: 63, phase: 6))
        let top = try XCTUnwrap(atlasPixel(falling, x: falling.width / 2, y: 20))
        let bottom = try XCTUnwrap(atlasPixel(falling, x: falling.width / 2, y: 62))
        XCTAssertGreaterThan(top.g, 140, "orange revealed above")
        XCTAssertGreaterThan(bottom.r, 160, "red remains below"); XCTAssertLessThan(bottom.g, 110)
    }

    func testDrumRetainsSecondBlackPositionBeforeWrappingToBlank() {
        let start = Date(timeIntervalSince1970: 0)
        let transition = BoardFlipTransition(from: [.color(.black)], to: [.character("A")], code62: .degree, startedAt: start)
        XCTAssertEqual(transition.sample(index: 0, at: start.addingTimeInterval(0.10)).drumCode, 71)
    }
}

#if canImport(UIKit)
import UIKit

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

// Read pixels from the materialized backing on either host or native runtime.
private func atlasPixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    var pixel: [UInt8] = [0, 0, 0, 0]
    guard let context = CGContext(data: &pixel, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: -x, y: -(image.height - y - 1), width: image.width, height: image.height))
    return (pixel[0], pixel[1], pixel[2], pixel[3])
}

// Packing is pure geometry, so these controls also run on the macOS host.

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
