import SwiftUI

/// Readable board geometry, in points. A constrained viewport clips and scrolls;
/// it never scales the tile below FiestaUI's `minTile` (13 pt).
public struct BoardViewportGeometry: Equatable, Sendable {
    public static let minimumTileHeight = 13.0
    public let rows: Int
    public let cols: Int
    public let tileHeight: Double
    public let viewportWidth: Double
    public let notes: Bool
    public var columnsPerPage: Int { notes ? min(15, cols) : cols }
    public var rowsPerPage: Int { notes ? min(3, rows) : rows }
    public var notesAcross: Int { notes ? max(1, (cols + 14) / 15) : 1 }
    public var noteCount: Int { notesAcross * (notes ? max(1, (rows + 2) / 3) : 1) }
    public var contentWidth: Double { BoardLayout.size(rows: rows, cols: cols, tileHeight: tileHeight).width }
    public var scrolls: Bool { contentWidth > viewportWidth || noteCount > 1 }
    public init(rows: Int, cols: Int, viewportWidth: Double, tileHeight: Double = 13, notes: Bool = false) {
        self.rows = min(BoardFrame.maxDimension, max(0, rows))
        self.cols = min(BoardFrame.maxDimension, max(0, cols))
        self.viewportWidth = viewportWidth.isFinite ? max(0, viewportWidth) : 0
        self.tileHeight = tileHeight.isFinite ? min(200, max(Self.minimumTileHeight, tileHeight)) : Self.minimumTileHeight
        self.notes = notes
    }
    public func bounds(page: Int) -> (rows: Range<Int>, cols: Range<Int>) {
        let index = min(noteCount - 1, max(0, page))
        let y = notes ? (index / notesAcross) * 3 : 0
        let x = notes ? (index % notesAcross) * 15 : 0
        return (min(rows, y)..<min(rows, y + rowsPerPage), min(cols, x)..<min(cols, x + columnsPerPage))
    }
    public func next(after page: Int) -> Int { min(noteCount - 1, max(0, page) + 1) }
    public func previous(before page: Int) -> Int { max(0, min(noteCount - 1, page) - 1) }
    public func label(page: Int) -> String { "Note \(min(noteCount, max(1, page + 1))) of \(noteCount)" }
}

/// A fixed hardware surround containing readable, horizontally scrolling content.
/// A Note array pages by complete Notes, in row-major order. Thumbnails keep
/// using `BoardThumbnail`; the owner's thumbnail exemption does not apply here.
public struct BoardViewport: View {
    private let frame: BoardFrame
    private let model: DisplayModel
    private let tileHeight: Double
    @State private var page: Int? = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(frame: BoardFrame, model: DisplayModel, tileHeight: Double = 13) {
        self.frame = frame
        self.model = model
        self.tileHeight = tileHeight
    }

    public var body: some View {
        if model.technology == .ledMatrix {
            matrixViewport
        } else {
            flapViewport
        }
    }

    private var matrixViewport: some View {
        let raster = LedRasterizer.raster(frame, model: model)
        return ScrollView([.horizontal, .vertical]) {
            MatrixDotsView(raster: raster, appearance: model.appearance)
                .frame(width: Double(raster.width) * 2, height: Double(raster.height) * 2)
        }
        .padding(8)
        .background(Color(rgb: model.appearance.bezel), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(height: min(320, Double(raster.height) * 2 + 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoardSpeech.spoken(frame, model: model))
    }

    private var flapViewport: some View {
        GeometryReader { proxy in
            let geometry = BoardViewportGeometry(rows: model.rows, cols: model.cols,
                viewportWidth: proxy.size.width - 16, tileHeight: tileHeight, notes: model.seams != nil)
            VStack(spacing: 8) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(0..<geometry.noteCount, id: \.self) { index in
                            let cells = pageCells(index, geometry: geometry)
                            let bounds = geometry.bounds(page: index)
                            BoardCanvas(layout: BoardLayout.make(rows: bounds.rows.count,
                                cols: bounds.cols.count, cells: cells, tileHeight: geometry.tileHeight),
                                palette: model.flapPalette, animated: false, code62: model.code62)
                                .frame(minWidth: geometry.viewportWidth, alignment: .center)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $page, anchor: .leading)
                .onChange(of: geometry.noteCount) { _, count in page = min(count - 1, max(0, page ?? 0)) }
                .padding(8)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .trailing) {
                    if geometry.scrolls {
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 12).padding(.vertical, 8).allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BoardSpeech.spoken(frame, model: model))
                .accessibilityValue(geometry.notes ? geometry.label(page: page ?? 0) : "Board")
                .accessibilityAction(named: "Next note") { move(to: geometry.next(after: page ?? 0)) }
                .accessibilityAction(named: "Previous note") { move(to: geometry.previous(before: page ?? 0)) }
                if geometry.notes { Text(geometry.label(page: page ?? 0)).font(.caption).accessibilityHidden(true) }
            }
        }
        .frame(height: BoardLayout.size(rows: model.seams == nil ? model.rows : min(3, model.rows), cols: 1,
            tileHeight: tileHeight.isFinite ? min(200, max(13, tileHeight)) : 13).height + (model.seams == nil ? 16 : 40))
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page = value }
    }

    private func pageCells(_ index: Int, geometry: BoardViewportGeometry) -> [[BoardCell]] {
        let all = frame.boardCells(model: model)
        let bounds = geometry.bounds(page: index)
        return bounds.rows.map { y in
            bounds.cols.map { x in
                y < all.count && x < all[y].count ? all[y][x] : .blank
            }
        }
    }
}
