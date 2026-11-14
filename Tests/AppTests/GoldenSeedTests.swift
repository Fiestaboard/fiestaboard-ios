import XCTest
import UIKit
import FiestaBoardDocuments
@testable import FiestaBoard

/// I0b regression seed only. Screen geometry and Figma parity belong to I2.
@MainActor final class GoldenSeedTests: XCTestCase {
    func testTemplateChipGolden() throws {
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 27)
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light), UITraitCollection(displayScale: 2)])
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        var rendered: UIImage?
        traits.performAsCurrent {
            rendered = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 48), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 240, height: 48))
                let fragments = TemplateSyntax.fragments("{{red}} {{weather.temperature|pad:3}}")
                var x: CGFloat = 8
                for fragment in fragments where fragment.kind != .text {
                    let chip = TemplateAttachment(fragment: fragment, font: .monospacedSystemFont(ofSize: 17, weight: .regular), traits: traits)
                    chip.image?.draw(at: CGPoint(x: x, y: 12))
                    x += chip.bounds.width + 8
                }
            }
        }
        let image = try XCTUnwrap(rendered)
        let attachment = XCTAttachment(image: image)
        attachment.name = "template-chip-iOS27"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let url = Bundle(for: Self.self).url(forResource: "template-chip", withExtension: "png", subdirectory: "iOS27"),
              let expected = UIImage(contentsOfFile: url.path) else {
            XCTFail("GOLDEN_RECORD_REQUIRED: commit attached template-chip-iOS27 PNG under Tests/__Snapshots__/iOS27/template-chip.png; recording intentionally fails")
            return
        }
        func pixels(_ image: UIImage) throws -> Data {
            let cg = try XCTUnwrap(image.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return Data(bytes: try XCTUnwrap(context.data), count: cg.width * cg.height * 4)
        }
        XCTAssertEqual(image.cgImage?.width, expected.cgImage?.width)
        XCTAssertEqual(image.cgImage?.height, expected.cgImage?.height)
        XCTAssertEqual(try pixels(image), try pixels(expected), "Golden regression: inspect the attached actual image before recording a replacement")
    }
}
