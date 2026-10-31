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
        let spliced = LineMetadataSplice.splice(old: old, new: rows, metadata: root["line_metadata"])
        root["template"] = .array(rows.map(LosslessJSON.string))
        if let spliced { root["line_metadata"] = spliced }
    }
}
