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
}
