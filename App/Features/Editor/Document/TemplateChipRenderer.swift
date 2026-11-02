import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardRender

/// Draws `TemplateChip`s as inline attachment images (PLAN B13): variables as violet pills with
/// nested filter sub-chips, unknown variables with the amber warning treatment, formulas as
/// amber ƒ pills, colour tokens as real board tiles (the shared `FlapTilePainter`), flexible
/// space as a green chip. Images follow the trait collection (light/dark, Dynamic Type, B31).
@MainActor enum TemplateChipRenderer {
    struct Palette {
        let fill: UIColor
        let stroke: UIColor
        let text: UIColor
        let dashed: Bool
    }

    static let violet = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.77, green: 0.71, blue: 0.99, alpha: 1) : UIColor(red: 0.43, green: 0.16, blue: 0.85, alpha: 1) }
    static let amber = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.99, green: 0.83, blue: 0.30, alpha: 1) : UIColor(red: 0.71, green: 0.33, blue: 0.04, alpha: 1) }
    static let green = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.53, green: 0.94, blue: 0.67, alpha: 1) : UIColor(red: 0.08, green: 0.50, blue: 0.24, alpha: 1) }

    static func palette(_ style: TemplateChip.Style) -> Palette {
        switch style {
        case .variable: return Palette(fill: UIColor.systemPurple.withAlphaComponent(0.16), stroke: violet, text: violet, dashed: true)
        case .unknownVariable: return Palette(fill: UIColor.systemOrange.withAlphaComponent(0.14), stroke: .systemOrange, text: .label, dashed: false)
        case .formula: return Palette(fill: UIColor.systemYellow.withAlphaComponent(0.22), stroke: amber, text: amber, dashed: true)
        case .fill: return Palette(fill: UIColor.systemGreen.withAlphaComponent(0.15), stroke: green, text: green, dashed: true)
        case .span(let color): return Palette(fill: .tertiarySystemFill, stroke: .separator, text: spanColor(color), dashed: false)
        case .icon, .tile: return Palette(fill: .tertiarySystemFill, stroke: .separator, text: .label, dashed: false)
        }
    }

    static func spanColor(_ name: String) -> UIColor {
        if name.hasPrefix("#"), name.count == 7, let value = UInt32(name.dropFirst(), radix: 16) { return UIColor(chipHex: value) }
        if let color = BoardColor(rawValue: TemplateChip.tileColor(name)), let value = UInt32(color.hex.dropFirst(), radix: 16) {
            return UIColor(chipHex: value)
        }
        return .label
    }

    /// A compact chip is at most this many monospace cells wide (P1): the document keeps the
    /// board's shape, and the full name lives in the callout and the accessibility label.
    static let maxCells = 10
    static let minCells = 2

    /// One monospace cell of the document at `font`'s size (the board's column pitch in the editor).
    static func cellWidth(_ font: UIFont) -> CGFloat {
        ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)]).width
    }

    /// The chip's image and its attachment bounds (baseline-relative) for `font`. Every chip but a
    /// tile is a whole number of document cells wide, at most `maxCells`, so text after a chip stays
    /// on the column grid (P1).
    static func render(_ chip: TemplateChip, font: UIFont, traits: UITraitCollection, outlined: Bool = false) -> (UIImage, CGRect) {
        if case .tile(let color) = chip.style { return tile(color: color, font: font, traits: traits, outlined: outlined) }
        // No taller than a text line, so rows with chips keep the same pitch as plain rows.
        let height = (font.lineHeight - 1).rounded(.down)
        let cell = cellWidth(font)
        let labelFont = UIFont.systemFont(ofSize: (font.pointSize * 0.72).rounded(), weight: .semibold, width: .condensed)
        let filterFont = UIFont.systemFont(ofSize: (font.pointSize * 0.62).rounded(), weight: .bold, width: .condensed)
        let markFont = UIFont.systemFont(ofSize: (font.pointSize * 0.58).rounded(), weight: .heavy)
        let palette = palette(chip.style)
        let symbolConfiguration = UIImage.SymbolConfiguration(font: UIFont.systemFont(ofSize: (font.pointSize * 0.62).rounded(), weight: .semibold))
        let symbol: UIImage? = {
            switch chip.style {
            case .fill: return UIImage(systemName: "arrow.left.and.right", withConfiguration: symbolConfiguration)?.withTintColor(palette.text, renderingMode: .alwaysOriginal)
            case .icon: return UIImage(systemName: iconSymbol(chip.title), withConfiguration: symbolConfiguration)?.withTintColor(.label, renderingMode: .alwaysOriginal)
            default: return nil
            }
        }()
        // Source mark (shared with AND-P1): the plugin's initial, white on a dot in the chip's ink;
        // "!" on an amber dot for a variable that will draw ???.
        let mark = chip.sourceMark
        let markInk: UIColor = { if case .unknownVariable = chip.style { return .systemOrange }; return palette.stroke }()
        let markDiameter = (markFont.lineHeight * 1.0).rounded()
        // The formula's ƒ is its source mark on the amber dot (iOS-F1: compact like a variable chip).
        let prefix: String? = nil
        let prefixFont = UIFont.systemFont(ofSize: font.pointSize * 0.86, weight: .bold).italic
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: palette.text]
        let filterAttributes: [NSAttributedString.Key: Any] = [.font: filterFont, .foregroundColor: palette.text]
        let padding: CGFloat = 4, gap: CGFloat = 2
        let badges = chip.compactFilters
        let badgeWidths = badges.map { ($0 as NSString).size(withAttributes: filterAttributes).width.rounded(.up) + 5 }
        let badgesWidth = badgeWidths.reduce(0) { $0 + $1 + gap }
        let label = chip.shortTitle
        let labelWidth = (label as NSString).size(withAttributes: labelAttributes).width.rounded(.up)
        var leading = padding
        if let symbol { leading += symbol.size.width + gap }
        if mark != nil { leading += markDiameter + gap }
        if let prefix { leading += (prefix as NSString).size(withAttributes: [.font: prefixFont]).width + gap }
        let natural = leading + labelWidth + badgesWidth + padding
        let cells = min(maxCells, max(minCells, Int((natural / cell).rounded(.up))))
        let size = CGSize(width: CGFloat(cells) * cell, height: height)
        let format = UIGraphicsImageRendererFormat(for: traits)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            traits.performAsCurrent {
                // A 1 pt margin each side keeps neighbouring chips from touching.
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.25, dy: 0.75)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
                palette.fill.setFill(); path.fill()
                path.lineWidth = palette.dashed ? 1 : 1.5
                if palette.dashed { path.setLineDash([3, 2], count: 2, phase: 0) }
                palette.stroke.setStroke(); path.stroke()
                if outlined {
                    let ring = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: size.height / 2)
                    ring.lineWidth = 2; UIColor.tintColor.setStroke(); ring.stroke()
                }
                var x = padding
                if let symbol {
                    symbol.draw(at: CGPoint(x: x, y: (size.height - symbol.size.height) / 2)); x += symbol.size.width + gap
                }
                if let mark {
                    let disc = CGRect(x: x, y: (size.height - markDiameter) / 2, width: markDiameter, height: markDiameter)
                    markInk.setFill(); UIBezierPath(ovalIn: disc).fill()
                    let attributes: [NSAttributedString.Key: Any] = [.font: markFont, .foregroundColor: UIColor.white]
                    let markSize = (mark as NSString).size(withAttributes: attributes)
                    (mark as NSString).draw(at: CGPoint(x: disc.midX - markSize.width / 2, y: disc.midY - markSize.height / 2), withAttributes: attributes)
                    x += markDiameter + gap
                }
                if let prefix {
                    let attributes: [NSAttributedString.Key: Any] = [.font: prefixFont, .foregroundColor: palette.text]
                    let prefixSize = (prefix as NSString).size(withAttributes: attributes)
                    (prefix as NSString).draw(at: CGPoint(x: x, y: (size.height - prefixSize.height) / 2), withAttributes: attributes)
                    x += prefixSize.width + gap
                }
                // Badges keep their room; the label gives way (truncated) when the chip is capped.
                let room = max(0, size.width - x - padding - badgesWidth)
                let style = NSMutableParagraphStyle()
                let isVariable: Bool = { switch chip.style { case .variable, .unknownVariable: return true; default: return false } }()
                style.lineBreakMode = isVariable && label.contains(".") ? .byTruncatingMiddle : .byTruncatingTail
                var attributes = labelAttributes; attributes[.paragraphStyle] = style
                (label as NSString).draw(in: CGRect(x: x, y: (size.height - labelFont.lineHeight) / 2, width: room, height: labelFont.lineHeight), withAttributes: attributes)
                x += min(room, labelWidth) + gap
                // Filters are tiny sub-chips *inside* the chip's bounds (B13).
                for (badge, badgeWidth) in zip(badges, badgeWidths) {
                    let sub = CGRect(x: x, y: 3.5, width: badgeWidth, height: size.height - 7)
                    guard sub.maxX <= size.width - 3 else { break }
                    let subPath = UIBezierPath(roundedRect: sub, cornerRadius: sub.height / 2)
                    palette.stroke.withAlphaComponent(0.24).setFill(); subPath.fill()
                    (badge as NSString).draw(at: CGPoint(x: sub.minX + 2.5, y: sub.midY - filterFont.lineHeight / 2), withAttributes: filterAttributes)
                    x += badgeWidth + gap
                }
            }
        }
        return (image, CGRect(x: 0, y: font.descender + 0.5, width: size.width, height: size.height))
    }

    /// A colour token as a real board tile: the shared tile painter at about 1.5ch × 1em.
    static func tile(color: String, font: UIFont, traits: UITraitCollection, outlined: Bool) -> (UIImage, CGRect) {
        let height = (font.capHeight * 1.55).rounded()
        let width = (height * 0.72).rounded()
        let code = (BoardColor(rawValue: color).map { BoardTables.code(for: .color($0)) }) ?? 70
        let model = DisplayModel.flap(rows: 1, cols: 1)
        let content = Canvas { context, size in
            FlapTilePainter.paint(code: code, model: model, in: CGRect(origin: .zero, size: size), context: &context)
        }
        .frame(width: width, height: height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = traits.displayScale > 0 ? traits.displayScale : 3
        var image = renderer.uiImage ?? UIImage()
        if outlined {
            let size = CGSize(width: width + 4, height: height + 4)
            image = UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traits)).image { _ in
                image.draw(at: CGPoint(x: 2, y: 2))
                let ring = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 4)
                ring.lineWidth = 2; UIColor.tintColor.setStroke(); ring.stroke()
            }
            return (image, CGRect(x: 0, y: -2, width: size.width, height: size.height))
        }
        return (image, CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func iconSymbol(_ name: String) -> String {
        switch name.lowercased() {
        case "sun": return "sun.max.fill"
        case "cloud": return "cloud.fill"
        case "rain": return "cloud.rain.fill"
        case "snow": return "snowflake"
        case "heart": return "heart.fill"
        case "star": return "star.fill"
        case "moon": return "moon.fill"
        default: return "square.grid.3x3.fill"
        }
    }
}

extension UIColor {
    convenience init(chipHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

private extension UIFont {
    var italic: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold]) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
