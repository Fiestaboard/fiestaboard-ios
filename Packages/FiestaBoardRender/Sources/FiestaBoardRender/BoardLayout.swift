// Vendored from fiestaboard-appletv@a3df9c9 Sources/Core/BoardLayout.swift. MIT: ThirdPartyNotices/FiestaBoardTV-MIT.txt.
import CoreGraphics
import Foundation

/// How the board is sized against the screen.
public enum BoardSizing: String, Codable, CaseIterable, Sendable {
    /// Fill the screen, preserving aspect. The default: a panel's grid was
    /// auto-fit for whatever TV its owner typed in, which is rarely this one.
    case fit
    /// Flaps at real Vestaboard size, accepting margins.
    case trueScale
}

/// One flap, positioned.
public struct TileRect: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let radius: Double
    public let cell: BoardCell
}

/// A board reduced to rectangles.
///
/// Pure geometry with no drawing: the renderer paints this, the tests do
/// arithmetic on it, and the future Compose implementation reuses the shape
/// of it verbatim.
public struct BoardLayout: Sendable {

    public let tiles: [TileRect]
    public let width: Double
    public let height: Double
    public let tileHeight: Double
    /// Vertical stretch (W4): tiles, gutters and seams are this much taller than the width-bound
    /// board's; widths are unchanged. 1 = the hardware's aspect. Hosts that give a board more
    /// height than its width needs (the editor's stage) use it instead of a `scaleEffect`, so the
    /// letters are drawn, not smeared.
    public private(set) var stretch: Double = 1

    /// Glyph font size as a fraction of tile height. FiestaUI uses 0.38–0.40
    /// (`board-metrics.ts`), which leaves letters a third of the flap tall and
    /// unreadable at phone sizes. A real split-flap letter fills well over half
    /// the flap: at 0.72 Spline Sans Mono's cap height (0.727 em) is 0.52 of the
    /// tile height and its advance (0.60 em) is 0.62 of the tile width
    /// (`BoardGeometry.tileWidthRatio` 0.70). iOS-R2, wave 2.
    public static let fontSizeRatio = 0.72

    /// Letters grow a little with a stretch (never past `maxGlyphStretch`), keeping their shape.
    public var fontSize: Double { tileHeight * Self.fontSizeRatio * min(stretch, Self.maxGlyphStretch) }
    public static let maxGlyphStretch = 1.15

    /// The size `make` would produce, without building its tiles.
    ///
    /// Laying a board out is a two-pass job and only the second pass needs
    /// the tiles; so is asking whether a grid suits a screen. An 85" panel
    /// is 810 tiles, so measuring through `make` allocated a whole board to
    /// read two numbers off it.
    public static func size(rows: Int, cols: Int,
                            tileHeight: Double, seams: NoteSeams? = nil, stretch: Double = 1) -> (width: Double, height: Double) {
        guard rows > 0, cols > 0, tileHeight > 0 else { return (0, 0) }
        let s = stretch.isFinite ? max(stretch, 0.01) : 1
        let gutter = tileHeight * BoardGeometry.tileGutterRatio
        let colPitch = tileHeight * BoardGeometry.tileWidthRatio + gutter
        let rowPitch = tileHeight + gutter
        let extra = tileHeight * NoteSeams.extraRatio
        let colSeams = seams.map { Double((cols - 1) / $0.everyCols) } ?? 0
        let rowSeams = seams.map { Double((rows - 1) / $0.everyRows) } ?? 0
        // Borderless: the trailing gutter is not part of the board.
        return (Double(cols) * colPitch - gutter + colSeams * extra,
                (Double(rows) * rowPitch - gutter + rowSeams * extra) * s)
    }

    /// Note-array seams (mobile addition; neither TV app has them): a wider
    /// gutter after every 15th column and every 3rd row so the individual
    /// Notes read as separate boards (FiestaUI `board-display.js:202-226`).
    public struct NoteSeams: Equatable, Sendable {
        public let everyCols: Int
        public let everyRows: Int
        /// Extra gutter at a seam as a fraction of tile height (web: 8px seam
        /// against a 5px gap on a 34px md tile → about 0.15·h more).
        public static let extraRatio = 0.16
        public static let notes = NoteSeams(everyCols: BoardGeometry.noteCols, everyRows: BoardGeometry.noteRows)
        public init(everyCols: Int, everyRows: Int) {
            self.everyCols = max(1, everyCols); self.everyRows = max(1, everyRows)
        }
    }

    public static func make(rows: Int, cols: Int, cells: [[BoardCell]], tileHeight: Double,
                            seams: NoteSeams? = nil, stretch: Double = 1) -> BoardLayout {
        let s = stretch.isFinite ? max(stretch, 0.01) : 1
        // The dimension ceiling is a second belt behind `PanelFrame`'s decode
        // clamp: `rows * cols` below is an unchecked Int multiply feeding
        // `reserveCapacity`, and a grid assembled in code rather than decoded
        // would otherwise still reach it. An empty layout is what every
        // caller already handles for a grid it cannot draw.
        guard rows > 0, cols > 0, tileHeight > 0,
              rows <= BoardFrame.maxDimension, cols <= BoardFrame.maxDimension else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: max(tileHeight, 0))
        }

        let h = tileHeight
        let tileWidth = h * BoardGeometry.tileWidthRatio
        let gutter = h * BoardGeometry.tileGutterRatio
        let radius = h * BoardGeometry.tileRadiusRatio
        let colPitch = tileWidth + gutter
        let rowPitch = h + gutter
        let extra = h * NoteSeams.extraRatio

        var tiles: [TileRect] = []
        tiles.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                // Short or ragged frames pad with blanks: a reshape in flight
                // is a normal transient state, not a crash.
                let cell: BoardCell = (row < cells.count && col < cells[row].count)
                    ? cells[row][col] : .blank
                let colSeams = seams.map { Double(col / $0.everyCols) } ?? 0
                let rowSeams = seams.map { Double(row / $0.everyRows) } ?? 0
                tiles.append(TileRect(row: row, col: col,
                                      x: Double(col) * colPitch + colSeams * extra,
                                      y: (Double(row) * rowPitch + rowSeams * extra) * s,
                                      width: tileWidth, height: h * s, radius: radius,
                                      cell: cell))
            }
        }

        let total = size(rows: rows, cols: cols, tileHeight: h, seams: seams, stretch: s)
        return BoardLayout(tiles: tiles, width: total.width, height: total.height, tileHeight: h, stretch: s)
    }

    /// Lay the board out at whatever tile height makes it meet the screen
    /// the way `mode` asks for.
    public static func fitting(rows: Int, cols: Int, cells: [[BoardCell]],
                               in screen: CGSize, mode: BoardSizing,
                               diagonalInches: Double = 0, calibration: Double = 1,
                               colPitchIn: Double = BoardGeometry.colPitchIn,
                               seams: NoteSeams? = nil) throws -> BoardLayout {
        guard screen.width > 0, screen.height > 0 else {
            throw BoardGeometry.Error.nonPositive("screen \(screen.width)×\(screen.height)")
        }
        guard rows > 0, cols > 0 else {
            return BoardLayout(tiles: [], width: 0, height: 0, tileHeight: 0)
        }

        // Measure once at a reference height, then rescale. This is the
        // same two-pass shape the web viewer uses (render, measure the grid,
        // apply a transform) without needing a real measurement.
        let reference = 100.0
        let base = size(rows: rows, cols: cols, tileHeight: reference, seams: seams)

        let scale: Double
        switch mode {
        case .fit:
            scale = try BoardGeometry.fitScale(gridWidthPx: base.width, gridHeightPx: base.height,
                                               screenWidthPx: Double(screen.width),
                                               screenHeightPx: Double(screen.height))
        case .trueScale:
            scale = try BoardGeometry.autofitScale(
                AutofitScaleInput(screenWidthPx: Double(screen.width),
                                  screenHeightPx: Double(screen.height),
                                  diagonalInches: diagonalInches,
                                  cols: cols,
                                  gridWidthPx: base.width, gridHeightPx: base.height,
                                  calibration: calibration, colPitchIn: colPitchIn))
        }

        return make(rows: rows, cols: cols, cells: cells, tileHeight: reference * scale, seams: seams)
    }
}
