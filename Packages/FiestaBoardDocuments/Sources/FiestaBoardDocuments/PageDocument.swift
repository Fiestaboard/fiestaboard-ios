import Foundation

/// Full page document. Projections are for display; all writes use the retained tree.
public struct PageDocument: Equatable, Sendable {
    public private(set) var root: LosslessJSONObject

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

    /// Stable line slots are the editing identity in this slice. No insert/delete/move API.
    /// Unknown metadata fields survive; ambiguous shapes or known unsupported values block edits.
    public var editableTemplateLines: [String]? {
        guard pageType == "template", let lines = templateLines, !lines.isEmpty,
              !lines.contains(where: { $0.contains("\n") || $0.contains("\r") }) else { return nil }
        switch root["line_metadata"] {
        case nil, .null: return lines
        case .array(let metadata):
            guard metadata.count == lines.count else { return nil }
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
