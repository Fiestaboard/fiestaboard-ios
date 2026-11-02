import XCTest
import UIKit
import FiestaBoardDocuments
@testable import FiestaBoard

/// PLAN B13/B31: each token kind draws as its chip, at text height, with its spoken label.
@MainActor final class TemplateChipFactoryTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
    private let row = #"TEMP {{weather.temperature|pad:3}} {{= IF(weather.temperature>70,"HI","") }} {{blue}}"#

    private func attachments(_ source: String, variables: VariableCatalog? = nil) -> [TemplateAttachment] {
        TemplateSyntax.fragments(source).filter { $0.kind != .text }
            .map { TemplateAttachment(fragment: $0, font: font, variables: variables, traits: UITraitCollection(userInterfaceStyle: .light)) }
    }

    func testKindToStyle() {
        let chips = attachments(row + " {{fill_space}} {{red:HOT}} {{icon:sun}}")
        XCTAssertEqual(chips.compactMap(\.chip?.style), [.variable, .formula, .tile(color: "blue"), .fill, .span(color: "red"), .icon])
        for chip in chips {
            XCTAssertNotNil(chip.image, "\(chip.source) draws an image")
            XCTAssertLessThanOrEqual(chip.bounds.height, font.lineHeight + 2, "\(chip.source) sits at text height")
            XCTAssertGreaterThan(chip.bounds.width, 4)
        }
    }

    func testColourTileIsARealTileNotABlackBlock() throws {
        let tile = try XCTUnwrap(attachments("{{red}}").first?.image?.cgImage)
        // Sample the tile's centre: the pigment chip is the board's red (#eb4034), not black.
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(tile, in: CGRect(x: -CGFloat(tile.width) / 2, y: -CGFloat(tile.height) / 2 + 0.5 * CGFloat(tile.height) * 0.3,
                                      width: CGFloat(tile.width), height: CGFloat(tile.height)))
        let pixel = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        XCTAssertGreaterThan(Int(pixel[0]), 150, "red channel")
        XCTAssertLessThan(Int(pixel[2]), 120, "blue channel")
    }

    func testFiltersWidenTheChipInsideItsBounds() throws {
        let plain = try XCTUnwrap(attachments("{{weather.temperature}}").first)
        let filtered = try XCTUnwrap(attachments("{{weather.temperature|pad:3}}").first)
        XCTAssertGreaterThan(filtered.bounds.width, plain.bounds.width, "the pad:3 sub-chip is drawn inside the chip")
    }

    func testAccessibilityLabels() {
        let chips = attachments(row)
        XCTAssertEqual(chips.map(\.accessibilityLabel), ["variable weather.temperature, filter pad 3", #"formula, IF(weather.temperatu…"#, "blue tile"])
    }

    func testUnknownVariableGetsTheWarningTreatment() throws {
        let strict = VariableCatalog.sample(authoritative: true)
        let known = try XCTUnwrap(attachments("{{weather.temperature}}", variables: strict).first)
        let unknown = try XCTUnwrap(attachments("{{bogus.thing}}", variables: strict).first)
        XCTAssertEqual(known.chip?.style, .variable)
        guard case .unknownVariable? = unknown.chip?.style else { return XCTFail("warning style") }
        XCTAssertTrue(unknown.accessibilityLabel?.contains("???") == true)
        XCTAssertGreaterThan(unknown.bounds.width, known.bounds.width - 60, "room for the ! icon")
    }
}
