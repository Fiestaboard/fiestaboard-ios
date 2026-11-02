import Foundation

/// Full page document. Projections are for display; all writes use the retained tree.
public struct PageDocument: Equatable, Sendable {
    public internal(set) var root: LosslessJSONObject

    public init(data: Data) throws {
        guard case .object(let object) = try LosslessJSON.parse(data) else { throw DocumentError.pageMustBeObject }
        root = object
    }

    public func serializedData() throws -> Data { try LosslessJSON.object(root).serializedData() }
    public var name: String? { if case .string(let value) = root["name"] { value } else { nil } }
    public var pageType: String? { if case .string(let value) = root["type"] { value } else { nil } }
    public var templateLines: [String]? {
        guard case .array(let entries) = root["template"] else { return nil }
        var lines: [String] = []
        for entry in entries {
            guard case .string(let line) = entry else { return nil }
            lines.append(line)
        }
        return lines
    }

    /// Unknown metadata fields survive; ambiguous shapes or known unsupported values block edits.
    public var editableTemplateLines: [String]? {
        guard pageType == "template", let lines = templateLines,
              !lines.contains(where: { $0.contains("\n") || $0.contains("\r") }) else { return nil }
        switch root["line_metadata"] {
        case nil, .null: return lines
        case .array(let metadata):
            // Real pages carry arrays shorter than `template` (PLAN §2.2). The server reads a row
            // without an entry from its legacy prefixes (`templates/engine.py`), as `lineAlignment`
            // does. Longer arrays have no row to belong to and stay read-only.
            guard metadata.count <= lines.count else { return nil }
            for value in metadata {
                guard case .object(let object) = value else { return nil }
                if let alignment = object["alignment"] {
                    guard case .string(let string) = alignment, ["left", "center", "right"].contains(string) else { return nil }
                }
                if let wrap = object["wrap"], case .bool = wrap {} else if object["wrap"] != nil { return nil }
            }
            return lines
        default: return nil
        }
    }

    public mutating func setName(_ name: String) throws {
        // Pydantic's string constraints count Unicode scalars rather than grapheme clusters.
        guard (1...100).contains(name.unicodeScalars.count) else { throw DocumentError.invalidName }
        root["name"] = .string(name)
    }

    public mutating func replaceTemplateLine(at index: Int, with content: String) throws {
        guard var lines = editableTemplateLines else { throw DocumentError.unsupportedTemplate }
        guard lines.indices.contains(index), !content.contains("\n"), !content.contains("\r") else { throw DocumentError.invalidLine }
        lines[index] = content
        root["template"] = .array(lines.map(LosslessJSON.string))
    }

    private static var defaultLineMetadata: LosslessJSON {
        .object(["alignment": .string("left"), "wrap": .bool(false)])
    }
    /// Mutate complete row records so positional metadata can never drift from its source.
    private mutating func editRows(_ edit: (inout [String], inout [LosslessJSON]?) throws -> Void) throws {
        guard var lines = editableTemplateLines else { throw DocumentError.unsupportedTemplate }
        var metadata: [LosslessJSON]?
        if case .array(let values) = root["line_metadata"] { metadata = values }
        try edit(&lines, &metadata)
        root["template"] = .array(lines.map(LosslessJSON.string))
        if let metadata { root["line_metadata"] = .array(metadata) }
    }
    /// Extends a short `line_metadata` array so it has an entry for `index`. Rows that gain an
    /// entry keep their effective alignment/wrap: their legacy prefixes (which the server reads
    /// only for rows without an entry) move into the entry. Rows without prefixes are untouched.
    private static func padMetadata(_ metadata: inout [LosslessJSON], lines: inout [String], through index: Int) {
        while metadata.count <= index, metadata.count < lines.count {
            let row = metadata.count
            let legacy = legacyLine(lines[row])
            metadata.append(.object(["alignment": .string(legacy.alignment), "wrap": .bool(legacy.wrap)]))
            if legacy.content != lines[row] { lines[row] = legacy.content }
        }
    }
    public mutating func insertTemplateLine(at index: Int, with content: String = "") throws {
        try editRows { lines, metadata in
            guard (0...lines.count).contains(index), !content.contains("\n"), !content.contains("\r") else { throw DocumentError.invalidLine }
            lines.insert(content, at: index)
            // Past the end of a short array the new row has no entry, which already reads left.
            if let count = metadata?.count, index <= count { metadata?.insert(Self.defaultLineMetadata, at: index) }
        }
    }
    public mutating func removeTemplateLine(at index: Int) throws {
        try editRows { lines, metadata in
            guard lines.indices.contains(index) else { throw DocumentError.invalidLine }
            lines.remove(at: index)
            if let count = metadata?.count, index < count { metadata?.remove(at: index) }
        }
    }
    /// Destination is the row's final index, after the move.
    public mutating func moveTemplateLine(from source: Int, to destination: Int) throws {
        try editRows { lines, metadata in
            guard lines.indices.contains(source), lines.indices.contains(destination) else { throw DocumentError.invalidLine }
            if var values = metadata {
                Self.padMetadata(&values, lines: &lines, through: max(source, destination))
                values.insert(values.remove(at: source), at: destination); metadata = values
            }
            lines.insert(lines.remove(at: source), at: destination)
        }
    }
    public mutating func duplicateTemplateLine(at index: Int) throws {
        try editRows { lines, metadata in
            guard lines.indices.contains(index) else { throw DocumentError.invalidLine }
            lines.insert(lines[index], at: index + 1)
            if var values = metadata, index < values.count { values.insert(values[index], at: index + 1); metadata = values }
        }
    }
    /// Mirrors exact20 src/text_utils.py: optional lowercase {wrap}, then one
    /// case-insensitive alignment prefix. Prefix order is significant.
    private static func legacyLine(_ line: String) -> (alignment: String, wrap: Bool, content: String) {
        var content = line
        let wrap = content.hasPrefix("{wrap}")
        if wrap { content.removeFirst(6) }
        for alignment in ["left", "center", "right"] {
            let token = "{\(alignment)}"
            if let range = content.range(of: token, options: [.anchored, .caseInsensitive]) {
                content.removeSubrange(range)
                return (alignment, wrap, content)
            }
        }
        return ("left", wrap, content)
    }
    public func lineAlignment(at index: Int) -> String {
        guard let lines = templateLines, lines.indices.contains(index) else { return "left" }
        if case .array(let metadata) = root["line_metadata"], metadata.indices.contains(index) {
            if case .object(let object) = metadata[index], case .string(let alignment) = object["alignment"] { return alignment }
            return "left"
        }
        return Self.legacyLine(lines[index]).alignment
    }
    public func lineWrap(at index: Int) -> Bool {
        guard let lines = templateLines, lines.indices.contains(index) else { return false }
        if case .array(let metadata) = root["line_metadata"], metadata.indices.contains(index) {
            if case .object(let object) = metadata[index], case .bool(let wrap) = object["wrap"] { return wrap }
            return false
        }
        return Self.legacyLine(lines[index]).wrap
    }
    private mutating func setLineMetadata(at index: Int, key: String, value: LosslessJSON) throws {
        guard let lines = editableTemplateLines else { throw DocumentError.unsupportedTemplate }
        guard lines.indices.contains(index) else { throw DocumentError.invalidLine }
        var metadata: [LosslessJSON]
        if case .array(let existing) = root["line_metadata"] {
            // A short array gains entries only up to this row (PLAN §2.2: write only what changed).
            metadata = existing
            var rows = lines
            Self.padMetadata(&metadata, lines: &rows, through: index)
            if rows != lines { root["template"] = .array(rows.map(LosslessJSON.string)) }
        } else {
            // Follow storage migration: metadata overrides prefixes, so consume only the
            // prefixes the backend previously interpreted, keeping the remaining source exact.
            let migrated = lines.map(Self.legacyLine)
            metadata = migrated.map { .object(["alignment": .string($0.alignment), "wrap": .bool($0.wrap)]) }
            root["template"] = .array(migrated.map { .string($0.content) })
        }
        guard case .object(var object) = metadata[index] else { throw DocumentError.unsupportedTemplate }
        object[key] = value; metadata[index] = .object(object)
        root["line_metadata"] = .array(metadata)
    }
    public mutating func setLineAlignment(at index: Int, alignment: String) throws {
        guard ["left", "center", "right"].contains(alignment) else { throw DocumentError.invalidLine }
        try setLineMetadata(at: index, key: "alignment", value: .string(alignment))
    }
    public mutating func setLineWrap(at index: Int, wrap: Bool) throws {
        try setLineMetadata(at: index, key: "wrap", value: .bool(wrap))
    }

    /// A changed-field object for inspection/future transport. This does not send a request.
    /// Removing a field is not equivalent to null; omission requires a separate deletion policy.
    public func changedFields(from baseline: PageDocument) throws -> LosslessJSON {
        for key in baseline.root.keys where root[key] == nil { throw DocumentError.deletionRequiresExplicitPolicy(key) }
        return .object(root.filter { key, value in baseline.root[key] != value })
    }
    /// Retain the exact values accepted by the evaluation endpoints, without converting through
    /// floating point or reconstructing nested metadata/canvas objects. Storage fields stay local.
    public func evaluationData(boardID: String, preview: Bool) throws -> Data {
        guard pageType == "template", templateLines != nil, !boardID.isEmpty else {
            throw DocumentError.unsupportedTemplate
        }
        var payload: LosslessJSONObject = ["template": root["template"]!, "board_id": .string(boardID)]
        if preview {
            for key in ["device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols", "line_metadata", "canvases"] {
                guard let value = root[key] else { continue }
                switch (key, value) {
                case ("device_type", .null), ("grid_rows", .null), ("grid_cols", .null),
                     ("line_metadata", .null), ("canvases", .null): break
                case ("device_type", .string(let kind)):
                    guard ["flagship", "note", "note_array", "panel"].contains(kind) else { throw DocumentError.unsupportedTemplate }
                case ("notes_wide", .number(let n)), ("notes_tall", .number(let n)),
                     ("grid_rows", .number(let n)), ("grid_cols", .number(let n)):
                    guard !n.isEmpty, n.utf8.allSatisfy({ (48...57).contains($0) }), n != "0" else { throw DocumentError.unsupportedTemplate }
                case ("line_metadata", .array(let values)), ("canvases", .array(let values)):
                    guard values.allSatisfy({ if case .object = $0 { true } else { false } }) else { throw DocumentError.unsupportedTemplate }
                default: throw DocumentError.unsupportedTemplate
                }
                payload[key] = value
            }
            if root["device_type"] == .string("panel") {
                guard case .number = root["grid_rows"], case .number = root["grid_cols"] else { throw DocumentError.unsupportedTemplate }
            }
        }
        return try LosslessJSON.object(payload).serializedData()
    }

}
