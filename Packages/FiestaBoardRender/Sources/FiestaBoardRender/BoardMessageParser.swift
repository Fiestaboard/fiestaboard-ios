import Foundation

/// Board markup → cells, per FiestaUI `parseLine` (`board-characters.js:182-248`,
/// design/board-display-visuals.md §1.2):
///
/// - `{red}`…`{black}`, `{purple}` (violet), `{filled}` (71) and `{63}`…`{71}` are colour tiles;
/// - `{/red}` close tags are skipped;
/// - `{icon:heart}` is the heart glyph; other `{icon:name}` keep their name on the token;
/// - `{red/blue:TEXT}` and `{red:TEXT}` spans give their characters `color`/`background`
///   (LED only; flap boards draw the plain characters);
/// - any other `{…}` stays literal;
/// - text is uppercased unless `preserveCase`.
///
/// Lines split on `\n`; each row is cut at `cols` and padded with blanks; rows
/// beyond `rows` are dropped.
public enum BoardMessageParser {

    static let named: [String: Int] = [
        "red": 63, "orange": 64, "yellow": 65, "green": 66, "blue": 67,
        "violet": 68, "purple": 68, "white": 69, "black": 70, "filled": 71,
    ]

    public static func cells(_ message: String, rows: Int, cols: Int, preserveCase: Bool) -> [[BoardToken]] {
        guard rows > 0, cols > 0 else { return [] }
        let lines = message.components(separatedBy: "\n")
        return (0..<rows).map { index in
            var row = index < lines.count ? line(lines[index], preserveCase: preserveCase) : []
            if row.count > cols { row = Array(row.prefix(cols)) }
            while row.count < cols { row.append(.char(" ")) }
            return row
        }
    }

    public static func line(_ text: String, preserveCase: Bool) -> [BoardToken] {
        var tokens: [BoardToken] = []
        let characters = Array(text)
        var index = 0
        func emit(_ character: Character, color: String? = nil, background: String? = nil) {
            let value = preserveCase ? String(character) : String(character).uppercased()
            tokens.append(BoardToken(kind: .char, value: value, color: color, background: background))
        }
        while index < characters.count {
            let character = characters[index]
            if character == "{", let close = characters[index...].firstIndex(of: "}") {
                let body = String(characters[(index + 1)..<close])
                let lower = body.lowercased()
                if let code = named[lower] ?? Int(body).flatMap({ (63...71).contains($0) ? $0 : nil }) {
                    tokens.append(.color(code)); index = close + 1; continue
                }
                if lower.hasPrefix("/"), named[String(lower.dropFirst())] != nil {
                    index = close + 1; continue
                }
                if lower.hasPrefix("icon:") {
                    let name = String(body.dropFirst(5))
                    if name.lowercased() == "heart" { tokens.append(.char("♥")) }
                    else { tokens.append(BoardToken(kind: .char, value: " ", icon: name)) }
                    index = close + 1; continue
                }
                if let colon = body.firstIndex(of: ":") {
                    let head = body[..<colon].lowercased()
                    let parts = head.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                    if !parts.isEmpty, parts.count <= 2, parts.allSatisfy({ named[$0] != nil }) {
                        let span = body[body.index(after: colon)...]
                        for glyph in span { emit(glyph, color: parts[0], background: parts.count == 2 ? parts[1] : nil) }
                        index = close + 1; continue
                    }
                }
            }
            emit(character)
            index += 1
        }
        return tokens
    }
}
