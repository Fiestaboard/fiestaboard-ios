import SwiftUI
import XCTest
@testable import FiestaBoardRender

@MainActor
final class BitmapCaptureTests: XCTestCase {
    func testAFirstCapturePaintsPigmentAndHardwareIntoOwnedPixels() throws {
        let layout = BoardLayout.make(rows: 1, cols: 1, cells: [[.color(.red)]], tileHeight: 200)
        let image = try XCTUnwrap(BitmapCapture.image(BoardCanvas(layout: layout, background: .black),
            size: CGSize(width: layout.width, height: layout.height)))
        XCTAssertEqual(image.width, Int(layout.width.rounded(.up)))
        XCTAssertEqual(image.height, Int(layout.height.rounded(.up)))
        let pigment = try sample(image, x: Int(layout.width / 2), y: Int(layout.height * 0.4))
        XCTAssertEqual(Int(pigment[0]), 235, accuracy: 12)
        XCTAssertEqual(Int(pigment[1]), 64, accuracy: 12)
        XCTAssertEqual(Int(pigment[2]), 52, accuracy: 12)
        XCTAssertGreaterThan(pigment[3], 240)
        let edge = try sample(image, x: 3, y: Int(layout.height * 0.4))
        XCTAssertEqual(Int(edge[0]), 13, accuracy: 3)
    }

    func testBCapturesDoNotShareTheirBackingAndPreserveTransparency() throws {
        let first = try XCTUnwrap(BitmapCapture.image(Color.red, size: CGSize(width: 17, height: 23)))
        let second = try XCTUnwrap(BitmapCapture.image(Color.clear, size: CGSize(width: 17, height: 23)))
        XCTAssertEqual(first.width, 17)
        XCTAssertEqual(first.height, 23)
        XCTAssertGreaterThan(try sample(first, x: 8, y: 11)[0], 240)
        XCTAssertEqual(try sample(second, x: 8, y: 11)[3], 0)
        XCTAssertGreaterThan(try sample(first, x: 8, y: 11)[3], 240)
    }

    private func sample(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - y - 1), width: image.width, height: image.height))
        return bytes
    }
}
