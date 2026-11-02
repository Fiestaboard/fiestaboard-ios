import Foundation

// Pixel canvases of a legacy template page (PLAN B24, §2.2/§2.4; server `src/canvas/models.py`).
// Every helper works on the retained `LosslessJSON` tree: keys it does not know survive, numbers
// it does not change keep their exact lexemes, and every number it writes is an integer lexeme
// (`FlexibleNumber.draft("12")`), never a `Double`.

/// 1-based character cells of the page grid (`CanvasArea`, `models.py`).
public struct CanvasArea: Equatable, Hashable, Sendable {
    public var row: Int, col: Int, rows: Int, cols: Int
    public init(row: Int, col: Int, rows: Int, cols: Int) { self.row = row; self.col = col; self.rows = rows; self.cols = cols }
    /// The area spanned by two 0-based cells (the web's `areaBetween`).
    public static func between(_ a: (row: Int, col: Int), _ b: (row: Int, col: Int)) -> CanvasArea {
        CanvasArea(row: min(a.row, b.row) + 1, col: min(a.col, b.col) + 1,
                   rows: abs(a.row - b.row) + 1, cols: abs(a.col - b.col) + 1)
    }
    /// Cut to a `rows × cols` grid; nil when it starts outside it (`clamp_area`).
    public func clamped(rows gridRows: Int, cols gridCols: Int) -> CanvasArea? {
        guard row >= 1, col >= 1, row <= gridRows, col <= gridCols, rows >= 1, cols >= 1 else { return nil }
        return CanvasArea(row: row, col: col, rows: min(rows, gridRows - row + 1), cols: min(cols, gridCols - col + 1))
    }
}

public enum CanvasLimits {
    public static let maxCanvases = 8
    public static let maxScale = 8
    public static let maxPaletteKeys = 62
    public static let maxPixels = 128
    public static let maxContentSize = 128
    public static let maxCoordinate = 1024
    public static let paletteKeys = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    public static let bleedSides = ["top", "left", "right", "bottom"]
    /// The LED renderer's board colours (`src/led/matrix.py` `BOARD_COLORS`).
    public static let boardColors: [(name: String, hex: String)] = [
        ("red", "#eb4034"), ("orange", "#f5a623"), ("yellow", "#f8e71c"), ("green", "#7ed321"),
        ("blue", "#4a90d9"), ("violet", "#9b59b6"), ("white", "#ffffff"), ("black", "#1a1a1a"),
    ]
    public static func validID(_ id: String) -> Bool {
        (1...16).contains(id.utf8.count) && id.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 }
    }
}

/// `{{…}}` expression test of the server (`is_expression`).
public func canvasIsExpression(_ value: LosslessJSON?) -> Bool {
    if case .string(let text) = value { return text.contains("{{") && text.contains("}}") }
    return false
}

/// The finite numeric value of a JSON number lexeme (for geometry only; never written back).
public func canvasNumber(_ value: LosslessJSON?) -> Double? {
    if case .number(let lexeme) = value, let number = Double(lexeme), number.isFinite { return number }
    return nil
}

/// An integer lexeme: what every drag, resize and stepper writes (PLAN §2.2 "Numbers (canvas)").
public func canvasInteger(_ value: Int) -> LosslessJSON { FlexibleNumber.draft(String(value)) }

/// One entry of `canvases[]`, edited in place. Unknown keys stay.
public struct LegacyCanvas: Equatable, Sendable {
    public var object: LosslessJSONObject
    public init(_ object: LosslessJSONObject) { self.object = object }
    public init?(_ value: LosslessJSON) { guard case .object(let object) = value else { return nil }; self.object = object }
    public var json: LosslessJSON { .object(object) }

    /// A new canvas over `area`: hides the text under it and draws nothing yet (`makeCanvas`).
    public static func make(id: String, area: CanvasArea) -> LegacyCanvas {
        var canvas = LegacyCanvas(["id": .string(id), "bleed": .array([]), "scale": canvasInteger(1), "text": .string("hide"),
                                   "content": .object(["palette": .object([:]), "shapes": .array([]), "pixels": .array([])])])
        canvas.area = area
        return canvas
    }
    /// The first `canvasN` id not already taken (`nextCanvasId`).
    public static func nextID(_ canvases: [LegacyCanvas]) -> String {
        let taken = Set(canvases.map(\.id))
        var n = 1
        while taken.contains("canvas\(n)") { n += 1 }
        return "canvas\(n)"
    }

    public var id: String {
        get { if case .string(let id) = object["id"] { id } else { "" } }
        set { object["id"] = .string(newValue) }
    }

    /// Nil when the area isn't four whole numbers (an expression or a fraction stays read-only here).
    public var area: CanvasArea? {
        get {
            guard case .object(let area) = object["area"] else { return nil }
            func int(_ key: String) -> Int? { canvasNumber(area[key]).flatMap { $0 == $0.rounded() ? Int(exactly: $0) : nil } }
            guard let row = int("row"), let col = int("col"), let rows = int("rows"), let cols = int("cols") else { return nil }
            return CanvasArea(row: row, col: col, rows: rows, cols: cols)
        }
        set {
            guard let newValue else { return }
            var area: LosslessJSONObject = [:]
            if case .object(let existing) = object["area"] { area = existing }
            for (key, value) in [("row", newValue.row), ("col", newValue.col), ("rows", newValue.rows), ("cols", newValue.cols)] {
                // Keep an unchanged number's own spelling ("2" stays "2", "2.0" stays "2.0").
                if let old = canvasNumber(area[key]), old == Double(value) { continue }
                area[key] = canvasInteger(value)
            }
            object["area"] = .object(area)
        }
    }

    /// Sides that bleed to the panel edge; `["all"]` reads as all four.
    public var bleed: Set<String> {
        get {
            guard case .array(let values) = object["bleed"] else { return [] }
            let sides = Set(values.compactMap { if case .string(let s) = $0 { s } else { nil } })
            return sides.contains("all") ? Set(CanvasLimits.bleedSides) : sides
        }
        set {
            let sides = CanvasLimits.bleedSides.filter(newValue.contains)
            object["bleed"] = .array(sides.count == 4 ? [.string("all")] : sides.map(LosslessJSON.string))
        }
    }

    public var scale: Int {
        get { canvasNumber(object["scale"]).flatMap { Int(exactly: $0) } ?? 1 }
        set {
            let value = min(CanvasLimits.maxScale, max(1, newValue))
            if canvasNumber(object["scale"]) == Double(value) { return }
            object["scale"] = canvasInteger(value)
        }
    }

    /// `"hide"` or `"flow"` (text under the canvas).
    public var textMode: String {
        get { if case .string(let mode) = object["text"] { mode } else { "hide" } }
        set { object["text"] = .string(newValue == "flow" ? "flow" : "hide") }
    }

    public var source: String? { if case .string(let source) = object["source"] { source } else { nil } }

    public var content: LosslessJSONObject? {
        get { if case .object(let content) = object["content"] { content } else { nil } }
        set { object["content"] = newValue.map(LosslessJSON.object) ?? .null }
    }

    /// `content.size` when it is two whole numbers.
    public var contentSize: (width: Int, height: Int)? {
        guard case .array(let size) = content?["size"], size.count == 2,
              let w = canvasNumber(size[0]).flatMap({ Int(exactly: $0) }), let h = canvasNumber(size[1]).flatMap({ Int(exactly: $0) }) else { return nil }
        return (w, h)
    }

    public var shapes: [LosslessJSON] {
        get { if case .array(let shapes) = content?["shapes"] { shapes } else { [] } }
        set { var c = content ?? [:]; c["shapes"] = .array(newValue); content = c }
    }
    public var palette: LosslessJSONObject {
        if case .object(let palette) = content?["palette"] { palette } else { [:] }
    }
    public var pixels: [String] {
        guard case .array(let rows) = content?["pixels"] else { return [] }
        return rows.compactMap { if case .string(let row) = $0 { row } else { nil } }
    }
}

extension PageDocument {
    /// `canvases[]` of a legacy page; empty when absent or `null`.
    public var legacyCanvases: [LegacyCanvas] {
        guard case .array(let values) = root["canvases"] else { return [] }
        return values.compactMap(LegacyCanvas.init)
    }
    /// The canvases can be edited only when they are absent, `null` or an array of objects.
    public var canvasesAreEditable: Bool {
        guard pageType == "template", editableTemplateLines != nil else { return false }
        switch root["canvases"] {
        case nil, .null: return true
        case .array(let values): return values.allSatisfy { if case .object = $0 { true } else { false } }
        default: return false
        }
    }

    /// Replaces `canvases` on a legacy (v1) page (PLAN §2.4). The value must be `null` or an array of
    /// objects; it is stored exactly as given, so unknown canvas and shape keys survive. Writing an
    /// empty list over an absent/`null` member keeps it absent/`null` (nothing changed).
    public mutating func setCanvases(_ value: LosslessJSON) throws {
        guard canvasesAreEditable else { throw DocumentError.unsupportedTemplate }
        switch value {
        case .null: break
        case .array(let values):
            guard values.count <= CanvasLimits.maxCanvases,
                  values.allSatisfy({ if case .object = $0 { true } else { false } }) else { throw DocumentError.unsupportedTemplate }
            if values.isEmpty, root["canvases"] == nil || root["canvases"] == .null { return }
        default: throw DocumentError.unsupportedTemplate
        }
        root["canvases"] = value
    }
    public mutating func setCanvases(_ canvases: [LegacyCanvas]) throws {
        try setCanvases(.array(canvases.map(\.json)))
    }
}

extension PageDocument {
    /// What would make the server refuse these canvases outright (`validate_page_canvases`'s
    /// structural rules: id, area, something to draw, unique ids, at most 8). Content details are
    /// left to the server, whose message the preview shows.
    public var canvasProblems: [String] {
        guard canvasesAreEditable else { return ["The canvases have a shape this editor can't save."] }
        let canvases = legacyCanvases
        var problems: [String] = []
        if canvases.count > CanvasLimits.maxCanvases { problems.append("A page holds at most \(CanvasLimits.maxCanvases) canvases.") }
        var seen = Set<String>()
        for (index, canvas) in canvases.enumerated() {
            let name = canvas.id.isEmpty ? "Canvas \(index + 1)" : "Canvas \(canvas.id)"
            if !CanvasLimits.validID(canvas.id) { problems.append("\(name): the ID must be 1–16 lowercase letters, digits, - or _.") }
            else if !seen.insert(canvas.id).inserted { problems.append("\(name): the ID is used twice.") }
            if let area = canvas.area {
                if area.row < 1 || area.col < 1 || area.rows < 1 || area.cols < 1 { problems.append("\(name): the area starts at row 1, column 1 and is at least 1 × 1.") }
            } else { problems.append("\(name): the area needs whole numbers for row, column, rows and columns.") }
            if canvas.content == nil && canvas.source == nil { problems.append("\(name) needs content or a source.") }
        }
        return problems
    }
}
