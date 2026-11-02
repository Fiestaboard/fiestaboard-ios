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

    /// Re-recorded (P1, compact chips): a chip used to be as wide as its full path plus filters
    /// (`weather.temperature|pad:3` ≈ 20 cells). It is now a whole number of document cells, at
    /// most `maxCells`, so text after it stays on the column grid; the pad:3 badge is still drawn
    /// inside the chip, and nothing is lost from the source or the spoken label.
    func testChipsAreCompactWholeCellsWithFiltersInside() throws {
        let cell = TemplateChipRenderer.cellWidth(font)
        let plain = try XCTUnwrap(attachments("{{weather.temperature}}").first)
        let filtered = try XCTUnwrap(attachments("{{weather.temperature|pad:3}}").first)
        let long = try XCTUnwrap(attachments("{{home_assistant.living_room_temperature|pad:3|upper}}").first)
        let formula = try XCTUnwrap(attachments(#"{{= IF(weather.temperature>70,"HI","") }}"#).first)
        for chip in [plain, filtered, long, formula] {
            let cells = chip.bounds.width / cell
            XCTAssertEqual(cells, cells.rounded(), accuracy: 0.001, "\(chip.source) is whole cells")
            XCTAssertLessThanOrEqual(cells, CGFloat(TemplateChipRenderer.maxCells) + 0.001, "\(chip.source) is compact")
        }
        XCTAssertGreaterThanOrEqual(filtered.bounds.width, plain.bounds.width, "the pad:3 badge is drawn inside the chip")
        XCTAssertEqual(filtered.source, "{{weather.temperature|pad:3}}", "the identifier and filters are kept")
        XCTAssertEqual(filtered.fullName, "weather.temperature | pad:3")
        XCTAssertEqual(filtered.boardWidth, 3)
        XCTAssertEqual(long.fullName, "home_assistant.living_room_temperature | pad:3 | upper")
        XCTAssertEqual(formula.fullName, #"ƒ IF(weather.temperature>70,"HI","")"#)
    }

    /// P1: the column guide counts a chip's *board* cells, so it means "the board ends here" on
    /// chip rows too: pad:3 is three cells, a tile one; a bare variable is unknown on a live server.
    func testRowFitCountsBoardCellsNotDrawnWidth() {
        func fit(_ source: String, columns: Int = 22, variables: VariableCatalog? = nil) -> BoardDocumentContainer.RowFit {
            let text = NSMutableAttributedString()
            for fragment in TemplateSyntax.fragments(source) {
                if fragment.kind == .text { text.append(NSAttributedString(string: fragment.source)) }
                else { text.append(NSAttributedString(attachment: TemplateAttachment(fragment: fragment, font: font, variables: variables))) }
            }
            return BoardDocumentContainer.rowFit(text, range: NSRange(location: 0, length: text.length), columns: columns)
        }
        XCTAssertEqual(fit("TEMP {{weather.temperature|pad:3}}°"), .fits(remaining: 13))
        XCTAssertEqual(fit("{{red}}{{red}}HELLO"), .fits(remaining: 15))
        XCTAssertEqual(fit("TEMP {{weather.temperature}}"), .unknown)
        XCTAssertEqual(fit("TEMP {{weather.temperature}}", variables: .sample(authoritative: true)), .fits(remaining: 15), "the demo's sample value is 72")
        XCTAssertEqual(fit("ABCDEFGHIJKLMNOPQRS{{weather.temperature|pad:6}}"), .cut(index: 19, fraction: 0.5))
        XCTAssertEqual(fit("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), .cut(index: 22, fraction: 0))
        XCTAssertEqual(fit("HI{{fill_space}}THERE"), .fits(remaining: 0))
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
