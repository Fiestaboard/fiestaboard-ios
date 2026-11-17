import Foundation
import Combine

/// The formula editor's pure parts (PLAN B21), ported from the web's `FormulaEditorPanel.tsx`
/// (`FiestaBoard@v10.3.2`): syntax colouring, one-argument-per-line pretty printing, and the
/// debounced validation state. The fixture and the editor never evaluate a formula.
public enum FormulaHighlighter {
    public enum Kind: String, Equatable, Sendable {
        case function, string, number, variable, `operator`, punctuation
    }
    public struct Token: Equatable, Sendable {
        public let kind: Kind
        /// UTF-16 range in the expression (for `NSAttributedString`).
        public let range: NSRange
        public init(kind: Kind, range: NSRange) { self.kind = kind; self.range = range }
    }

    /// The web's stream tokenizer: `"…"` strings, numbers, lowercase dotted variable paths,
    /// uppercase function names, comparison/arithmetic operators, parens and commas. An unclosed
    /// string runs to the end (it is still being typed).
    public static func tokens(_ expression: String) -> [Token] {
        let text = expression as NSString
        var tokens: [Token] = []
        var index = 0
        let rules: [(Kind, String)] = [
            (.string, #""[^"]*"?"#),
            (.number, #"\d+\.?\d*"#),
            (.variable, #"[a-z_][a-z0-9_]*(?:\.[a-z_0-9][a-z0-9_]*)*"#),
            (.function, #"[A-Z][A-Z0-9_]*"#),
            (.operator, #"[<>]=?|[!=]=|[+\-*/]"#),
            (.punctuation, #"[(),]"#),
        ]
        let compiled = rules.compactMap { kind, pattern in (try? NSRegularExpression(pattern: pattern)).map { (kind, $0) } }
        outer: while index < text.length {
            let character = text.character(at: index)
            if character == 32 || character == 10 || character == 9 { index += 1; continue }
            for (kind, regex) in compiled {
                // `.anchored`: the match must start at `index`.
                guard let match = regex.firstMatch(in: expression, options: [.anchored], range: NSRange(location: index, length: text.length - index)),
                      match.range.length > 0 else { continue }
                tokens.append(Token(kind: kind, range: match.range))
                index = NSMaxRange(match.range)
                continue outer
            }
            index += 1
        }
        return tokens
    }

    /// Expands a flat expression to one argument per line, two-space indented (web `formatFormula`).
    public static func pretty(_ expression: String) -> String {
        var result = ""
        var depth = 0
        var inString = false
        var skipSpaces = false
        for character in expression {
            if inString { result.append(character); if character == "\"" { inString = false }; continue }
            if character == "\"" { inString = true; skipSpaces = false; result.append(character); continue }
            if skipSpaces && character == " " { continue }
            skipSpaces = false
            switch character {
            case "(":
                depth += 1; result += "(\n" + String(repeating: "  ", count: max(depth, 0)); skipSpaces = true
            case ")":
                depth -= 1; result += "\n" + String(repeating: "  ", count: max(depth, 0)) + ")"
            case ",":
                result += ",\n" + String(repeating: "  ", count: max(depth, 0)); skipSpaces = true
            default: result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Collapses a pretty-printed expression back to one line (web `unformatFormula`).
    public static func flatten(_ text: String) -> String {
        var result = ""
        var inString = false
        var afterNewline = false
        for character in text {
            if inString {
                result.append(character); if character == "\"" { inString = false }; afterNewline = false
            } else if character == "\"" {
                inString = true; result.append(character); afterNewline = false
            } else if character == "\n" {
                afterNewline = true
            } else if character == " " && afterNewline {
                continue
            } else {
                result.append(character); afterNewline = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The scaffold a function row inserts (`IF(` / `)` with the caret inside), pretty-printed, and
    /// the caret's UTF-16 offset.
    public static func scaffold(_ name: String) -> (text: String, caret: Int) {
        let text = pretty(name + "()")
        let lines = text.components(separatedBy: "\n")
        // `IF(\n  \n)`: the caret sits on the indented middle line.
        let caret = lines.count >= 2 ? (lines[0] as NSString).length + 1 + (lines[1] as NSString).length : (text as NSString).length
        return (text, caret)
    }
}

/// The result of one validation round trip, reduced to what the editor shows.
public struct FormulaCheck: Equatable, Sendable {
    public let valid: Bool
    public let messages: [String]
    public init(valid: Bool, messages: [String]) { self.valid = valid; self.messages = messages }
    /// From `POST /templates/validate`: messages without the leading "Formula " (as the web strips it).
    public init(_ result: TemplateValidationResult) {
        self.init(valid: result.valid, messages: result.errors.map { FormulaValidator.displayMessage($0.message) })
    }
}

/// idle → validating → valid / invalid, 300 ms after the last change (PLAN B21). A network failure
/// returns to idle (no verdict, nothing retried). A late answer for an older expression is
/// dropped. Confirm is allowed only for the expression that last validated as valid.
@MainActor public final class FormulaValidator: ObservableObject {
    public enum Status: Equatable, Sendable {
        case idle, validating, valid, invalid([String])
        public var label: String {
            switch self {
            case .idle: return "idle"
            case .validating: return "validating"
            case .valid: return "valid"
            case .invalid: return "invalid"
            }
        }
    }

    @Published public private(set) var status: Status = .idle
    /// The trimmed expression that last validated as valid.
    @Published public private(set) var lastValid: String?
    private var latest = ""
    private var task: Task<Void, Never>?
    private let delay: Duration
    private let check: @MainActor (String) async throws -> FormulaCheck

    /// `check` receives the bare expression; the caller wraps it as `{{= … }}`.
    public init(delay: Duration = .milliseconds(300), check: @escaping @MainActor (String) async throws -> FormulaCheck) {
        self.delay = delay; self.check = check
    }

    /// The pending round trip (tests await it).
    public var pending: Task<Void, Never>? { task }

    public func update(_ expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        latest = trimmed
        task?.cancel()
        guard !trimmed.isEmpty else { status = .idle; lastValid = nil; task = nil; return }
        if trimmed == lastValid { status = .valid; return }
        status = .validating
        let delay = self.delay
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, self.latest == trimmed else { return }
            do {
                let result = try await self.check(trimmed)
                guard !Task.isCancelled, self.latest == trimmed else { return }
                if result.valid { self.lastValid = trimmed; self.status = .valid }
                else { self.lastValid = nil; self.status = .invalid(result.messages) }
            } catch {
                guard self.latest == trimmed else { return }
                self.status = .idle
            }
        }
    }

    public func canConfirm(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && status == .valid && lastValid == trimmed
    }

    /// `Formula #NAME?: Unknown function: BOGUS` → `#NAME?: Unknown function: BOGUS`.
    public nonisolated static func displayMessage(_ raw: String) -> String {
        guard let range = raw.range(of: #"^Formula\s+"#, options: .regularExpression) else { return raw }
        return String(raw[range.upperBound...])
    }

    /// The fixture's validate rule, for the demo (no server): balanced quotes and parentheses and
    /// every `NAME(` a known function. Never evaluates anything.
    public nonisolated static func localCheck(_ expression: String, functions: Set<String>) -> FormulaCheck {
        var depth = 0
        var inString = false
        for character in expression {
            if character == "\"" { inString.toggle(); continue }
            if inString { continue }
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1; if depth < 0 { break } }
        }
        if inString || depth != 0 { return FormulaCheck(valid: false, messages: ["#ERROR!: Mismatched parentheses"]) }
        let pattern = try! NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*\("#)
        // Names inside string literals are text, not calls.
        let code = expression.replacingOccurrences(of: #""[^"]*""#, with: "\"\"", options: .regularExpression)
        let text = code as NSString
        for match in pattern.matches(in: code, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: match.range(at: 1)).uppercased()
            if !functions.contains(name) { return FormulaCheck(valid: false, messages: ["#NAME?: Unknown function: \(name)"]) }
        }
        return FormulaCheck(valid: true, messages: [])
    }
}
