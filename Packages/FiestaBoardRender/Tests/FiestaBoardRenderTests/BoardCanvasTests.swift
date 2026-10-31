// Ported from fiestaboard-appletv@a3df9c9 Tests/BoardCanvasTests.swift (:34, :231, :246). MIT.
#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardRender

@MainActor
final class BoardCanvasTests: XCTestCase {

    private func layout(cells: [[BoardCell]], tileHeight: Double = 100) -> BoardLayout {
        BoardLayout.make(rows: cells.count, cols: cells.first?.count ?? 0, cells: cells, tileHeight: tileHeight)
    }

    func testRendersWithoutCrashing() {
        let grid = [[BoardCell.character("A"), .color(.red)], [.blank, .character("9")]]
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), background: .black))
        RenderHarness.render(BoardCanvas(layout: layout(cells: grid), palette: .black, animated: true, loading: true))
    }

    func testFlipTransitionWalksTheFiestaUIDrumAtEightyMillisecondsPerStep() {
        XCTAssertEqual(BoardFlipTransition.stepDuration, 0.08)
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("A")], to: [.character("D")],
                                       code62: .degree, startedAt: started)
        XCTAssertEqual(flip.duration, 0.24, accuracy: 0.0001)

        let falling = flip.sample(index: 0, at: started.addingTimeInterval(0.02))
        XCTAssertEqual(falling.previous, .character("A"))
        XCTAssertEqual(falling.next, .character("B"))
        XCTAssertEqual(falling.progress, 0.25, accuracy: 0.0001)
        XCTAssertTrue(falling.isAnimating)

        let rising = flip.sample(index: 0, at: started.addingTimeInterval(0.06))
        XCTAssertEqual(rising.cell, .character("B"))
        XCTAssertEqual(rising.progress, 0.75, accuracy: 0.0001)

        let secondStep = flip.sample(index: 0, at: started.addingTimeInterval(0.10))
        XCTAssertEqual(secondStep.previous, .character("B"))
        XCTAssertEqual(secondStep.next, .character("C"))

        let settled = flip.sample(index: 0, at: started.addingTimeInterval(0.24))
        XCTAssertEqual(settled.cell, .character("D"))
        XCTAssertFalse(settled.isAnimating)
    }

    func testNoteDrumShowsHeartAtCodeSixtyTwo() {
        let started = Date(timeIntervalSince1970: 0)
        let flip = BoardFlipTransition(from: [.character("?")], to: [.character("♥")], code62: .heart, startedAt: started)
        XCTAssertEqual(flip.sample(index: 0, at: started.addingTimeInterval(0.02)).next, .blank, "61 is undefined")
        XCTAssertEqual(flip.sample(index: 0, at: started.addingTimeInterval(0.10)).next, .character("♥"))
    }

    func testTheFlapStepIsTheBoardsSpeedSetting() {
        let started = Date(timeIntervalSince1970: 0)
        let relaxed = BoardFlipTransition(from: [.character("A")], to: [.character("D")], code62: .degree,
                                          startedAt: started, step: 0.13)
        XCTAssertEqual(relaxed.duration, 0.39, accuracy: 0.0001)
    }

    /// A colour tile paints its pigment as an inset chip on the #0d0d0d face.
    /// Sample above the hinge, whose shadow intentionally darkens the centre.
    func testAColorTilePaintsItsPigment() throws {
        let board = layout(cells: [[BoardCell.color(.red)]], tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black).frame(width: board.width, height: board.height)
        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let centre = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height * 0.4)))
        XCTAssertEqual(Int(centre.r), 0xeb, accuracy: 12, "red channel")
        XCTAssertEqual(Int(centre.g), 0x40, accuracy: 12, "green channel")
        XCTAssertEqual(Int(centre.b), 0x34, accuracy: 12, "blue channel")
        // The inset: the tile's edge stays the hardware surface around the chip.
        let edge = try XCTUnwrap(image.pixel(x: 3, y: Int(board.height * 0.4)))
        XCTAssertEqual(Int(edge.r), 0x0d, accuracy: 3, "surface #0d0d0d around the chip")
    }

    func testWhiteHardwareUsesLightFlapsAndInvertsWhiteAndBlackCodes() throws {
        for (cell, shouldBeLight) in [(BoardCell.blank, true), (.color(.white), false), (.color(.black), true)] {
            let board = layout(cells: [[cell]], tileHeight: 200)
            let image = RenderHarness.image(BoardCanvas(layout: board, background: .white),
                                            size: CGSize(width: board.width, height: board.height))
            let pixel = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height * 0.4)))
            if shouldBeLight { XCTAssertGreaterThan(Int(pixel.r), 0xc0, "\(cell)") }
            else { XCTAssertLessThan(Int(pixel.r), 0x60, "\(cell)") }
        }
        XCTAssertEqual(FlapPalette.white.pigment(.white), 0x1a1a1a)
        XCTAssertEqual(FlapPalette.white.pigment(.black), 0xffffff)
        XCTAssertEqual(FlapPalette.white.surface, 0xfafafa)
        XCTAssertEqual(FlapPalette.white.ink, 0x0d0d0d)
    }

    func testBlackHardwareFaceInkAndBezelTokens() {
        let palette = FlapPalette.black
        XCTAssertEqual(palette.surface, 0x0d0d0d)
        XCTAssertEqual(palette.ink, 0xf0f0e8)
        XCTAssertEqual(palette.bezel, 0x050505)
        XCTAssertEqual(palette.bezelBorder, 0x1a1a1a)
        XCTAssertEqual(palette.ink(for: "♥"), 0xeb4034, "the heart is always red")
        XCTAssertEqual(palette.ink(for: "°"), 0xf0f0e8)
    }

    func testTheGutterShowsTheBoardBehind() throws {
        let board = layout(cells: [[BoardCell.color(.white), BoardCell.color(.white)]], tileHeight: 200)
        let view = BoardCanvas(layout: board, background: .black).background(Color.black)
            .frame(width: board.width, height: board.height)
        let image = RenderHarness.image(view, size: CGSize(width: board.width, height: board.height))
        let gutterX = Int(board.tiles[0].width + board.tileHeight * BoardGeometry.tileGutterRatio / 2)
        let gutter = try XCTUnwrap(image.pixel(x: gutterX, y: Int(board.height * 0.4)))
        XCTAssertLessThan(Int(gutter.r), 0x10, "the gutter must not be a lit flap")
        let tile = try XCTUnwrap(image.pixel(x: Int(board.tiles[0].width / 2), y: Int(board.height * 0.4)))
        XCTAssertGreaterThan(Int(tile.r), 0xc0, "a white chip must be lit")
    }

    func testSeamCrossesEveryTile() throws {
        let board = layout(cells: [[BoardCell.blank]], tileHeight: 200)
        let image = RenderHarness.image(BoardCanvas(layout: board, palette: .white),
                                        size: CGSize(width: board.width, height: board.height))
        let face = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int(board.height * 0.3)))
        let seam = try XCTUnwrap(image.pixel(x: Int(board.width / 2), y: Int((board.height / 2).rounded())))
        XCTAssertLessThan(Int(seam.r), Int(face.r), "the seam is darker than the face")
    }
}
#endif
