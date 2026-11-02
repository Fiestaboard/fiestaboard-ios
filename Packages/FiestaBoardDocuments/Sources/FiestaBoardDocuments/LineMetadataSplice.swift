import Foundation

/// Keeps positional `line_metadata` in step with the rows when the document editor inserts or
/// deletes rows in the middle (Return / Backspace-join / multi-line paste). Mirrors the web's
/// prefix/suffix row diff (`FiestaBoard@v10.3.2:web/src/components/page-builder.tsx:1087-1135`)
/// with the native lossless rules (PLAN §2.2):
///
/// - absent metadata stays absent and `null` stays `null` (legacy prefixes live in the row text);
/// - an array is spliced: inserted rows get `{"alignment":"left","wrap":false}`, deleted rows lose
///   their entry, every surviving entry keeps its exact bytes;
/// - an array shorter than the rows is never padded (a missing entry already means left/no-wrap);
///   inserts beyond its end add nothing, deletes beyond its end remove nothing.
public enum LineMetadataSplice {
    public static let defaultEntry: LosslessJSON = .object(["alignment": .string("left"), "wrap": .bool(false)])

    /// The common prefix/suffix of two row lists, as the web computes it.
    public static func diff(old: [String], new: [String]) -> (prefix: Int, suffix: Int) {
        let limit = min(old.count, new.count)
        var prefix = 0
        while prefix < limit && LosslessJSON.stringsEqual(old[prefix], new[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix && LosslessJSON.stringsEqual(old[old.count - 1 - suffix], new[new.count - 1 - suffix]) { suffix += 1 }
        return (prefix, suffix)
    }

    /// Returns the metadata to store after `old` rows become `new` rows. `nil` means "absent".
    public static func splice(old: [String], new: [String], metadata: LosslessJSON?) -> LosslessJSON? {
        guard case .array(var entries) = metadata else { return metadata }
        guard old.count != new.count else { return metadata }
        let (prefix, suffix) = diff(old: old, new: new)
        if new.count < old.count {
            let count = old.count - new.count
            let start = prefix + (new.count - prefix - suffix)
            if start < entries.count { entries.removeSubrange(start..<min(entries.count, start + count)) }
        } else {
            let count = new.count - old.count
            let start = prefix + (old.count - prefix - suffix)
            if start <= entries.count {
                entries.insert(contentsOf: Array(repeating: defaultEntry, count: count), at: start)
            }
        }
        return .array(entries)
    }
}

extension PageDocument {
    /// Replaces the whole row list in one value change, splicing `line_metadata` positionally.
    /// Rows are the document editor's paragraphs; none may contain a line break.
    public mutating func replaceTemplateRows(_ rows: [String]) throws {
        guard let old = editableTemplateLines else { throw DocumentError.unsupportedTemplate }
        guard !rows.contains(where: { $0.contains("\n") || $0.contains("\r") }) else { throw DocumentError.invalidLine }
        var spliced = LineMetadataSplice.splice(old: old, new: rows, metadata: root["line_metadata"])
        // A row whose text was cleared drops its alignment and wrap (web research §d.11: metadata
        // never carries onto a re-typed row). Only with the row count unchanged, where positions
        // are unambiguous; other keys in the entry are kept.
        if old.count == rows.count, case .array(var entries)? = spliced {
            for index in rows.indices where index < entries.count && rows[index].isEmpty && !old[index].isEmpty {
                guard case .object(var entry) = entries[index] else { continue }
                if entry["alignment"] != nil && entry["alignment"] != .string("left") { entry["alignment"] = .string("left") }
                if entry["wrap"] == .bool(true) { entry["wrap"] = .bool(false) }
                entries[index] = .object(entry)
            }
            spliced = .array(entries)
        }
        root["template"] = .array(rows.map(LosslessJSON.string))
        if let spliced { root["line_metadata"] = spliced }
    }

    /// Rows as Plain mode shows them (PLAN B18): a row with a metadata entry gets `{wrap}` then its
    /// alignment as prefixes where set; a row without one already carries its legacy prefixes.
    public var plainRows: [String]? {
        guard let lines = editableTemplateLines else { return nil }
        guard case .array(let entries) = root["line_metadata"] else { return lines }
        return lines.enumerated().map { index, line in
            index < entries.count ? PlainModePrefix.encode(line, alignment: lineAlignment(at: index), wrap: lineWrap(at: index)) : line
        }
    }

    /// Commits Plain mode rows: prefixes on rows with a metadata entry move into the entry
    /// (prefixes win); rows without one keep their text, prefixes included, as the server reads
    /// them. Untouched rows and entries stay byte-identical.
    public mutating func replacePlainRows(_ rows: [String]) throws {
        guard let current = plainRows else { throw DocumentError.unsupportedTemplate }
        guard rows != current else { return }
        // First the row structure (splicing entries), using the plain rows' positions.
        guard let old = editableTemplateLines else { throw DocumentError.unsupportedTemplate }
        let (prefix, suffix) = LineMetadataSplice.diff(old: current, new: rows)
        var raw = rows
        for index in 0..<prefix { raw[index] = old[index] }
        for back in 0..<suffix { raw[rows.count - 1 - back] = old[old.count - 1 - back] }
        try replaceTemplateRows(raw)
        guard case .array(var entries) = root["line_metadata"], var lines = templateLines else { return }
        for index in rows.indices where index >= prefix && index < rows.count - suffix && index < entries.count {
            let decoded = PlainModePrefix.decode(rows[index])
            lines[index] = decoded.content
            guard case .object(var entry) = entries[index] else { continue }
            let alignment = decoded.alignment ?? "left"
            if lineAlignment(at: index) != alignment || entry["alignment"] == nil && alignment != "left" { entry["alignment"] = .string(alignment) }
            if lineWrap(at: index) != decoded.wrap { entry["wrap"] = .bool(decoded.wrap) }
            entries[index] = .object(entry)
        }
        root["template"] = .array(lines.map(LosslessJSON.string))
        root["line_metadata"] = .array(entries)
    }
}

/// Plain mode's row prefixes (PLAN B18, `S:page-builder.tsx:1500-1535`): `{wrap}` is stripped first,
/// then one alignment prefix, case-insensitively; prefixes win over the row's metadata.
public enum PlainModePrefix {
    public static func encode(_ content: String, alignment: String, wrap: Bool) -> String {
        (wrap ? "{wrap}" : "") + (alignment == "left" ? "" : "{\(alignment)}") + content
    }
    public static func decode(_ line: String) -> (alignment: String?, wrap: Bool, content: String) {
        var content = Substring(line)
        var wrap = false
        if let range = content.range(of: "{wrap}", options: [.anchored, .caseInsensitive]) { wrap = true; content = content[range.upperBound...] }
        for alignment in ["left", "center", "right"] {
            if let range = content.range(of: "{\(alignment)}", options: [.anchored, .caseInsensitive]) {
                return (alignment, wrap, String(content[range.upperBound...]))
            }
        }
        return (nil, wrap, String(content))
    }
}
