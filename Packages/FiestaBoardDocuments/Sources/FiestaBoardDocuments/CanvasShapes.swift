import Foundation

/// A shape of `content.shapes[]` as the Shapes tab edits it (PLAN B24). Rectangles, circles,
/// ellipses, lines and text can be dragged and resized; gradients, polygons and unknown types are
/// "preserved": drawn as a hatched overlay and edited only through the numeric inspector.
public struct CanvasShape: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case rect, circle, ellipse, line, text, preserved(String) }
    public enum Handle: String, CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight, start, end, radius }
    /// A rectangle in content pixels (may extend past the content).
    public struct Box: Equatable, Sendable {
        public var x: Double, y: Double, w: Double, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    }
    public struct Field: Equatable, Sendable {
        public enum Kind: Sendable { case number, color, text }
        public let name: String, kind: Kind, required: Bool
    }

    public var object: LosslessJSONObject
    public init(_ object: LosslessJSONObject) { self.object = object }
    public init?(_ value: LosslessJSON) { guard case .object(let object) = value else { return nil }; self.object = object }
    public var json: LosslessJSON { .object(object) }

    public var type: String { if case .string(let type) = object["type"] { type } else { "" } }
    public var kind: Kind {
        switch type {
        case "rect": .rect
        case "circle": .circle
        case "ellipse": .ellipse
        case "line": .line
        case "text": .text
        default: .preserved(type)
        }
    }
    public var isPreserved: Bool { if case .preserved = kind { true } else { false } }

    /// Each type's own fields, required first (`src/canvas/models.py`, web `SHAPE_FIELDS`).
    public static func fields(_ type: String) -> [Field] {
        func n(_ name: String, _ required: Bool = true) -> Field { Field(name: name, kind: .number, required: required) }
        func c(_ name: String, _ required: Bool = false) -> Field { Field(name: name, kind: .color, required: required) }
        func t(_ name: String, _ required: Bool = true) -> Field { Field(name: name, kind: .text, required: required) }
        switch type {
        case "rect": return [n("x"), n("y"), n("w"), n("h"), c("fill"), c("stroke")]
        case "circle": return [n("cx"), n("cy"), n("r"), c("fill"), c("stroke")]
        case "ellipse": return [n("cx"), n("cy"), n("rx"), n("ry"), c("fill"), c("stroke")]
        case "line": return [n("x1"), n("y1"), n("x2"), n("y2"), c("stroke", true), n("width", false)]
        case "polygon": return [t("points"), c("fill"), c("stroke")]
        case "text": return [n("x"), n("y"), t("text"), c("color", true), t("font", false)]
        case "gradient": return [c("from", true), c("to", true), n("angle", false), n("x", false), n("y", false), n("w", false), n("h", false)]
        default: return []
        }
    }
    public static let addableTypes = ["rect", "circle", "ellipse", "line", "text"]

    /// A new shape with starting values (web `defaultShape`), placed inside a `size` content.
    public static func make(_ type: String, size: (width: Int, height: Int)) -> CanvasShape {
        let w = max(2, size.width), h = max(2, size.height)
        let cx = w / 2, cy = h / 2, s = max(2, min(w, h) / 3)
        func i(_ v: Int) -> LosslessJSON { canvasInteger(v) }
        switch type {
        case "circle": return CanvasShape(["type": .string(type), "cx": i(cx), "cy": i(cy), "r": i(max(1, s / 2)), "fill": .string("yellow")])
        case "ellipse": return CanvasShape(["type": .string(type), "cx": i(cx), "cy": i(cy), "rx": i(s), "ry": i(max(1, s / 2)), "fill": .string("blue")])
        case "line": return CanvasShape(["type": .string(type), "x1": i(1), "y1": i(1), "x2": i(w - 2), "y2": i(h - 2), "stroke": .string("white")])
        case "text": return CanvasShape(["type": .string(type), "x": i(1), "y": i(1), "text": .string("HI"), "color": .string("white"), "font": .string("3x5")])
        default: return CanvasShape(["type": .string("rect"), "x": i(max(0, cx - s / 2)), "y": i(max(0, cy - s / 2)), "w": i(s), "h": i(s), "fill": .string("red")])
        }
    }

    // MARK: Values

    public func isExpression(_ key: String) -> Bool { canvasIsExpression(object[key]) }
    public func number(_ key: String) -> Double? { canvasNumber(object[key]) }
    /// Inspector text for a field: a number's own lexeme, a string as is.
    public func text(_ key: String) -> String { FlexibleNumber.display(object[key]) }

    /// Writes `value` as an integer lexeme unless the field holds an expression (that axis is
    /// locked) or already has that value (its own spelling stays).
    @discardableResult
    public mutating func setInteger(_ key: String, _ value: Int) -> Bool {
        guard !isExpression(key) else { return false }
        let clamped = min(CanvasLimits.maxCoordinate, max(-CanvasLimits.maxCoordinate, value))
        if number(key) == Double(clamped) { return true }
        object[key] = canvasInteger(clamped)
        return true
    }
    /// The numeric inspector's write: numbers through `FlexibleNumber.draft` (an unfinished entry
    /// stays a string the server will name), colours and text verbatim, empty removes the key.
    public mutating func setField(_ key: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { object[key] = nil; return }
        if key == "if", trimmed == "true" || trimmed == "false" { object[key] = .bool(trimmed == "true"); return }
        let numeric = Self.fields(type).first(where: { $0.name == key })?.kind == .number
        object[key] = numeric && !canvasIsExpression(.string(trimmed)) ? FlexibleNumber.draft(trimmed) : .string(text)
    }

    // MARK: Geometry

    /// The fields a move writes, per axis: (x fields, y fields).
    private var moveFields: (x: [String], y: [String]) {
        switch kind {
        case .rect, .text: (["x"], ["y"])
        case .circle, .ellipse: (["cx"], ["cy"])
        case .line: (["x1", "x2"], ["y1", "y2"])
        case .preserved: ([], [])
        }
    }
    /// An axis is locked when a field it moves holds a `{{…}}` expression (PLAN B24).
    public var lockedX: Bool { isPreserved || moveFields.x.contains(where: isExpression) }
    public var lockedY: Bool { isPreserved || moveFields.y.contains(where: isExpression) }
    public var hasExpression: Bool { object.contains { canvasIsExpression($0.value) } }

    /// Bounds in content pixels for the overlay; nil when a needed field isn't a number.
    /// `glyph` = (width, height, spacing) of the text font.
    public func bounds(glyph: (w: Int, h: Int)? = nil) -> Box? {
        func v(_ key: String) -> Double? { number(key) }
        switch kind {
        case .rect:
            guard var x = v("x"), var y = v("y"), var w = v("w"), var h = v("h") else { return nil }
            if w < 0 { x += w; w = -w }; if h < 0 { y += h; h = -h }
            return Box(x: x, y: y, w: w, h: h)
        case .circle:
            guard let cx = v("cx"), let cy = v("cy"), let r = v("r") else { return nil }
            return Box(x: cx - abs(r), y: cy - abs(r), w: 2 * abs(r), h: 2 * abs(r))
        case .ellipse:
            guard let cx = v("cx"), let cy = v("cy"), let rx = v("rx"), let ry = v("ry") else { return nil }
            return Box(x: cx - abs(rx), y: cy - abs(ry), w: 2 * abs(rx), h: 2 * abs(ry))
        case .line:
            guard let x1 = v("x1"), let y1 = v("y1"), let x2 = v("x2"), let y2 = v("y2") else { return nil }
            return Box(x: min(x1, x2), y: min(y1, y2), w: abs(x2 - x1) + 1, h: abs(y2 - y1) + 1)
        case .text:
            guard let x = v("x"), let y = v("y") else { return nil }
            let font = text("font") == "3x5" ? (w: 3, h: 5) : (w: 5, h: 7)
            let g = glyph ?? font
            let lines = text("text").components(separatedBy: "\n")
            let longest = lines.map(\.count).max() ?? 0
            return Box(x: x, y: y, w: Double(max(1, longest * (g.w + 1) - 1)), h: Double(max(1, lines.count * (g.h + 1) - 1)))
        case .preserved:
            // A gradient without a rect covers the whole content; the caller supplies that.
            if type == "gradient", let x = v("x"), let y = v("y"), let w = v("w"), let h = v("h") { return Box(x: x, y: y, w: w, h: h) }
            if type == "polygon", case .array(let points) = object["points"] {
                let xy = points.compactMap { p -> (Double, Double)? in
                    guard case .array(let pair) = p, pair.count == 2, let x = canvasNumber(pair[0]), let y = canvasNumber(pair[1]) else { return nil }
                    return (x, y)
                }
                guard xy.count == points.count, let minX = xy.map(\.0).min(), let maxX = xy.map(\.0).max(),
                      let minY = xy.map(\.1).min(), let maxY = xy.map(\.1).max() else { return nil }
                return Box(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
            }
            return nil
        }
    }

    /// The handles a shape offers (none when preserved or when every field it moves is locked).
    public var handles: [Handle] {
        switch kind {
        case .rect, .ellipse: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .circle: [.radius]
        case .line: [.start, .end]
        case .text, .preserved: []
        }
    }

    /// `self` translated by (dx, dy) content pixels from `origin` (the shape when the drag began),
    /// snapped to whole pixels. Locked axes don't move. Integer lexemes only.
    public static func moved(_ origin: CanvasShape, dx: Double, dy: Double) -> CanvasShape {
        var shape = origin
        let fields = origin.moveFields
        let ix = Int(dx.rounded()), iy = Int(dy.rounded())
        if !origin.lockedX { for key in fields.x { if let v = origin.number(key) { shape.setInteger(key, Int(v.rounded()) + ix) } } }
        if !origin.lockedY { for key in fields.y { if let v = origin.number(key) { shape.setInteger(key, Int(v.rounded()) + iy) } } }
        return shape
    }

    /// `origin` with `handle` dragged to the content point (px, py), snapped to whole pixels.
    /// A field holding an expression is never written.
    public static func resized(_ origin: CanvasShape, handle: Handle, to px: Double, _ py: Double) -> CanvasShape {
        var shape = origin
        let x = Int(px.rounded()), y = Int(py.rounded())
        switch (origin.kind, handle) {
        case (.rect, _):
            // Each axis on its own: an expression (or missing number) on one axis locks only that axis.
            func axis(_ start: String, _ length: String, to target: Int, leading: Bool) {
                guard var a = origin.number(start), var l = origin.number(length) else { return }
                if l < 0 { a += l; l = -l }
                var lo = Int(a.rounded()), hi = Int((a + l).rounded())
                if leading { lo = min(target, hi - 1) } else { hi = max(target, lo + 1) }
                shape.setInteger(start, lo); shape.setInteger(length, hi - lo)
            }
            axis("x", "w", to: x, leading: handle == .topLeft || handle == .bottomLeft)
            axis("y", "h", to: y, leading: handle == .topLeft || handle == .topRight)
        case (.ellipse, _):
            guard let cx = origin.number("cx"), let cy = origin.number("cy") else { return origin }
            shape.setInteger("rx", max(1, Int(abs(px - cx).rounded())))
            shape.setInteger("ry", max(1, Int(abs(py - cy).rounded())))
        case (.circle, _):
            guard let cx = origin.number("cx"), let cy = origin.number("cy") else { return origin }
            shape.setInteger("r", max(1, Int(((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot().rounded())))
        case (.line, .start):
            shape.setInteger("x1", x); shape.setInteger("y1", y)
        case (.line, .end):
            shape.setInteger("x2", x); shape.setInteger("y2", y)
        default: break
        }
        return shape
    }
}
