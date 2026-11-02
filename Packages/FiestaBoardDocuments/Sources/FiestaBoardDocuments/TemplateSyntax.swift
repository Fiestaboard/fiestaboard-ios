import Foundation

/// Lexical authoring projection, never a template evaluator. Every fragment retains its
/// exact source, including spelling, whitespace, filters and scalar-distinct Unicode.
public enum TemplateSyntax {
    public enum Kind: String, Sendable { case text, tile, fill, expression, formula, span, icon }
    public struct Fragment: Equatable, Sendable {
        public let source: String
        public let kind: Kind
        public var label: String {
            guard kind != .text else { return source }
            let inner = source.hasPrefix("{{") ? String(source.dropFirst(2).dropLast(2)) : String(source.dropFirst().dropLast())
            if kind == .fill { return inner == "fill_space" ? "Flexible space" : inner }
            return inner
        }
        public var displayLength: Int { kind == .text ? source.utf16.count : 1 }
    }
    public static let tileColors = ["red", "orange", "yellow", "green", "blue", "violet", "purple", "white", "black", "filled"]

    public static func fragments(_ source: String) -> [Fragment] {
        var result: [Fragment] = []
        var cursor = source.startIndex
        var textStart = cursor
        func appendText(until end: String.Index) {
            if textStart < end { result.append(Fragment(source: String(source[textStart..<end]), kind: .text)) }
        }
        while cursor < source.endIndex {
            guard source[cursor] == "{" else { cursor = source.index(after: cursor); continue }
            let isDouble = source[cursor...].hasPrefix("{{")
            var end: String.Index?
            if isDouble {
                var scan = source.index(cursor, offsetBy: 2)
                var depth = 1
                while scan < source.endIndex {
                    if source[scan...].hasPrefix("{{") { depth += 1; scan = source.index(scan, offsetBy: 2) }
                    else if source[scan...].hasPrefix("}}") {
                        depth -= 1; scan = source.index(scan, offsetBy: 2)
                        if depth == 0 { end = scan; break }
                    } else { scan = source.index(after: scan) }
                }
            } else if let close = source[cursor...].firstIndex(of: "}") { end = source.index(after: close) }
            guard let end else { cursor = source.endIndex; break }
            let raw = String(source[cursor..<end])
            let content = isDouble ? String(raw.dropFirst(2).dropLast(2)) : String(raw.dropFirst().dropLast())
            let kind = classify(content, double: isDouble)
            if kind != .text {
                appendText(until: cursor)
                result.append(Fragment(source: raw, kind: kind))
                textStart = end
            }
            cursor = end
        }
        appendText(until: source.endIndex)
        return result
    }
    private static func classify(_ content: String, double: Bool) -> Kind {
        let lower = content.lowercased()
        if tileColors.contains(lower) { return .tile }
        guard double, !content.isEmpty, !content.contains("\n"), !content.contains("\r") else { return .text }
        if lower == "fill_space" || lower.hasPrefix("fill_space_repeat:") { return .fill }
        if lower.hasPrefix("icon:"), !content.contains("{") { return .icon }
        if content.trimmingCharacters(in: .whitespaces).hasPrefix("=") { return .formula }
        if let colon = content.firstIndex(of: ":") {
            let head = content[..<colon].split(separator: "/", omittingEmptySubsequences: false)
            if (1...2).contains(head.count), head.allSatisfy({ isSpanColor(String($0)) }) { return .span }
        }
        // Preserve malformed/nested future syntax as literal source rather than flattening it.
        if content.contains("{") || content.contains("}") { return .text }
        return .expression
    }
    private static func isSpanColor(_ value: String) -> Bool {
        let lower = value.lowercased()
        if tileColors.dropLast().contains(lower) || ["63", "64", "65", "66", "67", "68", "69", "70"].contains(lower) { return true }
        return lower.count == 7 && lower.first == "#" && lower.dropFirst().allSatisfy { $0.isHexDigit }
    }
    public static func sourceOffset(displayOffset: Int, in source: String) -> Int {
        var remaining = max(0, displayOffset), offset = 0
        for fragment in fragments(source) {
            if remaining < fragment.displayLength { return offset + (fragment.kind == .text ? remaining : 0) }
            remaining -= fragment.displayLength; offset += fragment.source.utf16.count
        }
        return offset
    }
    public static func displayOffset(sourceOffset: Int, in source: String) -> Int {
        var remaining = max(0, sourceOffset), offset = 0
        for fragment in fragments(source) {
            if remaining < fragment.source.utf16.count { return offset + (fragment.kind == .text ? remaining : 0) }
            remaining -= fragment.source.utf16.count; offset += fragment.displayLength
        }
        return offset
    }
}

/// Audited authoring dimensions; unknown/invalid shapes have no guessed canvas.
public struct TemplateGeometry: Equatable, Sendable {
    public let rows: Int
    public let columns: Int
    public let isPanel: Bool
    public init?(document: PageDocument) {
        func value(_ key: String, default fallback: Int? = nil, max limit: Int) -> Int? {
            guard let raw = document.root[key] else { return fallback }
            guard case .number(let number) = raw, let n = Int(number), (1...limit).contains(n) else { return nil }
            return n
        }
        switch document.root["device_type"] {
        case nil, .string("flagship"): rows = 6; columns = 22; isPanel = false
        case .string("note"): rows = 3; columns = 15; isPanel = false
        case .string("note_array"):
            guard let wide = value("notes_wide", default: 1, max: 8), let tall = value("notes_tall", default: 1, max: 8) else { return nil }
            rows = tall * 3; columns = wide * 15; isPanel = false
        case .string("panel"):
            guard let height = value("grid_rows", max: 96), let width = value("grid_cols", max: 128), height >= 3, width >= 10 else { return nil }
            rows = height; columns = width; isPanel = true
        default: return nil
        }
    }
}

/// A legacy page's board shape as stored (`device_type` + `notes_*` / `grid_*`), PLAN B20.
public struct PageGeometry: Equatable, Sendable, Hashable {
    public let deviceType: String
    public let notesWide: Int?
    public let notesTall: Int?
    public let gridRows: Int?
    public let gridCols: Int?
    public static let keys = ["device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols"]

    public init(deviceType: String, notesWide: Int? = nil, notesTall: Int? = nil, gridRows: Int? = nil, gridCols: Int? = nil) {
        self.deviceType = deviceType; self.notesWide = notesWide; self.notesTall = notesTall
        self.gridRows = gridRows; self.gridCols = gridCols
    }
    public static let flagship = PageGeometry(deviceType: "flagship")
    public static let note = PageGeometry(deviceType: "note")
    public static func noteArray(wide: Int, tall: Int) -> PageGeometry { PageGeometry(deviceType: "note_array", notesWide: wide, notesTall: tall) }
    public static func panel(rows: Int, cols: Int) -> PageGeometry { PageGeometry(deviceType: "panel", gridRows: rows, gridCols: cols) }

    public var rows: Int {
        switch deviceType {
        case "note": 3
        case "note_array": 3 * (notesTall ?? 1)
        case "panel": gridRows ?? 6
        default: 6
        }
    }
    public var columns: Int {
        switch deviceType {
        case "note": 15
        case "note_array": 15 * (notesWide ?? 1)
        case "panel": gridCols ?? 22
        default: 22
        }
    }
    /// True when this shape is smaller than `other` in either direction (content may be cut off).
    public func shrinks(from other: PageGeometry) -> Bool { rows < other.rows || columns < other.columns }
}

extension PageDocument {
    /// The stored shape, or nil when it isn't one the editor understands.
    public var geometry: PageGeometry? {
        guard let shape = TemplateGeometry(document: self) else { return nil }
        func int(_ key: String) -> Int? { if case .number(let n) = root[key] { return Int(n) }; return nil }
        switch root["device_type"] {
        case .string("note"): return .note
        case .string("note_array"): return .noteArray(wide: int("notes_wide") ?? 1, tall: int("notes_tall") ?? 1)
        case .string("panel"): return .panel(rows: shape.rows, cols: shape.columns)
        default: return .flagship
        }
    }

    /// Changes the page's board shape (PLAN B20/§2.4). Writes only the keys the new shape needs;
    /// every other key, including the old shape's now-unused ones, keeps its exact bytes (the
    /// server ignores `notes_*` off note arrays and clears `grid_*` off panels itself).
    public mutating func setGeometry(_ geometry: PageGeometry) throws {
        guard pageType == "template", editableTemplateLines != nil else { throw DocumentError.unsupportedTemplate }
        func number(_ value: Int?, _ range: ClosedRange<Int>) throws -> LosslessJSON {
            guard let value, range.contains(value) else { throw DocumentError.invalidLine }
            return .number(String(value))
        }
        var candidate = root
        switch geometry.deviceType {
        case "flagship", "note": break
        case "note_array":
            candidate["notes_wide"] = try number(geometry.notesWide, 1...8)
            candidate["notes_tall"] = try number(geometry.notesTall, 1...8)
        case "panel":
            candidate["grid_rows"] = try number(geometry.gridRows, 3...96)
            candidate["grid_cols"] = try number(geometry.gridCols, 10...128)
        default: throw DocumentError.unsupportedTemplate
        }
        if self.geometry == geometry { return }
        candidate["device_type"] = .string(geometry.deviceType)
        // Keep an unchanged number's lexeme ("2" vs "2.0") when the value is the same.
        for key in ["notes_wide", "notes_tall", "grid_rows", "grid_cols"] {
            if let old = root[key], case .number(let a) = old, case .number(let b)? = candidate[key], Int(a) == Int(b) { candidate[key] = old }
        }
        root = candidate
    }
}
