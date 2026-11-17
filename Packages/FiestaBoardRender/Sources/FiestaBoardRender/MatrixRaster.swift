// Vendored from fiestaboard-tvos@f1fc67d Sources/Core/MatrixRaster.swift. MIT; see ThirdPartyNotices.
import Foundation

/// Bounded, row-major RGB pixels. Zero means an unlit LED.
public struct MatrixRaster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var rgb: [UInt8]
    public var lit: [Bool]
    public init(width: Int, height: Int) {
        self.width = min(MatrixDisplay.maxPixelDimension, max(0, width)); self.height = min(MatrixDisplay.maxPixelDimension, max(0, height))
        rgb = Array(repeating: 0, count: self.width * self.height * 3)
        lit = Array(repeating: false, count: self.width * self.height)
    }
    public func pixel(x: Int, y: Int) -> UInt32? {
        guard x >= 0, y >= 0, x < width, y < height, lit[y * width + x] else { return nil }
        let i = (y * width + x) * 3
        return UInt32(rgb[i]) << 16 | UInt32(rgb[i + 1]) << 8 | UInt32(rgb[i + 2])
    }
    /// Paint one pixel (clipped). Painting black turns the pixel off.
    mutating func set(x: Int, y: Int, _ color: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 3
        rgb[i] = UInt8((color >> 16) & 0xff); rgb[i + 1] = UInt8((color >> 8) & 0xff); rgb[i + 2] = UInt8(color & 0xff)
        lit[y * width + x] = color & 0xffffff != 0
    }
    public var pixels: [UInt32] {
        (0..<(width * height)).map { i in UInt32(rgb[i * 3]) << 16 | UInt32(rgb[i * 3 + 1]) << 8 | UInt32(rgb[i * 3 + 2]) }
    }
    public init(width: Int, height: Int, pixels: [UInt32], text: String = "") {
        self.init(width: width, height: height)
        self.text = text
        for (i, pixel) in pixels.prefix(self.width * self.height).enumerated() { set(x: i % self.width, y: i / self.width, pixel) }
    }
    /// Readable content of the clipped glyph grid, including icon labels.
    public var text: String = ""

    public func spoken(message: String?) -> String {
        if let message {
            let words = message.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if !words.isEmpty { return words }
        }
        if !text.isEmpty { return text }
        return pixels.contains { $0 != 0 } ? "Coloured pixels, no text" : BoardSpeech.blank
    }

    private struct Face: Decodable {
        let glyphWidth: Int
        let glyphHeight: Int
        let spacingX: Int
        let spacingY: Int
        let glyphs: [String: [String]]
        let icons: [String: [String]]
    }
    private struct Registry: Decodable {
        struct Icon: Decodable {
            let label: String
            let color: String
            let fallback: String?
        }
        let icons: [String: Icon]
        let aliases: [String: String]
    }
    private static func resource<T: Decodable>(_ name: String) -> T {
        guard let url = RenderResources.url(name, "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            preconditionFailure("Missing or invalid bundled matrix data: \(name)")
        }
        return value
    }
    private static let faces: [String: Face] = resource("led-fonts")

    private static func characterColumns(width: Int, face: Face) -> (pitch: Int, count: Int, origin: Int) {
        let pitch = face.glyphWidth + face.spacingX
        let count = (width + face.spacingX) / pitch
        return (pitch, count, (width - (count * pitch - face.spacingX)) / 2)
    }

    /// The same centered character grid used by the rasterizer. The final
    /// reveal includes the trailing outer margin, even on nonstandard panels.
    static func characterColumnBoundaries(width: Int, font: String) -> [Int] {
        guard width > 0 else { return [] }
        let grid = characterColumns(width: width, face: faces[font] ?? faces["5x7"]!)
        guard grid.count > 0 else { return [width] }
        return (1...grid.count).map { $0 == grid.count ? width : min(width, grid.origin + $0 * grid.pitch) }
    }
    private static let registry: Registry = resource("markup_icons")

    /// Model appearance uses six-digit RGB; malformed values use the caller's default.
    public static func hex(_ value: String?) -> UInt32? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 else { return nil }
        return UInt32(value, radix: 16)
    }

    private static func ink(_ code: String) -> UInt32 {
        if ["black", "filled", "70", "71"].contains(code) { return 0 }
        let named = code == "purple" ? "violet" : code
        if let color = BoardColor(rawValue: named) { return hex(color.hex) ?? 0 }
        if let number = Int(code), let color = BoardColor(code: number) { return hex(color.hex) ?? 0 }
        return hex(code) ?? 0
    }

    public static func make(display: MatrixDisplay, cells: [[BoardCell]], richCells: [[MatrixCell]]? = nil, layers: [PixelLayer] = []) -> MatrixRaster {
        let width = display.width, height = display.height
        let face = faces[display.font]!
        let columns = characterColumns(width: width, face: face)
        let pitchX = columns.pitch
        let pitchY = face.glyphHeight + face.spacingY
        let cols = columns.count
        let rows = (height + face.spacingY) / pitchY
        var pixels = [UInt32](repeating: 0, count: width * height)
        let originX = columns.origin
        let originY = (height - (rows * pitchY - face.spacingY)) / 2
        let mono = display.color?.kind == "monochrome" ? hex(display.color?.color) : nil
        struct Cell {
            let token: MatrixCell
            let foreground: UInt32
            let background: UInt32?
        }
        var resolved: [Cell] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let token: MatrixCell
                if let richCells {
                    token = row < richCells.count && col < richCells[row].count
                        ? richCells[row][col] : MatrixCell(type: "char", value: " ")
                } else {
                    let cell: BoardCell = row < cells.count && col < cells[row].count ? cells[row][col] : .blank
                    switch cell {
                    case .blank: token = MatrixCell(type: "char", value: " ")
                    case .character(let glyph): token = MatrixCell(type: "char", value: String(glyph))
                    case .color(let color): token = MatrixCell(type: "color", code: color.rawValue)
                    }
                }
                let background = token.background.map(ink).flatMap { $0 == 0 ? nil : $0 }
                let foreground: UInt32 = mono != nil && background != nil ? 0 : mono ?? token.color.map(ink) ?? 0xffffff
                resolved.append(Cell(token: token, foreground: foreground, background: background.map { mono ?? $0 }))
            }
        }
        func rectangle(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32) {
            for py in y..<min(height, y + h) {
                for px in x..<min(width, x + w) { pixels[py * width + px] = color }
            }
        }
        func glyph(_ token: MatrixCell, _ x: Int, _ y: Int, _ foreground: UInt32) {
            var bitmap: [String]?
            var color = foreground
            if let name = token.icon {
                let canonical = registry.aliases[name] ?? name
                guard let icon = registry.icons[canonical], face.icons[canonical] != nil else {
                    // The wire token supplies the fallback for newer icons or
                    // a font without their bitmap. Its span colors still apply.
                    var fallback = token
                    fallback.icon = nil
                    glyph(fallback, x, y, foreground)
                    return
                }
                bitmap = face.icons[canonical]
                color = mono == nil ? hex(icon.color) ?? foreground : foreground
            } else if token.type == "color" {
                let tile = ink(token.code ?? "black")
                if tile != 0 { rectangle(x, y, face.glyphWidth, face.glyphHeight, mono == nil ? tile : foreground) }
                return
            } else {
                let value = token.value ?? " "
                bitmap = face.glyphs[value]
                if value == "♥", mono == nil { color = 0xeb4034 }
            }
            for (dy, line) in (bitmap ?? []).enumerated() {
                for (dx, pixel) in line.enumerated() where pixel == "#" {
                    if y + dy < height, x + dx < width { pixels[(y + dy) * width + x + dx] = color }
                }
            }
        }
        func readable(_ token: MatrixCell) -> String {
            if let name = token.icon {
                let canonical = registry.aliases[name] ?? name
                if let icon = registry.icons[canonical], face.icons[canonical] != nil { return " \(icon.label) " }
            }
            guard token.type == "char", let value = token.value, face.glyphs[value] != nil else { return " " }
            return value
        }
        var lines: [String] = []
        for row in 0..<rows {
            var line = ""
            for col in 0..<cols {
                let cell = resolved[row * cols + col]
                line += readable(cell.token)
                let x = originX + col * pitchX, y = originY + row * pitchY
                if let background = cell.background {
                    let right = col + 1 < cols && resolved[row * cols + col + 1].background == background
                    let below = row + 1 < rows && resolved[(row + 1) * cols + col].background == background
                    rectangle(x, y, face.glyphWidth + (right ? face.spacingX : 0), face.glyphHeight + (below ? face.spacingY : 0), background)
                }
                glyph(cell.token, x, y, cell.foreground)
            }
            lines.append(line)
        }
        let text = lines.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for layer in layers.prefix(64) {
            // Reject offscreen origins before adding or negating them: even
            // Int.min/Int.max coordinates cannot overflow clipping arithmetic.
            guard layer.w > 0, layer.h > 0, layer.w <= MatrixDisplay.maxPixelDimension, layer.h <= MatrixDisplay.maxPixelDimension,
                  layer.x < width, layer.x > -layer.w,
                  layer.y < height, layer.y > -layer.h else { continue }
            for sy in max(0, -layer.y)..<min(layer.h, height - layer.y) {
                for sx in max(0, -layer.x)..<min(layer.w, width - layer.x) {
                    let offset = (sy * layer.w + sx) * 4
                    guard offset >= 0, offset + 3 < layer.rgba.count, layer.rgba[offset + 3] != 0 else { continue }
                    let r = UInt32(layer.rgba[offset]), g = UInt32(layer.rgba[offset + 1]), b = UInt32(layer.rgba[offset + 2])
                    let color = mono.map { 299 * r + 587 * g + 114 * b >= 127_500 ? $0 : 0 }
                        ?? (r << 16 | g << 8 | b)
                    pixels[(layer.y + sy) * width + layer.x + sx] = color
                }
            }
        }
        return MatrixRaster(width: width, height: height, pixels: pixels, text: text)
    }
}
