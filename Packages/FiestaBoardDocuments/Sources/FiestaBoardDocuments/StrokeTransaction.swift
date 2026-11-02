import Foundation

/// Draw on board (PLAN B23): cell-level painting of template rows, a port of the web's
/// `utils/draw-mode.ts` and `utils/stroke-transaction.ts` (`FiestaBoard@v10.3.2`).
///
/// A *positional* row maps 1:1 to board cells: each literal character is one cell and each colour
/// marker (`{{red}}`) is one cell. Dynamic tokens (variables, formulas, flexible space) have no
/// fixed width, so painting a row drops them; the user is choosing to draw over them, and Undo
/// restores them. A stroke rewrites only the rows it touched and forces those rows to left
/// alignment without wrap, so the painted cells land where they were drawn; the whole stroke is
/// one undo step that also restores each row's previous alignment and wrap.
public enum DrawBrush: Equatable, Sendable {
    case color(String)
    case eraser
    case character(String)
}

public struct CellPaint: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public init(row: Int, col: Int) { self.row = row; self.col = col }
}

public enum DrawMode {
    /// Board colours in the web toolbar's order (8 swatches).
    public static let colors = ["red", "orange", "yellow", "green", "blue", "violet", "white", "black"]

    /// The stampable characters: every real character on the board (codes 1–62 minus blank and the
    /// undefined slots), as `DRAW_CHARS`.
    public static let characters: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890").map(String.init)
        + ["!", "@", "#", "$", "(", ")", "-", "+", "&", "=", ";", ":", "'", "\"", "%", ",", ".", "/", "?", "°"]

    /// Colour names (and aliases) the tokenizer treats as one painted cell, with their codes.
    static let colorCodes: [String: Int] = ["red": 63, "orange": 64, "yellow": 65, "green": 66, "blue": 67,
                                            "violet": 68, "purple": 68, "white": 69, "black": 70, "filled": 71]
    static let codeNames: [Int: String] = [63: "red", 64: "orange", 65: "yellow", 66: "green", 67: "blue",
                                           68: "violet", 69: "white", 70: "black", 71: "black"]

    static func colorCell(_ name: String) -> String { "{{\(name == "purple" ? "violet" : name)}}" }

    /// The cell a brush writes: `{{red}}`, a literal character, or a space (eraser). An invalid
    /// stamp erases, as the web does.
    public static func cell(for brush: DrawBrush) -> String {
        switch brush {
        case .color(let name): return colorCell(name.lowercased())
        case .eraser: return " "
        case .character(let raw):
            let upper = raw.uppercased()
            return characters.contains(upper) ? upper : " "
        }
    }

    /// Splits a row into board cells; `droppedDynamic` says a non-colour `{{…}}` was dropped.
    static func tokenize(_ line: String) -> (cells: [String], droppedDynamic: Bool) {
        var cells: [String] = []
        var dropped = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            if characters[index] == "{", index + 1 < characters.count, characters[index + 1] == "{",
               let close = closingBraces(characters, from: index + 2), close > index + 2 {
                let content = String(characters[(index + 2)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
                if colorCodes[content] != nil { cells.append(colorCell(content)) } else { dropped = true }
                index = close + 2
                continue
            }
            if characters[index] == "{", let close = characters[(index + 1)...].firstIndex(of: "}"), close > index + 1 {
                let token = String(characters[(index + 1)..<close])
                if token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                    let lower = token.lowercased()
                    if colorCodes[lower] != nil { cells.append(colorCell(lower)); index = close + 1; continue }
                    if let code = Int(lower), let name = codeNames[code] { cells.append(colorCell(name)); index = close + 1; continue }
                }
            }
            cells.append(String(characters[index]))
            index += 1
        }
        return (cells, dropped)
    }

    /// `}}` after `start` with no `}` before it (the web's `[^}]+` match).
    private static func closingBraces(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < characters.count {
            if characters[index] == "}" { return characters[index + 1] == "}" ? index : nil }
            index += 1
        }
        return nil
    }

    public static func cells(_ line: String) -> [String] { tokenize(line).cells }

    /// Cells back to a row, trailing blanks trimmed.
    public static func line(_ cells: [String]) -> String {
        var end = cells.count
        while end > 0 && cells[end - 1] == " " { end -= 1 }
        return cells[..<end].joined()
    }

    /// True when the row maps 1:1 to cells (no variable, formula or flexible space).
    public static func isPositional(_ line: String) -> Bool { !tokenize(line).droppedDynamic }

    /// One row with `paints` (column → cell) applied; cut at `cols`; dynamic tokens dropped.
    public static func paint(_ line: String, _ paints: [(col: Int, cell: String)], cols: Int) -> String {
        var cells = self.cells(line)
        if cells.count > cols { cells.removeLast(cells.count - cols) }
        for paint in paints where paint.col >= 0 && paint.col < cols {
            while cells.count <= paint.col { cells.append(" ") }
            cells[paint.col] = paint.cell
        }
        return self.line(cells)
    }

    /// A positional row as stage markup (`{{red}}` → `{red}`), for the instant local preview.
    public static func stageLine(_ line: String) -> String {
        cells(line).map { cell in
            guard cell.hasPrefix("{{"), cell.hasSuffix("}}") else { return cell }
            return "{" + cell.dropFirst(2).dropLast(2) + "}"
        }.joined()
    }
}

/// One committed stroke: the rows it repaints and the metadata it forces. Pure; the session applies
/// it as one undo step (`DocumentEditingSession.applyStroke`).
public struct StrokeTransaction: Equatable, Sendable {
    /// Every row of the document after the stroke (rows below the last one are added when painted).
    public let rows: [String]
    /// The rows the stroke touched, ascending.
    public let paintedRows: [Int]

    /// Builds the stroke, or nil when nothing would change (no cells, or every cell already held).
    public init?(rows current: [String], paints: [CellPaint], brush: DrawBrush, cols: Int) {
        guard cols > 0 else { return nil }
        let cell = DrawMode.cell(for: brush)
        var byRow: [Int: [(col: Int, cell: String)]] = [:]
        for paint in paints where paint.row >= 0 && paint.col >= 0 && paint.col < cols {
            byRow[paint.row, default: []].append((paint.col, cell))
        }
        guard !byRow.isEmpty else { return nil }
        var rows = current
        if let last = byRow.keys.max(), last >= rows.count { rows += Array(repeating: "", count: last - rows.count + 1) }
        for (row, cells) in byRow { rows[row] = DrawMode.paint(rows[row], cells, cols: cols) }
        self.rows = rows
        paintedRows = byRow.keys.sorted()
    }

    /// The stage while drawing (web `drawPreviewMessage`): painted rows show exactly what committing
    /// will produce; positional rows that are left-aligned without wrap are drawn locally; the rest
    /// keep the server's last render. Returns stage markup, one line per board row.
    public static func preview(rows: [String], serverLines: [String], alignment: (Int) -> String, wrap: (Int) -> Bool,
                               pending: [CellPaint], brush: DrawBrush, boardRows: Int, cols: Int) -> [String] {
        let cell = DrawMode.cell(for: brush)
        var byRow: [Int: [(col: Int, cell: String)]] = [:]
        for paint in pending { byRow[paint.row, default: []].append((paint.col, cell)) }
        return (0..<max(0, boardRows)).map { row in
            let template = row < rows.count ? rows[row] : ""
            if let paints = byRow[row] { return DrawMode.stageLine(DrawMode.paint(template, paints, cols: cols)) }
            if DrawMode.isPositional(template) && alignment(row) == "left" && !wrap(row) {
                return DrawMode.stageLine(DrawMode.paint(template, [], cols: cols))
            }
            return row < serverLines.count ? serverLines[row] : ""
        }
    }
}

extension PageDocument {
    /// Applies a stroke: the painted rows' text, and left alignment without wrap on exactly those
    /// rows. Entries are written only where the row's alignment or wrap actually changes, so an
    /// absent `line_metadata` stays absent for a left/no-wrap page (PLAN §2.2 lossless rule).
    public mutating func applyStroke(_ stroke: StrokeTransaction) throws {
        try replaceTemplateRows(stroke.rows)
        for row in stroke.paintedRows {
            if lineAlignment(at: row) != "left" { try setLineAlignment(at: row, alignment: "left") }
            if lineWrap(at: row) { try setLineWrap(at: row, wrap: false) }
        }
    }
}
