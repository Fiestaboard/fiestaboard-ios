import Foundation

/// A partial page update. Unknown document fields never enter the write body.
public struct PageSavePatch: Encodable, Sendable, Equatable {
    public let name: String?
    public let template: [String]?
    public let expectedRevision: String
    public init(name: String? = nil, template: [String]? = nil, expectedRevision: String) {
        self.name = name; self.template = template; self.expectedRevision = expectedRevision
    }
    enum CodingKeys: String, CodingKey { case name, template, expectedRevision = "expected_revision" }
    public func validate() throws {
        guard name != nil || template != nil, !expectedRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
            throw FiestaBoardError.pageWritesDisabled
        }
    }
}

/// Storage acknowledgement only; page PUT does not directly send content to hardware.
public struct PageSaveReceipt: Sendable {
    public let rawData: Data
    public let pageData: Data
    public let incompatibleReferenceCount: Int
    public init(rawData: Data, expectedPageID: String) throws {
        guard let members = try? RawJSONObject.members(rawData),
              let referenceBytes = members["incompatible_references"],
              let references = try? JSONDecoder().decode([IgnoredJSONValue].self, from: referenceBytes),
              let bytes = members["page"],
              let page = try? JSONDecoder().decode(Page.self, from: bytes), page.id == expectedPageID,
              page.editProtocol == "page-revision-v1", page.revision?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw FiestaBoardError.unknownMutationOutcome
        }
        self.rawData = rawData; pageData = bytes; incompatibleReferenceCount = references.count
    }
}

public struct TemplateValidationIssue: Decodable, Sendable, Equatable {
    public let line: Int
    public let column: Int
    public let message: String
}
public struct TemplateValidationResult: Sendable {
    public let valid: Bool
    public let errors: [TemplateValidationIssue]
    public let rawData: Data
    public let isSimulated: Bool
    public init(rawData: Data, isSimulated: Bool = false) throws {
        struct Reply: Decodable { let valid: Bool; let errors: [TemplateValidationIssue] }
        guard let value = try? JSONDecoder().decode(Reply.self, from: rawData), value.valid == value.errors.isEmpty else {
            throw FiestaBoardError.invalidResponse
        }
        valid = value.valid; errors = value.errors; self.rawData = rawData; self.isSimulated = isSimulated
    }
}
public struct TemplatePreviewResult: Sendable {
    public let rendered: String
    public let lines: [String]
    public let charset: String?
    public let charsetIssueCount: Int
    public let canvasIssueCount: Int
    public let hasLayers: Bool
    public let rawData: Data
    public let isSimulated: Bool
    public init(rawData: Data, isSimulated: Bool = false) throws {
        struct Reply: Decodable { let rendered: String; let lines: [String]; let line_count: Int; let charset: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: rawData), reply.line_count == reply.lines.count,
              reply.rendered == reply.lines.joined(separator: "\n"),
              let members = try? RawJSONObject.members(rawData) else { throw FiestaBoardError.invalidResponse }
        rendered = reply.rendered; lines = reply.lines; charset = reply.charset
        charsetIssueCount = try RawJSONObject.arrayCount(members["charset_issues"])
        canvasIssueCount = try RawJSONObject.arrayCount(members["canvas_issues"])
        hasLayers = try RawJSONObject.arrayCount(members["layers"]) > 0
        self.rawData = rawData; self.isSimulated = isSimulated
    }
}

/// Lexical slicing preserves UTF-8 spelling, unknown numbers and nested values.
/// JSONDecoder validates syntax without converting unknown number lexemes to Double.
/// The scanner only finds top-level value boundaries, including escaped ASCII keys.
private struct IgnoredJSONValue: Decodable { init(from decoder: any Decoder) throws {} }
private struct JSONObjectEnvelope: Decodable {
    struct Key: CodingKey { let stringValue: String; let intValue: Int? = nil; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    init(from decoder: any Decoder) throws { _ = try decoder.container(keyedBy: Key.self) }
}
enum RawJSONObject {
    static func arrayCount(_ data: Data?) throws -> Int {
        guard let data, data != Data("null".utf8) else { return 0 }
        guard let count = try? JSONDecoder().decode([IgnoredJSONValue].self, from: data).count else { throw FiestaBoardError.invalidResponse }
        return count
    }
    static func members(_ data: Data) throws -> [String: Data] {
        guard (try? JSONDecoder().decode(JSONObjectEnvelope.self, from: data)) != nil else { throw FiestaBoardError.invalidResponse }
        let bytes = Array(data); var i = 0; var result: [String: Data] = [:]; var seen: Set<Data> = []
        func space() { while i < bytes.count && [9, 10, 13, 32].contains(bytes[i]) { i += 1 } }
        func stringEnd() throws {
            guard i < bytes.count, bytes[i] == 34 else { throw FiestaBoardError.invalidResponse }
            i += 1
            while i < bytes.count {
                if bytes[i] == 92 { i += 2 }
                else if bytes[i] == 34 { i += 1; return }
                else { i += 1 }
            }
            throw FiestaBoardError.invalidResponse
        }
        space(); i += 1; space()
        while i < bytes.count && bytes[i] != 125 {
            let keyStart = i; try stringEnd()
            let key = try JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<i]))
            guard seen.insert(Data(key.utf8)).inserted else { throw FiestaBoardError.invalidResponse }
            space(); guard bytes[i] == 58 else { throw FiestaBoardError.invalidResponse }; i += 1; space()
            let start = i; var depth = 0
            while i < bytes.count {
                let b = bytes[i]
                if b == 34 { try stringEnd(); continue }
                if depth == 0 && (b == 44 || b == 125) { break }
                if b == 123 || b == 91 { depth += 1 }
                if b == 125 || b == 93 { depth -= 1 }
                i += 1
            }
            var end = i
            while end > start && [9, 10, 13, 32].contains(bytes[end - 1]) { end -= 1 }
            result[key] = Data(bytes[start..<end]); space()
            if i < bytes.count && bytes[i] == 44 { i += 1; space() }
        }
        return result
    }
}

extension FiestaBoardService {
    public func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { throw FiestaBoardError.pageWritesDisabled }
    public func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { throw FiestaBoardError.previewUnsupported }
    public func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { throw FiestaBoardError.previewUnsupported }
}
