import Foundation

/// One rich cell (`BoardTokenJson`, web `templates.ts:85-92`): `{type:"char", value}`
/// or `{type:"color", code:"63".."71"}`, plus optional span colour, background and icon.
public struct BoardToken: Sendable, Equatable {
    public enum Kind: String, Sendable { case char, color }
    public var kind: Kind
    public var value: String?
    public var code: Int?
    public var color: String?
    public var background: String?
    public var icon: String?
    public init(kind: Kind, value: String? = nil, code: Int? = nil, color: String? = nil,
                background: String? = nil, icon: String? = nil) {
        self.kind = kind; self.value = value; self.code = code
        self.color = color; self.background = background; self.icon = icon
    }
    public static func char(_ value: String) -> BoardToken { BoardToken(kind: .char, value: value) }
    public static func color(_ code: Int) -> BoardToken { BoardToken(kind: .color, code: code) }

    /// Decodes the wire JSON; nil for anything unrecognised.
    public init?(json: Any) {
        guard let object = json as? [String: Any], let type = object["type"] as? String,
              let kind = Kind(rawValue: type) else { return nil }
        self.kind = kind
        value = object["value"] as? String
        if let code = object["code"] as? String {
            // A tile may spell its colour by name (`"white"`, FiestaUI `BoardToken`).
            self.code = Int(code) ?? BoardMessageParser.named[code.lowercased()]
        } else { code = DisplayModel.int(object["code"]) }
        color = object["color"] as? String
        background = object["background"] as? String
        icon = object["icon"] as? String
    }
}

/// `{x, y, width, height, rgba}` pixel layer composited over LED cells.
public struct PixelLayer: Sendable, Equatable {
    public var x: Int, y: Int, w: Int, h: Int
    public var rgba: Data
    public init(x: Int, y: Int, w: Int, h: Int, rgba: Data) { self.x = x; self.y = y; self.w = w; self.h = h; self.rgba = rgba }
}

/// What to draw on a board (design/board-display-visuals.md §2.2).
public struct BoardFrame: Sendable, Equatable {
    public static let maxDimension = 256
    public var rows: Int
    public var cols: Int
    /// `characters` — the flap wire format.
    public var codes: [[Int]]?
    /// `cells` — rich tokens; win over codes and message.
    public var cells: [[BoardToken]]?
    /// Markup, parsed with FiestaUI `parseLine` rules when nothing else is present.
    public var message: String?
    public var layers: [PixelLayer]

    public init(rows: Int, cols: Int, codes: [[Int]]? = nil, cells: [[BoardToken]]? = nil,
                message: String? = nil, layers: [PixelLayer] = []) {
        self.rows = min(max(rows, 0), Self.maxDimension)
        self.cols = min(max(cols, 0), Self.maxDimension)
        self.codes = codes; self.cells = cells; self.message = message; self.layers = layers
    }

    public static func empty(rows: Int, cols: Int) -> BoardFrame { BoardFrame(rows: rows, cols: cols) }

    /// Editor / thumbnail path: rendered lines (`/templates/render` `lines`) as markup rows.
    public static func fromLines(_ lines: [String], rows: Int, cols: Int) -> BoardFrame {
        BoardFrame(rows: rows, cols: cols, message: lines.joined(separator: "\n"))
    }

    public var isEmpty: Bool { codes == nil && cells == nil && (message ?? "").isEmpty }

    /// Resolve to flap cells. Precedence: `cells` → `characters` → `message`.
    /// (The web's rule is cells over message; on a split-flap board the
    /// `characters` grid is the exact wire frame, so it outranks re-parsing
    /// the message, which can only approximate it.)
    public func boardCells(model: DisplayModel) -> [[BoardCell]] {
        let code62 = model.code62
        if let cells {
            return cells.prefix(rows).map { row in row.prefix(cols).map { Self.cell($0, code62: code62, preserveCase: model.preservesCase) } }
        }
        if let codes {
            return codes.prefix(rows).map { row in row.prefix(cols).map { BoardTables.cell(forCode: $0, code62: code62) } }
        }
        if let message, !message.isEmpty {
            return BoardMessageParser.cells(message, rows: rows, cols: cols, preserveCase: model.preservesCase)
                .map { row in row.map { Self.cell($0, code62: code62, preserveCase: model.preservesCase) } }
        }
        return []
    }

    static func cell(_ token: BoardToken, code62: Code62Glyph, preserveCase: Bool) -> BoardCell {
        switch token.kind {
        case .color:
            return token.code.flatMap(BoardColor.init(code:)).map(BoardCell.color) ?? .blank
        case .char:
            if token.icon == "heart" { return .character("♥") }
            guard let value = token.value, let first = value.first, first != " " else { return .blank }
            let glyph = preserveCase ? first : Character(String(first).uppercased())
            if glyph == "°" || glyph == "♥" { return .character(glyph) }
            if preserveCase { return .character(glyph) }
            return BoardTables.code(for: .character(glyph)) == 0 ? .blank : .character(glyph)
        }
    }

    /// Lines of text the board reads, colour tiles as spaces (stage AX value).
    public func lines(model: DisplayModel) -> [String] {
        boardCells(model: model).map { row in
            String(row.map { cell -> Character in
                if case .character(let c) = cell { return c }
                return " "
            })
        }
    }
}

extension BoardSpeech {
    /// What a VoiceOver user hears for a board: its message, else its flaps read back.
    public static func spoken(_ frame: BoardFrame, model: DisplayModel) -> String {
        // Read the flaps back: a message may carry markup that is not speech.
        spoken(message: nil, cells: frame.boardCells(model: model))
    }
}
