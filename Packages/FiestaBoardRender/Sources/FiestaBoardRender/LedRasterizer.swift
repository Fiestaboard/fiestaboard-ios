import Foundation
import SwiftUI

/// An LED frame: RGB888, row-major, with a lit mask.
public struct MatrixRaster: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var rgb: [UInt8]
    public var lit: [Bool]
    public init(width: Int, height: Int) {
        self.width = max(0, width); self.height = max(0, height)
        rgb = Array(repeating: 0, count: self.width * self.height * 3)
        lit = Array(repeating: false, count: self.width * self.height)
    }
    public func pixel(x: Int, y: Int) -> UInt32? {
        guard x >= 0, y >= 0, x < width, y < height, lit[y * width + x] else { return nil }
        let i = (y * width + x) * 3
        return UInt32(rgb[i]) << 16 | UInt32(rgb[i + 1]) << 8 | UInt32(rgb[i + 2])
    }
    mutating func set(x: Int, y: Int, _ color: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 3
        rgb[i] = UInt8((color >> 16) & 0xff); rgb[i + 1] = UInt8((color >> 8) & 0xff); rgb[i + 2] = UInt8(color & 0xff)
        lit[y * width + x] = true
    }
}

/// LED path, **D1 static stub**: glyph bitmaps from `led-fonts.json`, colour
/// tiles as filled glyph rects (black draws nothing), the heart in red,
/// monochrome recolouring and alpha layers. The exact FiestaUI raster
/// (`led-golden.json`, 0 px diff, `tile_gap`/`block_padding` gutters) is
/// iOS-R2's (wave 2); nothing here is golden-verified yet.
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

    public static func raster(_ frame: BoardFrame, model: DisplayModel) -> MatrixRaster {
        guard case .pixels(let width, let height) = model.geometry else { return MatrixRaster(width: 0, height: 0) }
        var raster = MatrixRaster(width: width, height: height)
        guard let font = fonts[model.font.rawValue] else { return raster }
        let rows = model.rows, cols = model.cols
        let blockW = cols * font.glyphW + (cols - 1) * font.spacingX
        let blockH = rows * font.glyphH + (rows - 1) * font.spacingY
        let originX = max(0, (width - blockW) / 2), originY = max(0, (height - blockH) / 2)
        let monochrome: UInt32? = { if case .monochrome(let hex) = model.color { return hex }; return nil }()
        let tokens: [[BoardToken]] = frame.cells
            ?? frame.message.map { BoardMessageParser.cells($0, rows: rows, cols: cols, preserveCase: true) }
            ?? (frame.codes ?? []).map { row in row.map { code in
                if let color = BoardColor(code: code) { _ = color; return .color(code) }
                if case .character(let c) = BoardTables.cell(forCode: code, code62: .heart) { return .char(String(c)) }
                return .char(" ")
            } }
        for (r, row) in tokens.prefix(rows).enumerated() {
            for (c, token) in row.prefix(cols).enumerated() {
                let x0 = originX + c * (font.glyphW + font.spacingX)
                let y0 = originY + r * (font.glyphH + font.spacingY)
                if token.kind == .color, let code = token.code, let color = BoardColor(code: code) {
                    guard color != .black else { continue }
                    let hex = monochrome ?? UInt32(BoardColor.hexValue(color))
                    for y in 0..<font.glyphH { for x in 0..<font.glyphW { raster.set(x: x0 + x, y: y0 + y, hex) } }
                    continue
                }
                let value = token.value ?? " "
                let bitmap = token.icon.flatMap { font.icons[$0] } ?? font.glyphs[value] ?? font.glyphs[value.uppercased()]
                guard let bitmap else { continue }
                let named = token.color.flatMap { BoardMessageParser.named[$0] }.flatMap(BoardColor.init(code:))
                let hex = monochrome ?? (value == "♥" ? FlapPalette.heart : named.map { UInt32(BoardColor.hexValue($0)) } ?? 0xffffff)
                for (y, line) in bitmap.enumerated() {
                    for (x, bit) in line.enumerated() where bit == "#" { raster.set(x: x0 + x, y: y0 + y, hex) }
                }
            }
        }
        for layer in frame.layers {
            for y in 0..<layer.h {
                for x in 0..<layer.w {
                    let i = (y * layer.w + x) * 4
                    guard i + 3 < layer.rgba.count else { continue }
                    let bytes = layer.rgba
                    let alpha = bytes[bytes.startIndex + i + 3]
                    guard alpha > 0 else { continue }
                    let color = UInt32(bytes[bytes.startIndex + i]) << 16 | UInt32(bytes[bytes.startIndex + i + 1]) << 8 | UInt32(bytes[bytes.startIndex + i + 2])
                    raster.set(x: layer.x + x, y: layer.y + y, monochrome ?? color)
                }
            }
        }
        return raster
    }
}

/// Draws a `MatrixRaster` as dots: substrate, off dots, lit dots (FiestaUI
/// `led-matrix-display.js:61-72`, without the glow pass in D1).
public struct MatrixDotsView: View {
    let raster: MatrixRaster
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
                    let shape = appearance.pixelShape == .round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: dot * 0.15)
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
