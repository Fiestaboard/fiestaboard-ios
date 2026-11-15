import Foundation
import SwiftUI

/// The LED path: a port of FiestaUI `led-matrix.ts` (`ledGridLayout`,
/// `layoutLedMessage` / `layoutLedCellGrid`, `drawLedGlyph`, `cellField`,
/// `ledGutterPixels`, `rasterizeLedLayout`) plus the bitmap-layer rules of
/// FiestaBoard `src/led/matrix.py`. Pinned by `Fixtures/shared/led-golden.json`
/// (`LedGoldenTests`, 0 px diff on every layout case).
public enum LedRasterizer {

    struct Font: Sendable {
        let glyphW: Int, glyphH: Int, spacingX: Int, spacingY: Int
        let glyphs: [String: [String]]
        let icons: [String: [String]]
    }

    static let fonts: [String: Font] = {
        guard let data = RenderResources.data("led-fonts", "json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: Font] = [:]
        for (name, value) in json {
            guard let value = value as? [String: Any] else { continue }
            func int(_ key: String) -> Int { Int("\(value[key] ?? 0)") ?? 0 }
            result[name] = Font(glyphW: int("glyphWidth"), glyphH: int("glyphHeight"),
                                spacingX: int("spacingX"), spacingY: int("spacingY"),
                                glyphs: value["glyphs"] as? [String: [String]] ?? [:],
                                icons: value["icons"] as? [String: [String]] ?? [:])
        }
        return result
    }()

    /// Layout options (FiestaUI `LedLayoutOptions`).
    struct Options: Sendable {
        /// `#rrggbb` glyph colour; unparseable or nil is white.
        var textColor: String? = nil
        /// `#rrggbb` LED colour of a single-colour panel; unparseable is unset.
        var monochrome: String? = nil
        /// `letterCase: "mixed"`; only affects parsing a message.
        var mixedCase: Bool = false
        /// A plugin set's own bitmaps (`CharacterSet.glyphs`); they win over the face's.
        var glyphs: [String: [String]]? = nil
        var tileGapFill: Bool = false
        var blockPadding: Int = 0
    }

    // MARK: Public entry

    /// One glyph's rows (`#` lit) of an LED face (`"3x5"` / `"5x7"`), for canvas text shapes
    /// drawn by the editor (PLAN B24). Nil when the face lacks the character.
    public static func glyphRows(_ character: Character, font: String) -> [String]? {
        fonts[font]?.glyphs[String(character)]
    }

    /// The device frame for `frame` on an LED `model`. Content precedence is
    /// `cells` → `codes` → `message` (as `BoardFrame.boardCells`); a message
    /// keeps its case (`model.preservesCase`); layers draw last.
    public static func raster(_ frame: BoardFrame, model: DisplayModel) -> MatrixRaster {
        guard case .pixels(let width, let height) = model.geometry else { return MatrixRaster(width: 0, height: 0) }
        var options = Options()
        if case .monochrome(let hex) = model.color { options.monochrome = String(format: "#%06x", hex & 0xffffff) }
        options.mixedCase = model.preservesCase
        options.tileGapFill = model.ledLayout.tileGapFill
        options.blockPadding = model.ledLayout.blockPadding
        let font = model.font.rawValue
        if let cells = frame.cells {
            return render(rows: cells.map { $0.map(ledToken) }, width: width, height: height, font: font,
                          options: options, layers: frame.layers)
        }
        if let codes = frame.codes {
            return render(rows: codes.map { $0.map { ledToken(code: $0, code62: model.code62) } }, width: width,
                          height: height, font: font, options: options, layers: frame.layers)
        }
        return render(message: frame.message ?? "", width: width, height: height, font: font,
                      options: options, layers: frame.layers)
    }

    /// An app `BoardToken` as the LED path reads it (FiestaUI `BoardToken`).
    static func ledToken(_ token: BoardToken) -> LedToken {
        var out: LedToken
        switch token.kind {
        case .color: out = .tile(token.code.map(String.init) ?? "70")
        case .char: out = .char(token.value ?? " ")
        }
        out.color = token.color
        out.background = token.background
        if let icon = token.icon { out.icon = LedMarkup.resolveIconName(icon.lowercased()) ?? icon }
        return out
    }

    /// A flap wire code as a token: 63-71 tiles, 62 the board's code-62 glyph.
    static func ledToken(code: Int, code62: Code62Glyph) -> LedToken {
        if (63...71).contains(code) { return .tile(String(code)) }
        if case .character(let c) = BoardTables.cell(forCode: code, code62: code62) { return .char(String(c)) }
        return .blank
    }

    // MARK: Layout (led-matrix.ts)

    struct Grid: Sendable {
        let width: Int, height: Int, rows: Int, cols: Int, originX: Int, originY: Int
        let font: Font
    }

    /// `ledGridLayout`.
    static func grid(width: Int, height: Int, font: Font) -> Grid {
        let w = min(max(width, 1), 256), h = min(max(height, 1), 256)
        let cellW = font.glyphW + font.spacingX, cellH = font.glyphH + font.spacingY
        let cols = (w + font.spacingX) / cellW
        let rows = (h + font.spacingY) / cellH
        let usedW = cols > 0 ? cols * cellW - font.spacingX : 0
        let usedH = rows > 0 ? rows * cellH - font.spacingY : 0
        return Grid(width: w, height: h, rows: rows, cols: cols,
                    originX: (w - usedW) / 2, originY: (h - usedH) / 2, font: font)
    }

    /// A resolved cell (`LedCell`): glyph key, text colour, block background.
    struct Cell: Sendable {
        var glyph: String
        var color: String
        var background: String?
    }

    enum Entry { case blank, char(String), tile(String), icon(String) }

    /// `LED_GLYPHS` as a membership set.
    static let builtinGlyphKeys: Set<String> = {
        var keys: Set<String> = [" ", "♥"]
        for s in ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "0123456789", "!@#$()-+&=;:'\"%,./?°", "abcdefghijklmnopqrstuvwxyz"] {
            for c in s { keys.insert(String(c)) }
        }
        for code in 63...71 { keys.insert("tile:\(code)") }
        for name in LedMarkup.icons.table.keys { keys.insert("icon:\(name)") }
        return keys
    }()

    /// `ledGlyphKey`.
    static func glyphKey(_ token: LedToken, custom: [String: [String]]?) -> String {
        if let icon = token.icon {
            let key = "icon:\(icon)"
            return builtinGlyphKeys.contains(key) ? key : " "
        }
        if token.isTile {
            return LedMarkup.tileCodeByHex[LedMarkup.resolveColorCode(token.code)].map { "tile:\($0)" } ?? " "
        }
        if builtinGlyphKeys.contains(token.value) { return token.value }
        return custom?[token.value] != nil ? token.value : " "
    }

    /// `ledGlyphEntry`.
    static func entry(_ glyph: String) -> Entry {
        if glyph == " " || glyph.isEmpty { return .blank }
        if glyph.hasPrefix("icon:") { return .icon(String(glyph.dropFirst(5))) }
        if glyph.hasPrefix("tile:") { return .tile(String(glyph.dropFirst(5))) }
        return .char(glyph)
    }

    /// `ledCellForToken`.
    static func cell(_ token: LedToken, textColor: String, monochrome: String?, custom: [String: [String]]?) -> Cell {
        let spanned = token.color != nil
        let span = token.color.flatMap(LedMarkup.colorCodeToHex)
        let background = token.background.flatMap(LedMarkup.colorCodeToHex)
        let color = background != nil && monochrome != nil
            ? "#000000" : (monochrome ?? span ?? (spanned ? "#000000" : textColor))
        return Cell(glyph: glyphKey(token, custom: custom), color: color,
                    background: background.map { monochrome ?? $0 })
    }

    static func isTwoDigitCode(_ s: String) -> Bool {
        s.unicodeScalars.count == 2 && s.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    /// `cellField`: the colour a cell's whole glyph box lights in, or nil.
    static func field(_ cell: Cell, font: Font, mono: String?) -> String? {
        if let background = cell.background { return background }
        var code: String?
        switch entry(cell.glyph) {
        case .tile(let c): code = c
        case .icon(let name) where font.icons[name] == nil:
            if let fallback = LedMarkup.icons.table[name]?.fallback, isTwoDigitCode(fallback) { code = fallback }
        default: break
        }
        guard let code, let hex = LedMarkup.colorCodeToHex(code) else { return nil }
        return mono != nil ? cell.color : hex
    }

    // MARK: Painting (rasterizeLedOps, painted directly in op order)

    struct Painter {
        var raster: MatrixRaster
        mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: String) {
            guard w > 0, h > 0 else { return }
            let rgb = LedMarkup.parseHex(color) ?? 0
            for dy in 0..<h { for dx in 0..<w { raster.set(x: x + dx, y: y + dy, rgb) } }
        }
        mutating func glyph(_ x: Int, _ y: Int, _ rows: [String], _ color: String) {
            let rgb = LedMarkup.parseHex(color) ?? 0
            for (dy, line) in rows.enumerated() {
                for (dx, bit) in line.unicodeScalars.enumerated() where bit == "#" { raster.set(x: x + dx, y: y + dy, rgb) }
            }
        }
    }

    /// `drawLedGlyph`.
    static func drawGlyph(_ p: inout Painter, _ glyph: String, _ x: Int, _ y: Int, font: Font, color: String,
                          options: Options) {
        let mono = options.monochrome
        switch entry(glyph) {
        case .blank: return
        case .tile(let code):
            if let hex = LedMarkup.colorCodeToHex(code) { p.rect(x, y, font.glyphW, font.glyphH, mono != nil ? color : hex) }
        case .icon(let name):
            guard let rows = font.icons[name] else {
                if let fallback = LedMarkup.icons.table[name]?.fallback {
                    let token: LedToken = isTwoDigitCode(fallback) ? .tile(fallback) : .char(fallback)
                    drawGlyph(&p, glyphKey(token, custom: nil), x, y, font: font, color: color, options: options)
                }
                return
            }
            p.glyph(x, y, rows, mono != nil ? color : (LedMarkup.icons.table[name]?.color ?? color))
        case .char(let c):
            guard let rows = options.glyphs?[c] ?? font.glyphs[c] else { return }
            p.glyph(x, y, rows, mono != nil ? color : (c == "♥" ? LedMarkup.boardRed : color))
        }
    }

    /// `gapModeBlockRect`: a block cell's rect joins a same-colour block cell right and below.
    static func gapModeBlockRect(_ g: Grid, _ cells: [Cell], row: Int, col: Int) -> (Int, Int, Int, Int) {
        let font = g.font
        let cell = cells[row * g.cols + col]
        let right = col + 1 < g.cols ? cells[row * g.cols + col + 1] : nil
        let below = row + 1 < g.rows ? cells[(row + 1) * g.cols + col] : nil
        let joinRight = right != nil && right?.background == cell.background
        let joinBelow = below != nil && below?.background == cell.background
        return (g.originX + col * (font.glyphW + font.spacingX), g.originY + row * (font.glyphH + font.spacingY),
                font.glyphW + (joinRight ? font.spacingX : 0), font.glyphH + (joinBelow ? font.spacingY : 0))
    }

    /// `ledGutterPixels`: the pixels outside every glyph box that `tileGap: "fill"`
    /// and `blockPadding: 1` light, row-major (design spec §7.6).
    static func gutterPixels(_ g: Grid, _ cells: [Cell], options: Options) -> [(x: Int, y: Int, color: String)] {
        let fill = options.tileGapFill, padding = options.blockPadding == 1
        var out: [(x: Int, y: Int, color: String)] = []
        guard fill || padding, g.rows > 0, g.cols > 0 else { return out }
        let font = g.font
        let gw = font.glyphW, gh = font.glyphH, sx = font.spacingX, sy = font.spacingY
        let usedW = g.cols * (gw + sx) - sx, usedH = g.rows * (gh + sy) - sy
        // The cells whose glyph box, grown by one pixel, covers `at`, and whether `at` is inside a box.
        func touching(_ at: Int, origin: Int, count: Int, size: Int, step: Int) -> (idx: [Int], box: Bool) {
            var idx: [Int] = []; var box = false
            for k in 0..<count {
                let a0 = origin + k * step
                if at >= a0 - 1 && at <= a0 + size {
                    idx.append(k)
                    if at >= a0 && at < a0 + size { box = true }
                }
            }
            return (idx, box)
        }
        let fields = cells.map { field($0, font: font, mono: options.monochrome) }
        let xMin = max(0, g.originX - 1), xMax = min(g.width - 1, g.originX + usedW)
        let yMin = max(0, g.originY - 1), yMax = min(g.height - 1, g.originY + usedH)
        guard xMin <= xMax, yMin <= yMax else { return out }
        let columns = (xMin...xMax).map { x in
            (t: touching(x, origin: g.originX, count: g.cols, size: gw, step: gw + sx),
             inside: x >= g.originX && x < g.originX + usedW)
        }
        for y in yMin...yMax {
            let rowT = touching(y, origin: g.originY, count: g.rows, size: gh, step: gh + sy)
            let rowInside = y >= g.originY && y < g.originY + usedH
            for x in xMin...xMax {
                let col = columns[x - xMin]
                if col.t.box && rowT.box { continue }
                var color: String?
                var conflict = false, every = true, block = false
                for r in rowT.idx {
                    for c in col.t.idx {
                        let i = r * g.cols + c
                        guard let f = fields[i] else { every = false; continue }
                        if color == nil { color = f } else if color != f { conflict = true }
                        if cells[i].background == f { block = true }
                    }
                }
                guard let color, !conflict else { continue }
                if (fill && every && col.inside && rowInside) || (padding && block) { out.append((x, y, color)) }
            }
        }
        return out
    }

    // MARK: Render

    /// `layoutLedMessage` + layers + `rasterizeLedLayout`.
    static func render(message: String, width: Int, height: Int, font fontID: String, options: Options,
                       layers: [PixelLayer] = []) -> MatrixRaster {
        guard let font = fonts[fontID] else { return MatrixRaster(width: width, height: height) }
        let g = grid(width: width, height: height, font: font)
        let lines = message.components(separatedBy: "\n")
        let rows: [[LedToken]] = (0..<g.rows).map { r in
            LedMarkup.parseLine(r < lines.count ? lines[r] : "", maxTokens: g.cols, preserveCase: options.mixedCase)
        }
        return render(rows: rows, grid: g, options: options, layers: layers)
    }

    /// `layoutLedCellGrid` + layers + `rasterizeLedLayout`: tokens drawn as given
    /// (no re-casing), clipped and padded to the grid.
    static func render(rows: [[LedToken]], width: Int, height: Int, font fontID: String, options: Options,
                       layers: [PixelLayer] = []) -> MatrixRaster {
        guard let font = fonts[fontID] else { return MatrixRaster(width: width, height: height) }
        return render(rows: rows, grid: grid(width: width, height: height, font: font), options: options, layers: layers)
    }

    static func render(rows: [[LedToken]], grid g: Grid, options: Options, layers: [PixelLayer]) -> MatrixRaster {
        var options = options
        options.monochrome = LedMarkup.resolveHexOption(options.monochrome, nil)
        let textColor = options.monochrome ?? LedMarkup.resolveHexOption(options.textColor, "#ffffff") ?? "#ffffff"
        let font = g.font
        var cells: [Cell] = []
        cells.reserveCapacity(g.rows * g.cols)
        for r in 0..<g.rows {
            let line = r < rows.count ? rows[r] : []
            for c in 0..<g.cols {
                cells.append(cell(c < line.count ? line[c] : .blank, textColor: textColor,
                                  monochrome: options.monochrome, custom: options.glyphs))
            }
        }
        var p = Painter(raster: MatrixRaster(width: g.width, height: g.height))
        let cellW = font.glyphW + font.spacingX, cellH = font.glyphH + font.spacingY
        for row in 0..<g.rows {
            for col in 0..<g.cols {
                let cell = cells[row * g.cols + col]
                let x = g.originX + col * cellW, y = g.originY + row * cellH
                if let background = cell.background {
                    if options.tileGapFill {
                        p.rect(x, y, font.glyphW, font.glyphH, background)
                    } else {
                        let (rx, ry, w, h) = gapModeBlockRect(g, cells, row: row, col: col)
                        p.rect(rx, ry, w, h, background)
                    }
                }
                drawGlyph(&p, cell.glyph, x, y, font: font, color: cell.color, options: options)
            }
        }
        for px in gutterPixels(g, cells, options: options) { p.rect(px.x, px.y, 1, 1, px.color) }
        let panel = options.monochrome.flatMap(LedMarkup.parseHex)
        for layer in layers { paint(layer, into: &p.raster, monochrome: panel) }
        return p.raster
    }

    /// A bitmap layer, clipped to the matrix: alpha > 0 overwrites with its RGB
    /// (no blending), alpha 0 leaves what is under; missing bytes are transparent.
    /// On a monochrome panel a pixel with alpha > 0 lights in the panel colour
    /// when `299·r + 587·g + 114·b ≥ 127500` and is unlit otherwise.
    static func paint(_ layer: PixelLayer, into raster: inout MatrixRaster, monochrome: UInt32?) {
        guard layer.w > 0, layer.h > 0 else { return }
        let bytes = [UInt8](layer.rgba)
        let x0 = max(0, layer.x), y0 = max(0, layer.y)
        let x1 = min(raster.width, layer.x + layer.w), y1 = min(raster.height, layer.y + layer.h)
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = ((y - layer.y) * layer.w + (x - layer.x)) * 4
                guard i + 3 < bytes.count, bytes[i + 3] > 0 else { continue }
                let r = UInt32(bytes[i]), g = UInt32(bytes[i + 1]), b = UInt32(bytes[i + 2])
                if let monochrome {
                    raster.set(x: x, y: y, 299 * r + 587 * g + 114 * b >= 127_500 ? monochrome : 0)
                } else {
                    raster.set(x: x, y: y, r << 16 | g << 8 | b)
                }
            }
        }
    }
}

/// Draws a `MatrixRaster` as dots: substrate, off dots, lit dots (FiestaUI
/// `led-matrix-display.js:61-72`, without the glow pass).
public struct MatrixDotsView: View {
    let raster: MatrixRaster
    @Environment(\.displayScale) private var displayScale
    let appearance: LedAppearance
    public init(raster: MatrixRaster, appearance: LedAppearance) { self.raster = raster; self.appearance = appearance }
    public var body: some View {
        Canvas { context, size in
            guard raster.width > 0, raster.height > 0 else { return }
            let pitch = min(size.width / Double(raster.width), size.height / Double(raster.height))
            let dot = pitch * appearance.dotRatio
            let inset = (pitch - dot) / 2
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: appearance.substrateColor)))
            var off = Path()
            var lit: [UInt32: Path] = [:]
            for y in 0..<raster.height {
                for x in 0..<raster.width {
                    let rect = CGRect(x: Double(x) * pitch + inset, y: Double(y) * pitch + inset, width: dot, height: dot)
                    let shape = LedDot.path(rect, round: appearance.pixelShape == .round, corner: LedDot.cornerRadius(dot: dot, scale: displayScale))
                    if let color = raster.pixel(x: x, y: y) { lit[color, default: Path()].addPath(shape) } else { off.addPath(shape) }
                }
            }
            context.fill(off, with: .color(Color(rgb: appearance.offColor)))
            for (color, path) in lit { context.fill(path, with: .color(Color(rgb: color))) }
        }
        .aspectRatio(Double(max(raster.width, 1)) / Double(max(raster.height, 1)), contentMode: .fit)
        .accessibilityHidden(true)
    }
}
