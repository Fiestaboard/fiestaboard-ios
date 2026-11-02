import SwiftUI
import FiestaBoardDocuments

/// Drag across the page's character grid to choose a canvas's area (web `CanvasAreaPicker`). Every
/// canvas shows as a labelled outline; the one being edited is filled. While the finger moves the
/// area is reported as `onChanging` (the stage follows at once); on release it is `onCommit`.
struct CanvasAreaPicker: View {
    var rows: Int
    var cols: Int
    var canvases: [LegacyCanvas]
    var activeID: String?
    /// Width / height of one character cell (the board's glyph pitch, e.g. 4 × 6 on a 3×5 face).
    var cellAspect: CGFloat
    var onChanging: (CanvasArea) -> Void
    var onCommit: (CanvasArea) -> Void

    @State private var dragStart: (row: Int, col: Int)?

    var body: some View {
        GeometryReader { proxy in
            let cell = CGSize(width: proxy.size.width / CGFloat(max(cols, 1)), height: proxy.size.height / CGFloat(max(rows, 1)))
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.1)))
                    var grid = Path()
                    for c in 0...cols { grid.move(to: CGPoint(x: CGFloat(c) * cell.width, y: 0)); grid.addLine(to: CGPoint(x: CGFloat(c) * cell.width, y: size.height)) }
                    for r in 0...rows { grid.move(to: CGPoint(x: 0, y: CGFloat(r) * cell.height)); grid.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cell.height)) }
                    context.stroke(grid, with: .color(.white.opacity(0.15)), lineWidth: 0.5)
                    for canvas in canvases {
                        guard let area = canvas.area?.clamped(rows: rows, cols: cols) else { continue }
                        let rect = CGRect(x: CGFloat(area.col - 1) * cell.width, y: CGFloat(area.row - 1) * cell.height,
                                          width: CGFloat(area.cols) * cell.width, height: CGFloat(area.rows) * cell.height)
                        let active = canvas.id == activeID
                        if active { context.fill(Path(rect), with: .color(Color.indigo.opacity(0.35))) }
                        context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(active ? Color(red: 0.51, green: 0.55, blue: 0.97) : .gray), lineWidth: 2)
                        context.draw(Text(canvas.id).font(.system(size: 10)).foregroundStyle(.white), at: CGPoint(x: rect.minX + 3, y: rect.minY + 2), anchor: .topLeading)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    // Only a drag that starts on the grid selects (a scroll grazing its edge doesn't).
                    guard inside(value.startLocation, proxy.size) else { return }
                    let start = dragStart ?? cellAt(value.startLocation, cell)
                    dragStart = start
                    onChanging(CanvasArea.between(start, cellAt(value.location, cell)))
                }
                .onEnded { value in
                    guard inside(value.startLocation, proxy.size) else { dragStart = nil; return }
                    let start = dragStart ?? cellAt(value.startLocation, cell)
                    dragStart = nil
                    onCommit(CanvasArea.between(start, cellAt(value.location, cell)))
                })
        }
        .aspectRatio(CGFloat(cols) * cellAspect / CGFloat(max(rows, 1)), contentMode: .fit)
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(uiColor: .separator)))
        .accessibilityElement()
        .accessibilityLabel("Board grid with the page's canvases")
        .accessibilityValue(activeArea.map { "Rows \($0.row) to \($0.row + $0.rows - 1), columns \($0.col) to \($0.col + $0.cols - 1)" } ?? "No area")
        .accessibilityHint(CanvasStrings.areaPickerHint)
        .accessibilityIdentifier("canvasAreaPicker")
    }

    private var activeArea: CanvasArea? { canvases.first(where: { $0.id == activeID })?.area }

    private func inside(_ p: CGPoint, _ size: CGSize) -> Bool { p.x >= 0 && p.y >= 0 && p.x <= size.width && p.y <= size.height }

    private func cellAt(_ point: CGPoint, _ cell: CGSize) -> (row: Int, col: Int) {
        (min(rows - 1, max(0, Int(point.y / max(cell.height, 1)))), min(cols - 1, max(0, Int(point.x / max(cell.width, 1)))))
    }
}
