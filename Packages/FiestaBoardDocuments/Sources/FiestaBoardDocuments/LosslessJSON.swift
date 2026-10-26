import Foundation

public enum DocumentError: Error, Equatable, Sendable, LocalizedError {
    case invalidJSON(String)
    case pageMustBeObject
    case invalidName
    case unsupportedTemplate
    case invalidLine
    case deletionRequiresExplicitPolicy(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let reason): "Invalid JSON: \(reason)"
        case .pageMustBeObject: "A full page JSON object is required."
        case .invalidName: "Page name must contain 1 to 100 characters."
        case .unsupportedTemplate: "This template or its metadata cannot be safely edited."
        case .invalidLine: "Edit an existing line without adding line breaks."
        case .deletionRequiresExplicitPolicy(let key): "Removing field '\(key)' needs an explicit deletion policy."
        }
    }
}

/// Exact Unicode identity for JSON keys and deployment/page identifiers. Swift String's
/// default equality/hash normalizes canonically equivalent sequences; JSON does not.
struct ExactUnicodeString: Hashable, Sendable {
    let value: String
    init(_ value: String) { self.value = value }
    static func == (lhs: Self, rhs: Self) -> Bool { LosslessJSON.stringsEqual(lhs.value, rhs.value) }
    func hash(into hasher: inout Hasher) {
        hasher.combine(value.utf8.count)
        for byte in value.utf8 { hasher.combine(byte) }
    }
}

/// Dictionary-style object storage whose keys retain exact decoded Unicode sequences.
/// String subscripts and literals remain convenient without native String-key collisions.
public struct LosslessJSONObject: Equatable, Sendable, ExpressibleByDictionaryLiteral, Sequence {
    public typealias Element = (key: String, value: LosslessJSON)
    private var storage: [ExactUnicodeString: LosslessJSON] = [:]

    public init() {}
    public init(dictionaryLiteral elements: (String, LosslessJSON)...) {
        for (key, value) in elements { self[key] = value }
    }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var keys: [String] { storage.keys.map(\.value) }
    public subscript(key: String) -> LosslessJSON? {
        get { storage[ExactUnicodeString(key)] }
        set { storage[ExactUnicodeString(key)] = newValue }
    }
    public func makeIterator() -> AnyIterator<Element> {
        var iterator = storage.makeIterator()
        return AnyIterator {
            guard let entry = iterator.next() else { return nil }
            return (key: entry.key.value, value: entry.value)
        }
    }
    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Self {
        var result = Self()
        for entry in self where try isIncluded(entry) { result[entry.key] = entry.value }
        return result
    }
}

/// JSON syntax tree with numeric lexemes kept verbatim. No floating-point conversion.
/// Object key order and whitespace are canonicalized; null and absent stay distinct.
/// Duplicate keys are rejected, since collapsing them would lose source information.
public indirect enum LosslessJSON: Equatable, Sendable {
    case object(LosslessJSONObject)
    case array([LosslessJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    /// Raw JSON and editor strings compare decoded UTF-8, without Unicode normalization.
    public static func stringsEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.string(let a), .string(let b)), (.number(let a), .number(let b)):
            return stringsEqual(a, b)
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    public static func parse(_ data: Data) throws -> Self {
        var parser = JSONParser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.offset == parser.bytes.count else { throw parser.error("trailing input") }
        return value
    }

    public func serializedData() throws -> Data {
        var bytes = Data()
        try append(to: &bytes, depth: 0)
        return bytes
    }

    private func append(to output: inout Data, depth: Int) throws {
        guard depth <= 256 else { throw DocumentError.invalidJSON("nesting exceeds 256") }
        switch self {
        case .object(let object):
            output.append(123)
            let keys = object.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (index, key) in keys.enumerated() {
                if index > 0 { output.append(44) }
                try LosslessJSON.string(key).append(to: &output, depth: depth + 1)
                output.append(58)
                try object[key]!.append(to: &output, depth: depth + 1)
            }
            output.append(125)
        case .array(let values):
            output.append(91)
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(44) }
                try value.append(to: &output, depth: depth + 1)
            }
            output.append(93)
        case .string(let string):
            output.append(try JSONEncoder().encode(string))
        case .number(let lexeme):
            var parser = JSONParser(bytes: Array(lexeme.utf8))
            _ = try parser.number()
            guard parser.offset == parser.bytes.count else { throw parser.error("invalid number token") }
            output.append(contentsOf: lexeme.utf8)
        case .bool(let flag): output.append(contentsOf: (flag ? "true" : "false").utf8)
        case .null: output.append(contentsOf: "null".utf8)
        }
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var offset = 0
    var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }
    func error(_ reason: String) -> DocumentError { .invalidJSON("\(reason) at byte \(offset)") }
    mutating func skipWhitespace() {
        while let c = current, c == 32 || c == 9 || c == 10 || c == 13 { offset += 1 }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        offset += 1
        return true
    }
    mutating func require(_ byte: UInt8) throws {
        guard consume(byte) else { throw error("expected '\(Character(UnicodeScalar(byte)))'") }
    }
    mutating func literal(_ spelling: String, as value: LosslessJSON) throws -> LosslessJSON {
        for byte in spelling.utf8 { try require(byte) }
        return value
    }
    mutating func value(depth: Int) throws -> LosslessJSON {
        guard depth <= 256 else { throw error("nesting exceeds 256") }
        skipWhitespace()
        guard let next = current else { throw error("expected JSON value") }
        switch next {
        case 123:
            offset += 1
            var object = LosslessJSONObject()
            skipWhitespace()
            if consume(125) { return .object(object) }
            repeat {
                skipWhitespace()
                let key = try string()
                guard object[key] == nil else { throw error("duplicate object key") }
                skipWhitespace()
                try require(58)
                object[key] = try value(depth: depth + 1)
                skipWhitespace()
                if consume(125) { return .object(object) }
                try require(44)
            } while true
        case 91:
            offset += 1
            var array: [LosslessJSON] = []
            skipWhitespace()
            if consume(93) { return .array(array) }
            repeat {
                array.append(try value(depth: depth + 1))
                skipWhitespace()
                if consume(93) { return .array(array) }
                try require(44)
            } while true
        case 34: return .string(try string())
        case 116: return try literal("true", as: .bool(true))
        case 102: return try literal("false", as: .bool(false))
        case 110: return try literal("null", as: .null)
        case 45, 48...57: return .number(try number())
        default: throw error("expected JSON value")
        }
    }
    mutating func string() throws -> String {
        let start = offset
        try require(34)
        while let byte = current {
            offset += 1
            if byte == 34 {
                let data = Data(bytes[start..<offset])
                // Foundation's string decoder validates UTF-8, escapes and surrogate pairs.
                do { return try JSONDecoder().decode(String.self, from: data) }
                catch { throw self.error("invalid string or Unicode escape") }
            }
            if byte == 92 {
                guard current != nil else { throw error("unterminated escape") }
                offset += 1
            } else if byte < 32 { throw error("unescaped control character") }
        }
        throw error("unterminated string")
    }
    mutating func number() throws -> String {
        let start = offset
        _ = consume(45)
        if consume(48) {
            // A following digit is left unconsumed and rejected by the enclosing grammar.
        } else {
            guard let byte = current, (49...57).contains(byte) else { throw error("expected number digit") }
            offset += 1
            while let byte = current, (48...57).contains(byte) { offset += 1 }
        }
        if consume(46) {
            guard let byte = current, (48...57).contains(byte) else { throw error("expected fractional digit") }
            while let byte = current, (48...57).contains(byte) { offset += 1 }
        }
        if current == 101 || current == 69 {
            offset += 1
            if current == 43 || current == 45 { offset += 1 }
            guard let byte = current, (48...57).contains(byte) else { throw error("expected exponent digit") }
            while let byte = current, (48...57).contains(byte) { offset += 1 }
        }
        return String(decoding: bytes[start..<offset], as: UTF8.self)
    }
}
