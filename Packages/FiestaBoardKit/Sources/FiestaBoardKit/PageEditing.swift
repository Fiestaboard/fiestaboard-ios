import Foundation
import FiestaBoardDocuments

/// A partial page update. Unknown document fields never enter the write body.
public struct PageSavePatch: Encodable, Sendable, Equatable {
    public let name: String?
    public let template: [String]?
    public let expectedRevision: String
    public let lineMetadataData: Data?
    public let blocksData: Data?
    public let styleData: Data?
    public let layoutData: Data?
    public let targetsData: Data?
    public var hasFlexibleFields: Bool { blocksData != nil || styleData != nil || layoutData != nil || targetsData != nil }
    public init(name: String? = nil, template: [String]? = nil, lineMetadataData: Data? = nil,
                blocksData: Data? = nil, styleData: Data? = nil, layoutData: Data? = nil, targetsData: Data? = nil,
                expectedRevision: String) {
        self.name = name; self.template = template; self.lineMetadataData = lineMetadataData
        self.blocksData = blocksData; self.styleData = styleData; self.layoutData = layoutData; self.targetsData = targetsData
        self.expectedRevision = expectedRevision
    }
    enum CodingKeys: String, CodingKey { case name, template, expectedRevision = "expected_revision" }
    public func validate() throws {
        guard name != nil || template != nil || lineMetadataData != nil || hasFlexibleFields,
              !expectedRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.map({ (1...100).contains($0.unicodeScalars.count) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              !hasFlexibleFields || (template == nil && lineMetadataData == nil) else { throw FiestaBoardError.pageWritesDisabled }
        if let lineMetadataData { try RawJSONObject.validateObjectArray(lineMetadataData) }
        if hasFlexibleFields {
            var root: LosslessJSONObject = ["name": .string(name ?? "Page"), "type": .string("flexible"), "document_protocol": .string("page-document-v2"), "blocks": .array([.object(["id": .string("default"), "kind": .string("spacer")])])]
            for (key, bytes) in rawFields {
                root[key] = try LosslessJSON.parse(bytes)
            }
            let document = try PageDocument(data: LosslessJSON.object(root).serializedData())
            guard document.flexibleIssues.isEmpty else { throw FiestaBoardError.pageWritesDisabled }
        }
    }
    private var rawFields: [(String, Data)] {
        [("line_metadata", lineMetadataData), ("blocks", blocksData), ("style", styleData), ("layout", layoutData), ("targets", targetsData)].compactMap { key, value in value.map { (key, $0) } }
    }
    public func encode(to encoder: any Encoder) throws {
        guard rawFields.isEmpty else { throw FiestaBoardError.pageWritesDisabled }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(template, forKey: .template)
        try container.encode(expectedRevision, forKey: .expectedRevision)
    }
    public func serializedData() throws -> Data {
        try validate()
        let encoded = try JSONEncoder().encode(PageSavePatch(name: name, template: template, expectedRevision: expectedRevision))
        guard encoded.last == 125 else { throw FiestaBoardError.invalidResponse }
        var result = Data(encoded.dropLast())
        for (key, data) in rawFields {
            result.append(Data((",\"" + key + "\":").utf8)); result.append(data)
        }
        result.append(125)
        _ = try RawJSONObject.members(result)
        return result
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
public struct PhysicalPreviewFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgba: Data
}
public enum PreviewSurface: Sendable, Equatable {
    case legacy, physical(PhysicalPreviewFrame), unsupported

    static func read(_ data: Data?) throws -> Self {
        guard let data, data != Data("null".utf8) else { return .legacy }
        let layers = try JSONDecoder().decode([Layer].self, from: data)
        if layers.contains(where: { $0.surface == .unsupported }) { return .unsupported }
        let frames = layers.compactMap { layer -> PhysicalPreviewFrame? in
            if case .physical(let frame) = layer.surface { return frame }; return nil
        }
        guard !frames.isEmpty else { return .legacy }
        // V1 is a complete surface, not an overlay in legacy character coordinates.
        guard frames.count == 1, layers.count == 1 else { throw FiestaBoardError.invalidResponse }
        return .physical(frames[0])
    }

    private struct Layer: Decodable {
        let surface: PreviewSurface
        enum CodingKeys: String, CodingKey { case x, y, width, height, rgba, version = "physical_frame_version" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.version) else {
                surface = .legacy; return
            }
            guard (try? c.decode(Int.self, forKey: .version)) == 1 else {
                surface = .unsupported; return
            }
            let width = try c.decode(Int.self, forKey: .width)
            let height = try c.decode(Int.self, forKey: .height)
            guard (1...512).contains(width), (1...512).contains(height),
                  try c.decode(Int.self, forKey: .x) == 0, try c.decode(Int.self, forKey: .y) == 0 else {
                throw FiestaBoardError.invalidResponse
            }
            let encoded = try c.decode(String.self, forKey: .rgba)
            let count = width * height * 4
            guard encoded.utf8.count == ((count + 2) / 3) * 4,
                  let bytes = Data(base64Encoded: encoded), bytes.count == count,
                  stride(from: 3, to: count, by: 4).allSatisfy({ bytes[$0] == 255 }) else {
                throw FiestaBoardError.invalidResponse
            }
            surface = .physical(PhysicalPreviewFrame(width: width, height: height, rgba: bytes))
        }
    }
}
public struct TemplatePreviewResult: Sendable {
    public let surface: PreviewSurface
    public let rendered: String
    public let lines: [String]
    public let charset: String?
    public let charsetIssueCount: Int
    public let canvasIssueCount: Int
    public let hasLayers: Bool
    public let rawData: Data
    public let isSimulated: Bool
    /// Full decodes of the optional members (PLAN §2.3, §3.3). Elements that do not match the
    /// verified 10.3.2 shapes are skipped, never fatal; the counts above stay exact.
    public let charsetIssues: [TemplateCharsetIssue]
    public let canvasIssues: [TemplateCanvasIssue]
    public let layers: [TemplatePreviewLayer]
    public init(rawData: Data, isSimulated: Bool = false) throws {
        struct Reply: Decodable { let rendered: String; let lines: [String]; let line_count: Int; let charset: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: rawData), reply.line_count == reply.lines.count,
              reply.rendered == reply.lines.joined(separator: "\n"),
              let members = try? RawJSONObject.members(rawData) else { throw FiestaBoardError.invalidResponse }
        rendered = reply.rendered; lines = reply.lines; charset = reply.charset
        charsetIssueCount = try RawJSONObject.arrayCount(members["charset_issues"])
        canvasIssueCount = try RawJSONObject.arrayCount(members["canvas_issues"])
        hasLayers = try RawJSONObject.arrayCount(members["layers"]) > 0
        surface = try PreviewSurface.read(members["layers"])
        charsetIssues = LenientArray.decode(members["charset_issues"])
        canvasIssues = LenientArray.decode(members["canvas_issues"])
        layers = LenientArray.decode(members["layers"])
        self.rawData = rawData; self.isSimulated = isSimulated
    }
}

/// `charset_issues[]` entry: FiestaUI `CharsetValidationIssue` (`S:src/led/charsets.py:385`).
public struct TemplateCharsetIssue: Decodable, Sendable, Equatable {
    public struct Token: Decodable, Sendable, Equatable {
        public let kind: String?
        public let value: String?
        public let color: String?
    }
    public let row: Int
    public let col: Int
    public let token: Token?
    public let reason: String?
    public let fallback: Token?
}
/// `canvas_issues[]` entry (`S:src/canvas/evaluate.py:75`).
public struct TemplateCanvasIssue: Decodable, Sendable, Equatable {
    public let canvasID: String?
    public let path: String?
    public let message: String
    public init(canvasID: String?, path: String?, message: String) { self.canvasID = canvasID; self.path = path; self.message = message }
    enum CodingKeys: String, CodingKey { case canvasID = "canvas_id", path, message }
}
/// `layers[]` entry: FiestaUI `LedBitmapLayer` `{x, y, width, height, rgba}` (`S:src/canvas/layer.py:57`).
public struct TemplatePreviewLayer: Decodable, Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let rgba: String
}
private enum LenientArray {
    private struct Element<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
    }
    static func decode<T: Decodable>(_ data: Data?) -> [T] {
        guard let data, let elements = try? JSONDecoder().decode([Element<T>].self, from: data) else { return [] }
        return elements.compactMap(\.value)
    }
}

/// Wire contract of POST /pages/preview/flexible, distinct from legacy template rendering.
public struct FlexiblePreviewResult: Sendable {
    public let surface: PreviewSurface
    public let lines: [String]
    public let displayType: String
    public let layoutIssueCount: Int
    public let layoutWarnings: [String]
    public let canvasWarnings: [String]
    public let canvasIssueCount: Int
    public let hasLayers: Bool
    public let rawData: Data
    public init(rawData: Data) throws {
        struct Reply: Decodable { let available: Bool; let page_id: String; let message: String; let lines: [String]; let display_type: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: rawData), reply.available, reply.page_id == "unsaved",
              reply.message == reply.lines.joined(separator: "\n"),
              let members = try? RawJSONObject.members(rawData), members["layout_issues"] != nil, let raw = members["raw"],
              (try? RawJSONObject.members(raw)) != nil else { throw FiestaBoardError.invalidResponse }
        lines = reply.lines; displayType = reply.display_type
        layoutIssueCount = try RawJSONObject.arrayCount(members["layout_issues"])
        canvasIssueCount = try RawJSONObject.arrayCount(members["canvas_issues"])
        func messages(_ bytes: Data?) throws -> [String] {
            guard let bytes, bytes != Data("null".utf8), case .array(let values) = try LosslessJSON.parse(bytes) else { return [] }
            return try values.map { value in
                if case .object(let object) = value, case .string(let text) = object["message"] { return text }
                return String(decoding: try value.serializedData(), as: UTF8.self)
            }
        }
        layoutWarnings = try messages(members["layout_issues"])
        canvasWarnings = try messages(members["canvas_issues"])
        hasLayers = try RawJSONObject.arrayCount(members["layers"]) > 0
        surface = try PreviewSurface.read(members["layers"])
        self.rawData = rawData
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
    static func validateObjectArray(_ data: Data) throws {
        guard (try? JSONDecoder().decode([JSONObjectEnvelope].self, from: data)) != nil else {
            throw FiestaBoardError.pageWritesDisabled
        }
        // Inspect individual object envelopes too, rejecting ambiguous duplicate keys.
        let bytes = Array(data)
        var objectStarts: [Int] = []; var inString = false; var escaped = false
        var prior: UInt8?
        for (index, byte) in bytes.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
                continue
            }
            if [9, 10, 13, 32].contains(byte) { continue }
            if (byte == 125 || byte == 93), prior == 44 { throw FiestaBoardError.pageWritesDisabled }
            prior = byte
            if byte == 34 { inString = true; continue }
            if byte == 123 { objectStarts.append(index) }
            if byte == 125 {
                guard let start = objectStarts.popLast() else { throw FiestaBoardError.pageWritesDisabled }
                _ = try members(Data(bytes[start...index]))
            }
        }
    }
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
    public func previewFlexiblePage(requestData: Data, target: BoardTarget) async throws -> FlexiblePreviewResult { throw FiestaBoardError.previewUnsupported }
    public func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { throw FiestaBoardError.pageWritesDisabled }
    public func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { throw FiestaBoardError.previewUnsupported }
    public func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { throw FiestaBoardError.previewUnsupported }
}
