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

/// Hints describe offscreen content, including fractional offsets and bounce.
public struct BoardViewportEdges: Equatable, Sendable {
    public let leading: Bool
    public let trailing: Bool
    public init(leading: Bool = false, trailing: Bool = false) {
        self.leading = leading; self.trailing = trailing
    }
    public init(offset: Double, contentWidth: Double, viewportWidth: Double) {
        let end = max(0, contentWidth - viewportWidth)
        let position = min(end, max(0, offset))
        leading = position > 1
        trailing = position < end - 1
    }
    public var accessibilityValue: String {
        if leading && trailing { return "More columns on both sides" }
        if leading { return "End of board" }
        if trailing { return "Start of board" }
        return "Entire board visible"
    }
}

/// The opt-in LED viewport enlarges uniformly within the available bezel and
/// height budget. A raster that cannot fit at two points per pixel scrolls.
struct MatrixViewportSizing: Equatable, Sendable {
    let pitch: Double
    let contentWidth: Double
    let contentHeight: Double
    let viewportWidth: Double
    let viewportHeight: Double
    var horizontalOverflow: Bool { contentWidth > max(0, viewportWidth - 16) + 0.000001 }
    var verticalOverflow: Bool { contentHeight > max(0, viewportHeight - 16) + 0.000001 }

    init(pixelWidth: Int, pixelHeight: Int, availableWidth: Double?, maximumHeight: Double = 320) {
        let pixelsWide = Double(max(1, min(2048, pixelWidth)))
        let pixelsHigh = Double(max(1, min(2048, pixelHeight)))
        let cap = maximumHeight.isFinite ? min(320, max(0, maximumHeight)) : 320
        let offeredWidth = availableWidth.flatMap { $0.isFinite ? max(0, $0) : nil }
        viewportWidth = offeredWidth ?? pixelsWide * 2 + 16
        pitch = max(2, min(max(0, viewportWidth - 16) / pixelsWide,
                           max(0, cap - 16) / pixelsHigh))
        contentWidth = pixelsWide * pitch
        contentHeight = pixelsHigh * pitch
        viewportHeight = min(cap, contentHeight + 16)
    }
}

/// Gives the reader its final finite viewport in the same layout pass. There
/// is no measured-width State and no initial frame drawn with an old width.
private struct MatrixViewportFitLayout: Layout {
    let pixelWidth: Int
    let pixelHeight: Int
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizing = MatrixViewportSizing(pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            availableWidth: proposal.width.map(Double.init), maximumHeight: Double(proposal.height ?? 320))
        return CGSize(width: sizing.viewportWidth, height: sizing.viewportHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// A fixed hardware surround containing readable, horizontally scrolling content.
/// A Note array pages by complete Notes, in row-major order. Thumbnails keep
/// using `BoardThumbnail`; the owner's thumbnail exemption does not apply here.
public struct BoardViewport: View {
    private let frame: BoardFrame
    private let model: DisplayModel
    private let tileHeight: Double
    private let fitLEDWidth: Bool
    @State private var page: Int? = 0
    @State private var edges = BoardViewportEdges()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(frame: BoardFrame, model: DisplayModel, tileHeight: Double = 13, fitLEDWidth: Bool = false) {
        self.frame = frame
        self.model = model
        self.tileHeight = tileHeight
        self.fitLEDWidth = fitLEDWidth
    }

    public var body: some View {
        if model.technology == .ledMatrix {
            if fitLEDWidth { fittedMatrixViewport } else { matrixViewport }
        } else {
            flapViewport
        }
    }

    private var fittedMatrixViewport: some View {
        let raster = LedRasterizer.raster(frame, model: model)
        return MatrixViewportFitLayout(pixelWidth: raster.width, pixelHeight: raster.height) {
            GeometryReader { proxy in
                let sizing = MatrixViewportSizing(pixelWidth: raster.width, pixelHeight: raster.height,
                    availableWidth: Double(proxy.size.width), maximumHeight: Double(proxy.size.height))
                ScrollView([.horizontal, .vertical]) {
                    MatrixDotsView(raster: raster, appearance: model.appearance)
                        .frame(width: sizing.contentWidth, height: sizing.contentHeight)
                }
                .padding(8)
                .background(Color(rgb: model.appearance.bezel), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BoardSpeech.spoken(frame, model: model))
            }
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
                Group {
                    if geometry.notes {
                        ScrollView(.horizontal) {
                            pages(geometry).scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                        .scrollPosition(id: $page, anchor: .leading)
                    } else {
                        // A wide merged board is freely pannable; only Notes snap.
                        ScrollView(.horizontal) { pages(geometry) }
                    }
                }
                .onScrollGeometryChange(for: BoardViewportEdges.self) { scroll in
                    BoardViewportEdges(offset: scroll.contentOffset.x + scroll.contentInsets.leading,
                        contentWidth: scroll.contentSize.width + scroll.contentInsets.leading + scroll.contentInsets.trailing,
                        viewportWidth: scroll.containerSize.width)
                } action: { _, value in edges = value }
                .scrollIndicators(.hidden)
                .onChange(of: geometry.noteCount) { _, count in page = min(count - 1, max(0, page ?? 0)) }
                .padding(8)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .leading) { fade(visible: edges.leading, leading: true) }
                .overlay(alignment: .trailing) { fade(visible: edges.trailing, leading: false) }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("board-viewport")
                .accessibilityLabel(BoardSpeech.spoken(frame, model: model))
                .accessibilityValue(geometry.notes ? geometry.label(page: page ?? 0) : edges.accessibilityValue)
                .accessibilityActions {
                    if geometry.notes {
                        Button("Next note") { move(to: geometry.next(after: page ?? 0)) }
                        Button("Previous note") { move(to: geometry.previous(before: page ?? 0)) }
                    }
                }
                if geometry.notes { Text(geometry.label(page: page ?? 0)).font(.caption).accessibilityHidden(true) }
            }
        }
        .frame(height: BoardLayout.size(rows: model.seams == nil ? model.rows : min(3, model.rows), cols: 1,
            tileHeight: tileHeight.isFinite ? min(200, max(13, tileHeight)) : 13).height + (model.seams == nil ? 16 : 40))
    }

    private func pages(_ geometry: BoardViewportGeometry) -> some View {
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
    }

    @ViewBuilder private func fade(visible: Bool, leading: Bool) -> some View {
        if visible {
            LinearGradient(colors: leading ? [.black.opacity(0.8), .clear] : [.clear, .black.opacity(0.8)],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: 12).padding(.vertical, 8).allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
