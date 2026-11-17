import SwiftUI

/// The face, ink and bezel tokens of a split-flap board, exactly as FiestaUI
/// draws them (`theme.css:178-184`, design/board-display-visuals.md §1.4).
///
/// Mobile change from tvOS: the unlit flap is FiestaUI's hardware surface
/// `#0d0d0d` (tvOS used board black `#1a1a1a`), colour codes draw as an inset
/// pigment chip on that surface, and the heart glyph is always red.
public struct FlapPalette: Hashable, Sendable {
    public let surface: UInt32
    public let ink: UInt32
    /// The board behind the tiles (what shows in the gutters).
    public let backing: UInt32
    public let bezel: UInt32
    public let bezelBorder: UInt32
    public let whiteHardware: Bool
    /// Monochrome LED fallback: every lit tile/glyph draws in this colour.
    public let monochrome: UInt32?

    public static let black = FlapPalette(surface: 0x0d0d0d, ink: 0xf0f0e8, backing: 0x000000,
                                          bezel: 0x050505, bezelBorder: 0x1a1a1a, whiteHardware: false, monochrome: nil)
    public static let white = FlapPalette(surface: 0xfafafa, ink: 0x0d0d0d, backing: 0xe2e2e2,
                                          bezel: 0xf8f8f8, bezelBorder: 0xd8d8d8, whiteHardware: true, monochrome: nil)
    public static let heart: UInt32 = 0xeb4034

    public static func forBoard(_ color: BoardColor) -> FlapPalette { color == .white ? .white : .black }

    public init(surface: UInt32, ink: UInt32, backing: UInt32, bezel: UInt32, bezelBorder: UInt32,
                whiteHardware: Bool, monochrome: UInt32?) {
        self.surface = surface; self.ink = ink; self.backing = backing; self.bezel = bezel
        self.bezelBorder = bezelBorder; self.whiteHardware = whiteHardware; self.monochrome = monochrome
    }

    public func monochrome(_ hex: UInt32) -> FlapPalette {
        FlapPalette(surface: surface, ink: hex, backing: backing, bezel: bezel, bezelBorder: bezelBorder,
                    whiteHardware: whiteHardware, monochrome: hex)
    }

    /// White hardware inverts codes 69/70 (`resolveColorCode`, FiestaUI
    /// `board-colors.js:84-90`): `{white}` paints `#1a1a1a`, `{black}` paints `#ffffff`.
    public func pigment(_ color: BoardColor) -> UInt32 {
        if let monochrome { return color == .black ? surface : monochrome }
        if whiteHardware && color == .white { return 0x1a1a1a }
        if whiteHardware && color == .black { return 0xffffff }
        return UInt32(BoardColor.hexValue(color))
    }

    public func ink(for character: Character) -> UInt32 {
        if let monochrome { return monochrome }
        return character == "♥" ? Self.heart : ink
    }
}

extension BoardColor {
    static func hexValue(_ color: BoardColor) -> Int { Int(color.hex.dropFirst(), radix: 16) ?? 0x1a1a1a }
}

/// Paints one flap: surface, glyph or inset pigment chip, then the seam.
/// Shared by the board canvas, the static thumbnail and (from iOS-E2) the
/// editor's colour-tile attachments, so a tile looks the same everywhere.
public enum FlapTilePainter {

    /// Inset of the pigment chip inside a colour tile, as fractions of the
    /// tile (web: top 3–8 px, bottom 4–10 px, sides 1–3 px, scaled by size).
    public static let chipInsetTop = 0.16
    public static let chipInsetBottom = 0.20
    public static let chipInsetSide = 0.09

    public static func paint(code: Int, model: DisplayModel, in rect: CGRect, context: inout GraphicsContext) {
        let tile = TileRect(row: 0, col: 0, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                            radius: rect.height * BoardGeometry.tileRadiusRatio,
                            cell: BoardTables.cell(forCode: code, code62: model.code62))
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]
        let palette = model.flapPalette
        draw(tile: tile, cell: tile.cell, palette: palette, font: BoardFont.glyph(size: rect.height * BoardLayout.fontSizeRatio),
             in: &context, resolved: &resolved)
        drawSeam(tile: tile, seam: seam(forTileHeight: rect.height), palette: palette, in: &context)
    }

    static func chipRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + rect.width * chipInsetSide,
               y: rect.minY + rect.height * chipInsetTop,
               width: rect.width * (1 - 2 * chipInsetSide),
               height: rect.height * (1 - chipInsetTop - chipInsetBottom))
    }

    static func draw(tile: TileRect, cell: BoardCell, palette: FlapPalette, font: Font,
                     in context: inout GraphicsContext,
                     resolved: inout [Character: GraphicsContext.ResolvedText]) {
        let rect = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
        let shape = Path(roundedRect: rect, cornerRadius: tile.radius)
        context.fill(shape, with: .color(Color(rgb: palette.surface)))
        switch cell {
        case .blank:
            break
        case .color(let color):
            let pigment = palette.pigment(color)
            guard pigment != palette.surface else { break }
            let chip = chipRect(rect)
            let chipShape = Path(roundedRect: chip, cornerRadius: tile.radius * 0.6)
            // A raised chip: a faint drop shadow under the pigment.
            context.fill(Path(roundedRect: chip.offsetBy(dx: 0, dy: max(0.5, tile.height * 0.02)),
                              cornerRadius: tile.radius * 0.6),
                         with: .color(.black.opacity(palette.whiteHardware ? 0.12 : 0.35)))
            context.fill(chipShape, with: .color(Color(rgb: pigment)))
        case .character(let character):
            let text: GraphicsContext.ResolvedText
            if let cached = resolved[character] {
                text = cached
            } else {
                text = context.resolve(Text(String(character)).font(font).foregroundColor(Color(rgb: palette.ink(for: character))))
                resolved[character] = text
            }
            context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    /// The split between the two leaves: a dark gap with the lit top edge
    /// of the lower leaf under it.
    struct Seam: Equatable {
        let thickness: Double
        let ink: Double
    }

    static let seamRatio = 1.0 / 80

    static func seam(forTileHeight height: Double) -> Seam {
        let line = height * seamRatio
        let thickness = max(1, line)
        return Seam(thickness: thickness, ink: max(0.3, min(1, line / thickness)))
    }

    static func drawSeam(tile: TileRect, seam: Seam, palette: FlapPalette, in context: inout GraphicsContext) {
        let top = (tile.y + tile.height / 2).rounded()
        let gap = CGRect(x: tile.x, y: top, width: tile.width, height: seam.thickness)
        let highlight = CGRect(x: tile.x, y: top + seam.thickness, width: tile.width, height: seam.thickness)
        context.fill(Path(gap), with: .color(Color.black.opacity((palette.whiteHardware ? 0.12 : 0.55) * seam.ink)))
        context.fill(Path(highlight), with: .color(Color.white.opacity((palette.whiteHardware ? 0.55 : 0.10) * seam.ink)))
    }
}
