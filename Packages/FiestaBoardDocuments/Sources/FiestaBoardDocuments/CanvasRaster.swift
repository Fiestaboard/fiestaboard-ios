import Foundation

/// An RGBA colour; nil wherever a colour may be is "transparent".
public struct CanvasRGBA: Equatable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    /// `#rgb`, `#rrggbb`, a board colour name, or a palette key (`parse_color`). Nil for transparent,
    /// expressions and anything unparseable.
    public static func parse(_ value: String?, palette: LosslessJSONObject = [:]) -> CanvasRGBA? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty, !raw.contains("{{") else { return nil }
        if raw.count == 1, case .string(let entry) = palette[raw] { return parse(entry) }
        let lower = raw.lowercased()
        if ["none", "transparent", "."].contains(lower) { return nil }
        if let named = CanvasLimits.boardColors.first(where: { $0.name == lower }) { return parse(named.hex) }
        guard lower.hasPrefix("#") else { return nil }
        let digits = Array(lower.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        func byte(_ s: String) -> UInt8 { UInt8(s, radix: 16) ?? 0 }
        if digits.count == 6 { return CanvasRGBA(byte(String(digits[0...1])), byte(String(digits[2...3])), byte(String(digits[4...5]))) }
        if digits.count == 3 { return CanvasRGBA(byte(String([digits[0], digits[0]])), byte(String([digits[1], digits[1]])), byte(String([digits[2], digits[2]]))) }
        return nil
    }
}

/// `content.pixels` + `palette` as a colour grid and back (web `decodePixels` / `encodePixels`).
public enum CanvasPixels {
    public typealias Grid = [[CanvasRGBA?]]

    public static func decode(_ canvas: LegacyCanvas, width: Int, height: Int) -> Grid {
        let palette = canvas.palette
        var resolved: [Character: CanvasRGBA] = [:]
        for (key, value) in palette { if let k = key.first, key.count == 1, case .string(let s) = value, let c = CanvasRGBA.parse(s) { resolved[k] = c } }
        let rows = canvas.pixels.map(Array.init)
        return (0..<height).map { y in
            (0..<width).map { x in
                guard y < rows.count, x < rows[y].count, rows[y][x] != "." else { return nil }
                return resolved[rows[y][x]]
            }
        }
    }

    public enum EncodeError: Error, Equatable { case tooManyColors }

    /// One key per colour (an existing key keeps the colour it meant), `.` transparent; palette keys
    /// that no pixel, background or shape refers to are dropped. Writes `size`, `palette`, `pixels`
    /// only; every other content key stays.
    public static func encode(_ grid: Grid, into canvas: inout LegacyCanvas) throws {
        var content = canvas.content ?? [:]
        let previous = canvas.palette
        // Colours other layers name by key (shapes, background); expressions may name any key.
        var references: [String] = []
        if case .string(let background) = content["background"] { references.append(background) }
        for shape in canvas.shapes { if case .object(let o) = shape { for (_, v) in o { if case .string(let s) = v { references.append(s) } } } }
        let dynamic = references.contains { $0.contains("{{") }
        var palette = previous.filter { key, _ in dynamic || references.contains(key) }
        var keyOf: [CanvasRGBA: String] = [:]
        for key in previous.keys.sorted() { if case .string(let s) = previous[key], let c = CanvasRGBA.parse(s), keyOf[c] == nil { keyOf[c] = key } }
        var colors: [CanvasRGBA] = []
        var seen = Set<CanvasRGBA>()
        for row in grid { for c in row { if let c, seen.insert(c).inserted { colors.append(c) } } }
        guard colors.count <= CanvasLimits.maxPaletteKeys else { throw EncodeError.tooManyColors }
        var used: [CanvasRGBA: String] = [:]
        var usedKeys = Set(palette.keys)
        for c in colors { if let kept = keyOf[c] { used[c] = kept; usedKeys.insert(kept) } }
        var free = CanvasLimits.paletteKeys.map(String.init).filter { !usedKeys.contains($0) }
        for c in colors where used[c] == nil {
            guard !free.isEmpty else { throw EncodeError.tooManyColors }
            let key = free.removeFirst(); used[c] = key; usedKeys.insert(key)
        }
        for (c, key) in used where palette[key] == nil { palette[key] = previous[key] ?? .string(c.hex) }
        content["palette"] = .object(palette)
        content["pixels"] = .array(colors.isEmpty ? [] : grid.map { row in .string(String(row.map { $0.flatMap { used[$0] }?.first ?? "." })) })
        if canvas.contentSize == nil {
            let height = grid.count, width = grid.first?.count ?? 0
            content["size"] = .array([canvasInteger(width), canvasInteger(height)])
        }
        canvas.content = content
    }
}

/// A pixel-matrix board as the canvas geometry needs it (web `PixelBoard`).
public struct CanvasBoard: Equatable, Sendable {
    public var width: Int, height: Int
    /// Glyph box of the board's LED font (3×5 or 5×7); the gutters are one pixel.
    public var glyphWidth: Int, glyphHeight: Int
    public var spacing: Int = 1
    public init(width: Int, height: Int, glyphWidth: Int, glyphHeight: Int) {
        self.width = width; self.height = height; self.glyphWidth = glyphWidth; self.glyphHeight = glyphHeight
    }
    public var font: String { glyphWidth == 3 ? "3x5" : "5x7" }
    public var cols: Int { max(1, (width + spacing) / (glyphWidth + spacing)) }
    public var rows: Int { max(1, (height + spacing) / (glyphHeight + spacing)) }
    public var originX: Int { (width - (cols * (glyphWidth + spacing) - spacing)) / 2 }
    public var originY: Int { (height - (rows * (glyphHeight + spacing) - spacing)) / 2 }
}

/// Where a canvas draws on the panel (`src/canvas/geometry.py` `canvas_placement`).
public struct CanvasPlacement: Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int, scale: Int
    public static func of(_ canvas: LegacyCanvas, board: CanvasBoard) -> CanvasPlacement? {
        guard let area = canvas.area?.clamped(rows: board.rows, cols: board.cols) else { return nil }
        let sx = board.spacing, sy = board.spacing
        let px = board.glyphWidth + sx, py = board.glyphHeight + sy
        var x0 = board.originX + (area.col - 1) * px, y0 = board.originY + (area.row - 1) * py
        var x1 = board.originX + (area.col - 1 + area.cols) * px - sx, y1 = board.originY + (area.row - 1 + area.rows) * py - sy
        let sides = canvas.bleed
        if sides.contains("left"), area.col == 1 { x0 = 0 }
        if sides.contains("top"), area.row == 1 { y0 = 0 }
        if sides.contains("right"), area.col - 1 + area.cols == board.cols { x1 = board.width }
        if sides.contains("bottom"), area.row - 1 + area.rows == board.rows { y1 = board.height }
        let scale = canvas.scale
        let w = (x1 - x0) / scale, h = (y1 - y0) / scale
        guard w >= 1, h >= 1 else { return nil }
        return CanvasPlacement(x: x0 + ((x1 - x0) - w * scale) / 2, y: y0 + ((y1 - y0) - h * scale) / 2, width: w, height: h, scale: scale)
    }
}

/// A straight-alpha RGBA bitmap at panel pixel (x, y) (the server's `CanvasLayer`).
public struct CanvasBitmap: Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int
    public var rgba: [UInt8]
}

/// The editor's own drawing of a canvas (a port of `src/canvas/raster.py` for the literal parts):
/// background, rect/circle/ellipse/line/text/polygon shapes and `pixels`, at the content's `size`,
/// fitted nearest-neighbour into the placement. A shape whose fields hold expressions, and
/// gradients, are left to the server's render (the stage shows the server's layers when they
/// are current). Pure and deterministic, so the stage can redraw on every drag step.
public enum CanvasRaster {
    /// LED font bitmaps by font id and character (`#` = lit), provided by the renderer.
    public typealias Glyphs = @Sendable (_ font: String, _ character: Character) -> [String]?

    public static func layers(_ canvases: [LegacyCanvas], board: CanvasBoard, glyphs: Glyphs? = nil) -> [CanvasBitmap] {
        canvases.compactMap { canvas in
            guard let placement = CanvasPlacement.of(canvas, board: board) else { return nil }
            let fitted = render(canvas, width: placement.width, height: placement.height, glyphs: glyphs)
            let scale = placement.scale
            var out = [UInt8](repeating: 0, count: placement.width * scale * placement.height * scale * 4)
            let outW = placement.width * scale
            for y in 0..<(placement.height * scale) {
                for x in 0..<outW {
                    let s = ((y / scale) * placement.width + x / scale) * 4, d = (y * outW + x) * 4
                    out[d] = fitted[s]; out[d + 1] = fitted[s + 1]; out[d + 2] = fitted[s + 2]; out[d + 3] = fitted[s + 3]
                }
            }
            return CanvasBitmap(x: placement.x, y: placement.y, width: outW, height: placement.height * scale, rgba: out)
        }
    }

    /// The canvas content drawn at its `size` (default `width × height`), fitted into `width × height`.
    public static func render(_ canvas: LegacyCanvas, width: Int, height: Int, glyphs: Glyphs? = nil) -> [UInt8] {
        let size = canvas.contentSize.map { (max(1, min(CanvasLimits.maxContentSize, $0.width)), max(1, min(CanvasLimits.maxContentSize, $0.height))) } ?? (width, height)
        let src = rasterize(canvas, width: size.0, height: size.1, glyphs: glyphs)
        return fit(src, size.0, size.1, width, height)
    }

    /// The content at its own size (`rasterize`).
    public static func rasterize(_ canvas: LegacyCanvas, width: Int, height: Int, glyphs: Glyphs? = nil) -> [UInt8] {
        var s = Surface(w: width, h: height)
        let palette = canvas.palette
        if case .string(let bg) = canvas.content?["background"], let c = CanvasRGBA.parse(bg, palette: palette) {
            for row in 0..<height { s.span(row, 0, width, c) }
        }
        for value in canvas.shapes {
            guard let shape = CanvasShape(value), !shape.hasExpression else { continue }
            draw(shape, on: &s, palette: palette, glyphs: glyphs)
        }
        let grid = CanvasPixels.decode(canvas, width: width, height: height)
        for (y, row) in grid.enumerated() { for (x, c) in row.enumerated() { if let c { s.plot(x, y, c) } } }
        return s.buf
    }

    static func fit(_ rgba: [UInt8], _ sw: Int, _ sh: Int, _ dw: Int, _ dh: Int) -> [UInt8] {
        if sw == dw && sh == dh { return rgba }
        let (fw, fh) = dw * sh <= dh * sw ? (dw, max(1, sh * dw / sw)) : (max(1, sw * dh / sh), dh)
        let ox = (dw - fw) / 2, oy = (dh - fh) / 2
        var out = [UInt8](repeating: 0, count: dw * dh * 4)
        for y in 0..<fh {
            let sy = y * sh / fh
            for x in 0..<fw {
                let sx = x * sw / fw, s = (sy * sw + sx) * 4, d = ((oy + y) * dw + ox + x) * 4
                out[d] = rgba[s]; out[d + 1] = rgba[s + 1]; out[d + 2] = rgba[s + 2]; out[d + 3] = rgba[s + 3]
            }
        }
        return out
    }

    struct Surface {
        let w: Int, h: Int
        var buf: [UInt8]
        init(w: Int, h: Int) { self.w = w; self.h = h; buf = [UInt8](repeating: 0, count: w * h * 4) }
        mutating func plot(_ x: Int, _ y: Int, _ c: CanvasRGBA) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let o = (y * w + x) * 4
            buf[o] = c.r; buf[o + 1] = c.g; buf[o + 2] = c.b; buf[o + 3] = c.a
        }
        mutating func span(_ y: Int, _ x0: Int, _ x1: Int, _ c: CanvasRGBA) {
            guard y >= 0, y < h else { return }
            for x in max(0, x0)..<max(max(0, x0), min(x1, w)) { plot(x, y, c) }
        }
    }

    private static func rhu(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    private static func draw(_ shape: CanvasShape, on s: inout Surface, palette: LosslessJSONObject, glyphs: Glyphs?) {
        func n(_ k: String) -> Double? { shape.number(k) }
        func color(_ k: String) -> CanvasRGBA? { if case .string(let v) = shape.object[k] { CanvasRGBA.parse(v, palette: palette) } else { nil } }
        switch shape.kind {
        case .rect:
            guard var x = n("x"), var y = n("y"), var w = n("w"), var h = n("h") else { return }
            if w < 0 { x += w; w = -w }; if h < 0 { y += h; h = -h }
            let x0 = rhu(x), x1 = rhu(x + w), y0 = rhu(y), y1 = rhu(y + h)
            guard x1 > x0, y1 > y0 else { return }
            if let fill = color("fill") { for row in max(y0, 0)..<max(max(y0, 0), min(y1, s.h)) { s.span(row, x0, x1, fill) } }
            if let stroke = color("stroke") {
                s.span(y0, x0, x1, stroke); if y1 - 1 != y0 { s.span(y1 - 1, x0, x1, stroke) }
                if y1 - 1 > y0 + 1 { for row in (y0 + 1)..<(y1 - 1) { s.span(row, x0, x0 + 1, stroke); if x1 - 1 != x0 { s.span(row, x1 - 1, x1, stroke) } } }
            }
        case .circle:
            guard let cx = n("cx"), let cy = n("cy"), let r = n("r") else { return }
            ellipse(&s, cx, cy, r, r, color("fill"), color("stroke"))
        case .ellipse:
            guard let cx = n("cx"), let cy = n("cy"), let rx = n("rx"), let ry = n("ry") else { return }
            ellipse(&s, cx, cy, rx, ry, color("fill"), color("stroke"))
        case .line:
            guard let x1 = n("x1"), let y1 = n("y1"), let x2 = n("x2"), let y2 = n("y2"), let c = color("stroke") else { return }
            line(&s, x1, y1, x2, y2, c, width: n("width") ?? 1)
        case .text:
            guard let x = n("x"), let y = n("y"), let c = color("color"), let glyphs else { return }
            let font = shape.text("font") == "3x5" ? "3x5" : "5x7"
            let (gw, gh) = font == "3x5" ? (3, 5) : (5, 7)
            let left = rhu(x); var px = left, py = rhu(y)
            for ch in shape.text("text") {
                if ch == "\n" { px = left; py += gh + 1; continue }
                if let rows = glyphs(font, ch) {
                    for (dy, bits) in rows.enumerated() { for (dx, bit) in bits.enumerated() where bit == "#" { s.plot(px + dx, py + dy, c) } }
                }
                px += gw + 1
            }
        case .preserved(let type):
            guard type == "polygon", case .array(let raw) = shape.object["points"] else { return }
            let points = raw.compactMap { p -> (Double, Double)? in
                guard case .array(let pair) = p, pair.count == 2, let x = canvasNumber(pair[0]), let y = canvasNumber(pair[1]) else { return nil }
                return (x, y)
            }
            guard points.count == raw.count, points.count >= 3 else { return }
            polygon(&s, points, color("fill"), color("stroke"))
        }
    }

    private static func ellipseSpan(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ row: Int) -> (Int, Int)? {
        guard rx > 0, ry > 0 else { return nil }
        let dy = Double(row) + 0.5 - cy, lim = rx * rx * ry * ry, dyTerm = dy * dy * rx * rx
        guard dyTerm <= lim else { return nil }
        func inside(_ i: Int) -> Bool { let dx = Double(i) + 0.5 - cx; return dx * dx * ry * ry + dyTerm <= lim }
        let half = rx * max(0, 1 - (dy * dy) / (ry * ry)).squareRoot()
        var i0 = Int((cx - half - 0.5).rounded(.up)), i1 = Int((cx + half - 0.5).rounded(.down))
        while inside(i0 - 1) { i0 -= 1 }
        while i0 <= i1 && !inside(i0) { i0 += 1 }
        while inside(i1 + 1) { i1 += 1 }
        while i1 >= i0 && !inside(i1) { i1 -= 1 }
        return i0 <= i1 ? (i0, i1) : nil
    }
    private static func ellipse(_ s: inout Surface, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ fill: CanvasRGBA?, _ stroke: CanvasRGBA?) {
        let rx = abs(rx), ry = abs(ry)
        let top = max(0, Int((cy - ry).rounded(.down)) - 1), bottom = min(s.h, Int((cy + ry).rounded(.up)) + 1)
        guard top < bottom else { return }
        for row in top..<bottom {
            guard let outer = ellipseSpan(cx, cy, rx, ry, row) else { continue }
            if let fill { s.span(row, outer.0, outer.1 + 1, fill) }
            if let stroke {
                if let inner = ellipseSpan(cx, cy, rx - 1, ry - 1, row) {
                    s.span(row, outer.0, inner.0, stroke); s.span(row, inner.1 + 1, outer.1 + 1, stroke)
                } else { s.span(row, outer.0, outer.1 + 1, stroke) }
            }
        }
    }
    private static func line(_ s: inout Surface, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: CanvasRGBA, width: Double = 1) {
        var a = (Int(x0.rounded(.down)), Int(y0.rounded(.down))), b = (Int(x1.rounded(.down)), Int(y1.rounded(.down)))
        if a > b { swap(&a, &b) }
        var (x, y) = a; let (xe, ye) = b
        let n = max(1, rhu(width)), back = (n - 1) / 2
        let dx = abs(xe - x), dy = -abs(ye - y), stepX = x < xe ? 1 : -1, stepY = y < ye ? 1 : -1
        var err = dx + dy
        while true {
            if n == 1 { s.plot(x, y, c) } else { for row in (y - back)..<(y - back + n) { s.span(row, x - back, x - back + n, c) } }
            if x == xe && y == ye { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += stepX }
            if e2 <= dx { err += dx; y += stepY }
        }
    }
    private static func polygon(_ s: inout Surface, _ points: [(Double, Double)], _ fill: CanvasRGBA?, _ stroke: CanvasRGBA?) {
        let edges = zip(points, points.dropFirst() + [points[0]]).map { ($0, $1) }
        if let fill, let minY = points.map(\.1).min(), let maxY = points.map(\.1).max() {
            let top = max(0, Int(minY.rounded(.down))), bottom = min(s.h, Int(maxY.rounded(.up)) + 1)
            if top < bottom {
                for row in top..<bottom {
                    let yc = Double(row) + 0.5
                    var xs: [Double] = []
                    for ((ax, ay), (bx, by)) in edges where (ay <= yc && yc < by) || (by <= yc && yc < ay) {
                        xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
                    }
                    xs.sort()
                    var k = 0
                    while k + 1 < xs.count { s.span(row, Int((xs[k] - 0.5).rounded(.up)), Int((xs[k + 1] - 0.5).rounded(.up)), fill); k += 2 }
                }
            }
        }
        if let stroke { for ((ax, ay), (bx, by)) in edges { line(&s, ax, ay, bx, by, stroke) } }
    }

    /// 0-based (row, col) cells under `hide` canvases, clamped to the grid: text there is blanked.
    public static func hiddenCells(_ canvases: [LegacyCanvas], rows: Int, cols: Int) -> Set<[Int]> {
        var cells = Set<[Int]>()
        for canvas in canvases where canvas.textMode == "hide" {
            guard let area = canvas.area?.clamped(rows: rows, cols: cols) else { continue }
            for r in (area.row - 1)..<(area.row - 1 + area.rows) { for c in (area.col - 1)..<(area.col - 1 + area.cols) { cells.insert([r, c]) } }
        }
        return cells
    }
}
