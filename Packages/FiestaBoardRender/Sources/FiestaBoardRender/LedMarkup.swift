import Foundation

/// A parsed board cell for the LED path, spelled the way FiestaUI's
/// `BoardToken` is (`board-characters.ts`): a tile keeps its code as written
/// (`"red"`, `"63"`), spans carry `color` / `background` as written (a board
/// colour code or `#rrggbb`), and an icon token is already its split-flap
/// fallback, tagged with the canonical icon name.
struct LedToken: Sendable, Equatable {
    var isTile: Bool
    /// The character (one code point, possibly a multi-scalar uppercase) for a char token.
    var value: String
    /// The colour code for a tile token.
    var code: String
    var color: String?
    var background: String?
    var icon: String?

    static let blank = LedToken(isTile: false, value: " ", code: "")
    static func char(_ value: String) -> LedToken { LedToken(isTile: false, value: value, code: "") }
    static func tile(_ code: String) -> LedToken { LedToken(isTile: true, value: "", code: code) }
}

/// Board colours, icons and the extended-markup line parser, ported from
/// FiestaUI `board-colors.ts`, `board-icons.ts` and `board-characters.ts`
/// (`parseLine` with `extendedMarkup: true`).
enum LedMarkup {

    // MARK: Colours (board-colors.ts)

    static let boardRed = "#eb4034"
    static let boardBlack = "#1a1a1a"

    /// `COLOR_CODE_MAP`, in order (the first code of a hex is its canonical tile).
    static let codeMap: [(String, String)] = [
        ("63", "#eb4034"), ("64", "#f5a623"), ("65", "#f8e71c"), ("66", "#7ed321"), ("67", "#4a90d9"),
        ("68", "#9b59b6"), ("69", "#ffffff"), ("70", "#1a1a1a"), ("71", "#1a1a1a"),
    ]

    /// `ALL_COLOR_CODES`.
    static let allColorCodes: [String: String] = {
        var map: [String: String] = [:]
        for (code, hex) in codeMap { map[code] = hex }
        let named: [String: String] = [
            "red": "#eb4034", "orange": "#f5a623", "yellow": "#f8e71c", "green": "#7ed321",
            "blue": "#4a90d9", "violet": "#9b59b6", "purple": "#9b59b6", "white": "#ffffff",
            "black": "#1a1a1a", "filled": "#1a1a1a",
        ]
        map.merge(named) { a, _ in a }
        return map
    }()

    /// `TILE_CODE_BY_HEX`: hex → its first numeric code.
    static let tileCodeByHex: [String: String] = {
        var map: [String: String] = [:]
        for (code, hex) in codeMap where map[hex] == nil { map[hex] = code }
        return map
    }()

    /// `resolveColorCode(code, false)`.
    static func resolveColorCode(_ code: String) -> String { allColorCodes[code] ?? boardBlack }

    static let offTileCodes: Set<String> = ["70", "71", "black"]

    /// `colorCodeToHex` (led-matrix.ts): hex of a colour code or `#rrggbb`, nil for an off colour.
    static func colorCodeToHex(_ code: String) -> String? {
        if offTileCodes.contains(code) { return nil }
        if code.hasPrefix("#") { return parseHex(code) != nil ? code.lowercased() : nil }
        return resolveColorCode(code)
    }

    /// `parseHexColor`: `#rrggbb` (or without `#`, trimmed) → 0xRRGGBB.
    static func parseHex(_ hex: String) -> UInt32? {
        var s = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), s.allSatisfy(\.isASCII) else { return nil }
        return UInt32(s, radix: 16)
    }

    /// `resolveHexOption`: lowercase `#rrggbb`, or the fallback.
    static func resolveHexOption(_ value: String?, _ fallback: String?) -> String? {
        guard let value else { return fallback }
        var s = Substring(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, s.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return fallback }
        return "#" + s.lowercased()
    }

    // MARK: Icons (board-icons.ts, vendored as markup_icons.json)

    struct Icon: Sendable { let label: String; let color: String; let fallback: String? }

    static let icons: (table: [String: Icon], aliases: [String: String]) = {
        guard let data = RenderResources.data("markup_icons", "json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([:], [:]) }
        var table: [String: Icon] = [:]
        for (name, value) in json["icons"] as? [String: Any] ?? [:] {
            guard let value = value as? [String: Any] else { continue }
            table[name] = Icon(label: value["label"] as? String ?? name, color: value["color"] as? String ?? "#ffffff",
                               fallback: value["fallback"] as? String)
        }
        return (table, json["aliases"] as? [String: String] ?? [:])
    }()

    /// `resolveBoardIconName`.
    static func resolveIconName(_ name: String) -> String? {
        if icons.table[name] != nil { return name }
        return icons.aliases[name]
    }

    // MARK: parseLine (board-characters.ts)

    static let maxSpanDepth = 8
    static let shortMarkerMax = 8
    static let spanHeadMax = 16
    static let iconNameMax = 16
    static let endTagNames: Set<String> = ["red", "orange", "yellow", "green", "blue", "violet", "purple",
                                           "white", "black", "filled"]
    static let tileOnlyCodes: Set<String> = ["filled", "71"]

    struct Span { var color: String; var background: String? }

    static func lookupColorCode(_ content: String) -> String? {
        if allColorCodes[content] != nil { return content }
        let lower = content.lowercased()
        return allColorCodes[lower] != nil ? lower : nil
    }

    static func isEndTag(_ content: String) -> Bool {
        guard content.hasPrefix("/") else { return false }
        let name = content.dropFirst().lowercased()
        return name.isEmpty || endTagNames.contains(name)
    }

    static func spanColor(_ head: String) -> String? {
        if let code = lookupColorCode(head) { return tileOnlyCodes.contains(code) ? nil : code }
        if head.hasPrefix("#"), head.utf16.count == 7, parseHex(head) != nil { return head.lowercased() }
        return nil
    }

    static func spanHead(_ head: String) -> Span? {
        guard let slash = head.firstIndex(of: "/") else { return spanColor(head).map { Span(color: $0) } }
        guard let color = spanColor(String(head[..<slash])),
              let background = spanColor(String(head[head.index(after: slash)...])) else { return nil }
        return Span(color: color, background: background)
    }

    static func iconToken(_ name: String, span: Span?) -> LedToken {
        let fallback = icons.table[name]?.fallback
        var token: LedToken
        if let fallback, allColorCodes[fallback] != nil { token = .tile(fallback) } else { token = .char(fallback ?? " ") }
        token.icon = name
        return withSpan(token, span)
    }

    static func withSpan(_ token: LedToken, _ span: Span?) -> LedToken {
        guard let span else { return token }
        var token = token
        token.color = span.color
        if let background = span.background { token.background = background }
        return token
    }

    /// `parseLine(line, maxTokens, {extendedMarkup: true, preserveCase})`, over UTF-16 units as JS indexes them.
    static func parseLine(_ line: String, maxTokens: Int = .max, preserveCase: Bool) -> [LedToken] {
        let u = Array(line.utf16)
        let n = u.count
        let openBrace: UInt16 = 0x7B, closeBrace: UInt16 = 0x7D, colonUnit: UInt16 = 0x3A
        var tokens: [LedToken] = []
        let hasBrace = u.contains(openBrace)
        var close = [Int](repeating: -1, count: n)
        var match = [Int](repeating: -1, count: n)
        if hasBrace {
            var next = -1
            for i in stride(from: n - 1, through: 0, by: -1) {
                if u[i] == closeBrace { next = i }
                close[i] = next
            }
            var open: [Int] = []
            for i in 0..<n {
                if u[i] == openBrace { open.append(i) } else if u[i] == closeBrace, let o = open.popLast() { match[o] = i }
            }
        }
        func sub(_ a: Int, _ b: Int) -> String { String(decoding: u[a..<b], as: UTF16.self) }

        func walk(_ start: Int, _ end: Int, _ span: Span?, _ depth: Int) {
            var i = start
            while i < end && tokens.count < maxTokens {
                if u[i] == openBrace && hasBrace {
                    let closing = close[i]
                    if closing != -1 && closing < end {
                        if closing - i - 1 <= shortMarkerMax {
                            let content = sub(i + 1, closing)
                            if isEndTag(content) { i = closing + 1; continue }
                            if let code = lookupColorCode(content) {
                                tokens.append(.tile(code)); i = closing + 1; continue
                            }
                        }
                        var colon = -1
                        let headEnd = min(closing, i + 2 + spanHeadMax)
                        var k = i + 1
                        while k < headEnd { if u[k] == colonUnit { colon = k; break }; k += 1 }
                        if colon > i + 1 {
                            let head = sub(i + 1, colon)
                            if head.lowercased() == "icon" {
                                if closing - colon - 1 <= iconNameMax {
                                    let raw = sub(colon + 1, closing).lowercased()
                                    if raw == "heart" {
                                        tokens.append(withSpan(.char("♥"), span)); i = closing + 1; continue
                                    }
                                    if let name = resolveIconName(raw) {
                                        tokens.append(iconToken(name, span: span)); i = closing + 1; continue
                                    }
                                }
                            } else if depth < maxSpanDepth {
                                if let opened = spanHead(head), match[i] != -1 {
                                    let spanEnd = match[i]
                                    walk(colon + 1, spanEnd, opened, depth + 1)
                                    i = spanEnd + 1
                                    continue
                                }
                            }
                        }
                    }
                }
                // One cell per code point.
                var width = 1
                var scalarValue = UInt32(u[i])
                if UTF16.isLeadSurrogate(u[i]), i + 1 < n, UTF16.isTrailSurrogate(u[i + 1]) {
                    scalarValue = 0x10000 + ((UInt32(u[i]) - 0xD800) << 10) + (UInt32(u[i + 1]) - 0xDC00)
                    width = 2
                }
                let ch = Unicode.Scalar(scalarValue).map { String(Character($0)) } ?? "\u{FFFD}"
                var value = preserveCase ? ch : ch.uppercased()
                if value == "❤" { value = "♥" }
                tokens.append(withSpan(.char(value), span))
                i += width
            }
        }
        walk(0, n, nil, 0)
        return tokens
    }
}
