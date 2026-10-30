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
