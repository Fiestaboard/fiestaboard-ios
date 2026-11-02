import SwiftUI
import FiestaBoardDocuments
import FiestaBoardRender

/// Draw on board (PLAN B23): the brush, the cells of the stroke in progress, and the commit.
/// Dragging across the stage paints tiles at once (no flap animation); releasing commits one
/// `StrokeTransaction` as one undo step.
@MainActor final class DrawModeController: ObservableObject {
    @Published var brush: DrawBrush = .color("red")
    /// Cells of the stroke in progress, in the order they were reached, without repeats.
    @Published private(set) var pending: [CellPaint] = []
    private var last: CellPaint?

    /// Adds a cell, filling the cells between it and the previous one so a fast drag leaves no gaps.
    func add(_ cell: CellPaint) {
        if let last, last == cell { return }
        let path = last.map { Self.line(from: $0, to: cell) } ?? [cell]
        for step in path where !pending.contains(step) { pending.append(step) }
        last = cell
    }

    /// The stroke to commit (nil when it changes nothing); clears the pending cells either way.
    func finish(rows: [String], cols: Int) -> StrokeTransaction? {
        defer { pending = []; last = nil }
        return StrokeTransaction(rows: rows, paints: pending, brush: brush, cols: cols)
    }
    func cancel() { pending = []; last = nil }

    /// Cells on the straight line between two cells (Bresenham), both ends included.
    static func line(from start: CellPaint, to end: CellPaint) -> [CellPaint] {
        var cells: [CellPaint] = []
        var x = start.col, y = start.row
        let dx = abs(end.col - x), dy = -abs(end.row - y)
        let sx = x < end.col ? 1 : -1, sy = y < end.row ? 1 : -1
        var error = dx + dy
        while true {
            cells.append(CellPaint(row: y, col: x))
            if x == end.col && y == end.row { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += sx }
            if doubled <= dx { error += dx; y += sy }
        }
        return cells
    }

    /// The tile under a point of the stage board (board coordinates before the stage's vertical
    /// stretch), or the nearest tile when the point falls in a gutter; nil outside the tiles.
    /// Geometry follows `BoardFrameView`: the board fills `size` at its flap aspect, its canvas
    /// sits inside the bezel padding and border, and tiles come from `BoardLayout`.
    nonisolated static func cell(at point: CGPoint, size: CGSize, model: DisplayModel) -> CellPaint? {
        guard size.width > 0, size.height > 0, model.rows > 0, model.cols > 0 else { return nil }
        let reference = BoardLayout.size(rows: model.rows, cols: model.cols, tileHeight: 100, seams: model.seams)
        let outerWidth = reference.width + 2 * 100 * (BoardFrameView.bezelPadX + BoardFrameView.bezelBorder)
        let outerHeight = reference.height + 2 * 100 * (BoardFrameView.bezelPadY + BoardFrameView.bezelBorder)
        let scale = min(Double(size.width) / outerWidth, Double(size.height) / outerHeight)
        let h = 100 * scale
        let boardWidth = outerWidth * scale, boardHeight = outerHeight * scale
        let originX = (Double(size.width) - boardWidth) / 2 + h * (BoardFrameView.bezelPadX + BoardFrameView.bezelBorder)
        let originY = (Double(size.height) - boardHeight) / 2 + h * (BoardFrameView.bezelPadY + BoardFrameView.bezelBorder)
        let cells = Array(repeating: Array(repeating: BoardCell.blank, count: model.cols), count: model.rows)
        let layout = BoardLayout.make(rows: model.rows, cols: model.cols, cells: cells, tileHeight: h, seams: model.seams)
        let x = Double(point.x) - originX, y = Double(point.y) - originY
        guard x >= -h * 0.2, y >= -h * 0.2, x <= layout.width + h * 0.2, y <= layout.height + h * 0.2 else { return nil }
        var best: (TileRect, Double)?
        for tile in layout.tiles {
            let dx = x - (tile.x + tile.width / 2), dy = y - (tile.y + tile.height / 2)
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.1 { best = (tile, distance) }
        }
        return best.map { CellPaint(row: $0.0.row, col: $0.0.col) }
    }
}

/// The transparent layer over the stage board that turns a drag into painted cells.
struct DrawCanvasOverlay: View {
    let size: CGSize
    let model: DisplayModel
    @ObservedObject var controller: DrawModeController
    var onCommit: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if let cell = DrawModeController.cell(at: value.location, size: size, model: model) { controller.add(cell) }
                }
                .onEnded { _ in onCommit() })
            // Hidden from VoiceOver/XCUI so the stage keeps reading its lines (`boardStage` value).
            .accessibilityHidden(true)
    }
}

/// Draw mode's toolbar (B23): 8 colour swatches, the eraser, a stamp picker, Undo/Redo and Done.
struct DrawModeBar: View {
    @ObservedObject var controller: DrawModeController
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DrawMode.colors, id: \.self) { color in
                        swatch(.color(color), label: "\(color.capitalized) brush", id: "drawBrush_\(color)") {
                            Image(uiImage: ColorPickerView.tile(color, size: 24))
                        }
                    }
                    swatch(.eraser, label: CatalogStrings.eraser, id: "drawBrush_eraser") {
                        Image(systemName: "eraser").font(.body.weight(.medium)).frame(width: 22, height: 26)
                    }
                    Menu {
                        ForEach(DrawMode.characters, id: \.self) { character in
                            Button(character) { controller.brush = .character(character) }
                        }
                    } label: {
                        let stamp: String? = { if case .character(let c) = controller.brush { return c }; return nil }()
                        Text(stamp ?? "A").font(.body.monospaced().weight(.bold)).frame(width: 28, height: 30)
                            .background(stamp != nil ? Color.accentColor.opacity(0.2) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(stamp != nil ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .accessibilityLabel(CatalogStrings.stamp)
                    .accessibilityIdentifier("drawStamp")
                    Divider().frame(height: 22).padding(.horizontal, 2)
                    Button(action: onUndo) { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30) }
                        .disabled(!canUndo).accessibilityLabel(EditorStrings.undo).accessibilityIdentifier("drawUndo")
                    Button(action: onRedo) { Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 30) }
                        .disabled(!canRedo).accessibilityLabel(EditorStrings.redo).accessibilityIdentifier("drawRedo")
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                Label(CatalogStrings.drawHint, systemImage: "pencil.tip").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("drawHint")
                Spacer(minLength: 8)
                Button(CatalogStrings.done, action: onDone).bold()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(CatalogStrings.doneDrawing)
                    .accessibilityIdentifier("drawDone")
            }
        }
        .buttonStyle(.borderless)
    }

    private func swatch<Content: View>(_ brush: DrawBrush, label: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        let selected = controller.brush == brush
        return Button { controller.brush = brush } label: {
            content()
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
