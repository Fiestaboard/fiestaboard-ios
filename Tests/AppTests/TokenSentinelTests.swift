import XCTest
import SwiftUI
import UIKit
import FiestaBoardRender
@testable import FiestaBoard

/// Re-render the generated pigments, then probe the swatch centers in sRGB.
@MainActor final class TokenSentinelTests: XCTestCase {
    func testGeneratedBoardPigmentsRerenderAtBothTierOneScales() throws {
        for device in IOSSnapshot.Device.allCases {
            let image = IOSSnapshot.image(HStack(spacing: 0) {
                ForEach(BoardColor.allCases, id: \.rawValue) { pigment in
                    let t = pigment.token
                    Color(.sRGB, red: t.red, green: t.green, blue: t.blue, opacity: t.alpha)
                }
            }.ignoresSafeArea(), device: device)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            for (index, pigment) in BoardColor.allCases.enumerated() {
                let x = Int((Double(index) + 0.5) * Double(cg.width) / 8)
                let offset = ((cg.height / 2) * cg.width + x) * 4
                let value = try XCTUnwrap(UInt32(pigment.hex.dropFirst(), radix: 16))
                for (channel, shift) in [16, 8, 0].enumerated() {
                    XCTAssertEqual(Double(pixels[offset + channel]), Double((value >> shift) & 255),
                                   accuracy: 1, "\(device.rawValue): \(pigment.rawValue)")
                }
            }
        }
    }
}
