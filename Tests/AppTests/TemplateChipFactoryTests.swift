import XCTest
import UIKit
import SwiftUI
import FiestaBoardRender
import FiestaBoardDocuments
@testable import FiestaBoard

/// Runs before the other app test classes and exercises the first production tile directly.
/// No diagnostic renderer may warm this path before the original-pixel assertion.
@MainActor final class ATemplateTileColdCaptureTests: XCTestCase {
    func testFirstProductionTilePreservesOriginalPixels() throws {
        let scale: CGFloat = 2
        let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        let height = (font.capHeight * 1.55).rounded()
        let width = (height * 0.72).rounded()
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light),
                                                   UITraitCollection(displayScale: scale)])
        let (tile, bounds) = TemplateChipRenderer.tile(color: "red", font: font, traits: traits, outlined: false)
        let backing = try XCTUnwrap(tile.cgImage, "first production render has backing pixels")
        XCTAssertEqual(bounds.size, CGSize(width: width, height: height))
        XCTAssertEqual(tile.scale, scale)
        XCTAssertEqual(backing.width, Int(width * scale))
        XCTAssertEqual(backing.height, Int(height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let actual = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 48), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 48))
            tile.draw(at: CGPoint(x: 8, y: 12))
        }
        let attachment = XCTAttachment(image: actual)
        attachment.name = "template-tile-first-production"
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "template-chip", withExtension: "png", subdirectory: "iOS27"))
        let crop = CGRect(x: 16, y: 24, width: width * scale, height: height * scale)
        let expected = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage?.cropping(to: crop))
        let captured = try XCTUnwrap(actual.cgImage?.cropping(to: crop))
        func pixels(_ image: CGImage) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
        }
        let actualPixels = try pixels(captured)
        let expectedPixels = try pixels(expected)
        print("FirstProductionTemplateTile exactMatch=\(actualPixels == expectedPixels)")
        XCTAssertEqual(actualPixels, expectedPixels, "first production render must retain the original tile pixels")
    }
}

/// PLAN B13/B31: each token kind draws as its chip, at text height, with its spoken label.
@MainActor final class TemplateChipFactoryTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
    private let row = #"TEMP {{weather.temperature|pad:3}} {{= IF(weather.temperature>70,"HI","") }} {{blue}}"#

    private func attachments(_ source: String, variables: VariableCatalog? = nil) -> [TemplateAttachment] {
        TemplateSyntax.fragments(source).filter { $0.kind != .text }
            .map { TemplateAttachment(fragment: $0, font: font, variables: variables, traits: UITraitCollection(userInterfaceStyle: .light)) }
    }

    /// Each first production render must own pixels, preserve point geometry and draw pigment.
    /// The native seed golden caught an empty first red tile even though later factory calls passed.
    func testAFirstColourTilesHaveOwnedPixelsAtBothTierOneScales() throws {
        for scale in [CGFloat(2), CGFloat(3)] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light),
                                                       UITraitCollection(displayScale: scale)])
            for color in ["red", "blue"] {
                let (image, bounds) = TemplateChipRenderer.tile(color: color, font: font, traits: traits, outlined: false)
                let cg = try XCTUnwrap(image.cgImage, "first \(color) tile at \(scale)x has actual pixels")
                XCTAssertEqual(image.scale, scale)
                XCTAssertEqual(image.size.width, bounds.width, accuracy: 0.001)
                XCTAssertEqual(image.size.height, bounds.height, accuracy: 0.001)
                XCTAssertEqual(cg.width, Int(bounds.width * scale))
                XCTAssertEqual(cg.height, Int(bounds.height * scale))
                let context = try XCTUnwrap(CGContext(data: nil, width: cg.width, height: cg.height,
                    bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                let pixels = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
                let index = ((cg.height / 3) * cg.width + cg.width / 2) * 4
                XCTAssertEqual(pixels[index + 3], 255)
                if color == "red" {
                    XCTAssertGreaterThan(pixels[index], 150)
                    XCTAssertLessThan(pixels[index + 2], 120)
                } else {
                    XCTAssertGreaterThan(pixels[index + 2], pixels[index])
                }
            }
        }
    }

    /// Diagnostic only: retain the original seed assertion while comparing single-render backends.
    /// Each alternative owns a fresh renderer; none warms or retries another path.
    func testFirstTileBackendPixelDiagnostics() throws {
        let scale: CGFloat = 2
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .light),
                                                   UITraitCollection(displayScale: scale)])
        let height = (font.capHeight * 1.55).rounded()
        let width = (height * 0.72).rounded()
        let size = CGSize(width: width, height: height)
        func content() -> some View {
            Canvas { context, size in
                FlapTilePainter.paint(code: BoardTables.code(for: .color(.red)),
                    model: .flap(rows: 1, cols: 1), in: CGRect(origin: .zero, size: size), context: &context)
            }.frame(width: width, height: height)
        }
        func ownedContext() -> CGContext? {
            CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        func direct(rasterizationScale: CGFloat) -> UIImage? {
            let renderer = ImageRenderer(content: content())
            renderer.scale = scale
            var result: CGImage?
            renderer.render(rasterizationScale: rasterizationScale) { _, draw in
                guard let context = ownedContext() else { return }
                context.scaleBy(x: scale, y: scale)
                draw(context)
                result = context.makeImage()
            }
            return result.map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
        }
        func uiOwned() -> UIImage? {
            let renderer = ImageRenderer(content: content())
            renderer.scale = scale
            let format = UIGraphicsImageRendererFormat(for: traits)
            format.scale = scale
            var result: UIImage?
            renderer.render(rasterizationScale: scale) { _, draw in
                result = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    context.cgContext.translateBy(x: 0, y: height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    draw(context.cgContext)
                }
            }
            return result
        }
        func cgOwned() -> UIImage? {
            let renderer = ImageRenderer(content: content())
            renderer.scale = scale
            guard let image = renderer.cgImage, let context = ownedContext() else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage().map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
        }
        func compositedTile(_ tile: UIImage, name: String) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale; format.opaque = true
            let seed = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 48), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 48))
                tile.draw(at: CGPoint(x: 8, y: 12))
            }
            let attachment = XCTAttachment(image: seed)
            attachment.name = "template-tile-backend-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            return try XCTUnwrap(seed.cgImage?.cropping(to: CGRect(x: 16, y: 24, width: width * scale, height: height * scale)))
        }
        func pixels(_ image: CGImage) throws -> [UInt8] {
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self)),
                                             count: image.width * image.height * 4))
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "template-chip", withExtension: "png", subdirectory: "iOS27"))
        let expected = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage?.cropping(to:
            CGRect(x: 16, y: 24, width: width * scale, height: height * scale)))
        let expectedPixels = try pixels(expected)
        let variants: [(String, @MainActor () -> UIImage?)] = [
            ("production-owned", { TemplateChipRenderer.tile(color: "red", font: self.font, traits: traits, outlined: false).0 }),
            ("ui-owned", uiOwned), ("cgimage-owned", cgOwned),
            ("direct-rasterization-one", { direct(rasterizationScale: 1) })
        ]
        for (name, render) in variants {
            guard let image = render(), image.cgImage != nil else {
                print("TemplateTileBackendProbe \(name) missing backing")
                continue
            }
            let actual = try pixels(compositedTile(image, name: name))
            XCTAssertEqual(actual.count, expectedPixels.count)
            guard actual.count == expectedPixels.count else { continue }
            var changed = 0, maximum = 0
            for index in stride(from: 0, to: actual.count, by: 4) {
                if (0..<4).contains(where: { actual[index + $0] != expectedPixels[index + $0] }) { changed += 1 }
                for channel in 0..<4 { maximum = max(maximum, abs(Int(actual[index + channel]) - Int(expectedPixels[index + channel]))) }
            }
            print("TemplateTileBackendProbe \(name) changedPixels=\(changed) maxChannelDelta=\(maximum) scale=\(image.scale)")
        }
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
        XCTAssertLessThanOrEqual(filtered.bounds.width / cell, 10.001, "{{weather.temperature|pad:3}} is about 10 cells (AND-P1 target)")
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
