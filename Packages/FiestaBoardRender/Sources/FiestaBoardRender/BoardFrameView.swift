import SwiftUI

/// Preview sizes (FiestaUI `board-metrics.js`): `sm` 18 px tiles for
/// thumbnails, `md` 34 px for stages, `fit` measures the container like
/// `ScaledBoardDisplay`.
public enum BoardSize: Sendable, Equatable {
    case sm, md, fit
    public var tileHeight: Double? {
        switch self { case .sm: 18; case .md: 34; case .fit: nil }
    }
}

/// The board, drawn as its hardware: dispatches split-flap / LED by
/// `model.technology`, wraps it in the bezel, flips on change.
public struct BoardFrameView: View {
    let frame: BoardFrame
    let model: DisplayModel
    let size: BoardSize
    let animated: Bool
    let loading: Bool
    let bezel: Bool
    let flapStepMs: Int
    let stretch: Double

    /// `stretch` (split-flap only, W4): the board is that much taller than its hardware aspect —
    /// tiles, gutters and the bezel's vertical padding grow; widths and letter shapes don't.
    public init(frame: BoardFrame, model: DisplayModel, size: BoardSize = .fit,
                animated: Bool, loading: Bool = false, bezel: Bool = true, flapStepMs: Int = 80, stretch: Double = 1) {
        self.frame = frame; self.model = model; self.size = size
        self.animated = animated; self.loading = loading; self.bezel = bezel; self.flapStepMs = flapStepMs
        self.stretch = stretch.isFinite ? max(1, stretch) : 1
    }

    /// Bezel padding and border as fractions of tile height, so the aspect of
    /// the whole board is size-independent.
    public static let bezelPadX = 0.40, bezelPadY = 0.55, bezelBorder = 0.10, bezelRadius = 0.40

    /// Width / height of a split-flap board with its bezel (size-independent), for hosts that lay
    /// the board out themselves (the editor's stage, P1).
    public static func flapAspect(_ model: DisplayModel, bezel: Bool = true, stretch: Double = 1) -> Double {
        let h = 100.0
        let grid = BoardLayout.size(rows: model.rows, cols: model.cols, tileHeight: h, seams: model.seams, stretch: stretch)
        guard bezel else { return grid.width / max(grid.height, 1) }
        return (grid.width + 2 * h * (bezelPadX + bezelBorder)) / max(grid.height + 2 * h * (bezelPadY * stretch + bezelBorder), 1)
    }

    /// The `stretch` at which a split-flap board `width` wide is `height` tall (bezel included;
    /// its border doesn't stretch). Unclamped: below 1 the board is width-bound and shorter.
    public static func flapStretch(_ model: DisplayModel, width: Double, height: Double, bezel: Bool = true) -> Double {
        let h = 100.0
        let grid = BoardLayout.size(rows: model.rows, cols: model.cols, tileHeight: h, seams: model.seams)
        let outerWidth = grid.width + (bezel ? 2 * h * (bezelPadX + bezelBorder) : 0)
        guard width > 0, height > 0, outerWidth > 0 else { return 1 }
        let scale = width / outerWidth
        let fixed = bezel ? 2 * h * bezelBorder : 0
        let stretchable = grid.height + (bezel ? 2 * h * bezelPadY : 0)
        return (height / scale - fixed) / max(stretchable, 1)
    }

    private var cells: [[BoardCell]] { frame.boardCells(model: model) }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(loading ? "Loading board" : BoardSpeech.spoken(frame, model: model))
            .accessibilityValue(frame.lines(model: model).joined(separator: "\n"))
    }

    @ViewBuilder private var content: some View {
        switch model.technology {
        case .splitFlap: flap
        case .ledMatrix: led
        }
    }

    // MARK: split-flap

    private func outer(tileHeight h: Double) -> (width: Double, height: Double) {
        let grid = BoardLayout.size(rows: model.rows, cols: model.cols, tileHeight: h, seams: model.seams, stretch: stretch)
        guard bezel else { return grid }
        return (grid.width + 2 * h * (Self.bezelPadX + Self.bezelBorder),
                grid.height + 2 * h * (Self.bezelPadY * stretch + Self.bezelBorder))
    }

    @ViewBuilder private var flap: some View {
        if let h = size.tileHeight {
            flapBoard(tileHeight: h)
        } else {
            let reference = outer(tileHeight: 100)
            GeometryReader { proxy in
                let scale = min(proxy.size.width / max(reference.width, 1), proxy.size.height / max(reference.height, 1))
                flapBoard(tileHeight: max(1, 100 * scale))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(reference.width / max(reference.height, 1), contentMode: .fit)
        }
    }

    private func flapBoard(tileHeight h: Double) -> some View {
        let layout = BoardLayout.make(rows: model.rows, cols: model.cols, cells: cells, tileHeight: h, seams: model.seams, stretch: stretch)
        let palette = model.flapPalette
        let canvas = BoardCanvas(layout: layout, palette: palette, animated: animated, loading: loading,
                                 code62: model.code62, step: Double(flapStepMs) / 1000)
            .background(Color(rgb: palette.backing))
        return Group {
            if bezel && model.seams == nil {
                canvas
                    .padding(.horizontal, h * Self.bezelPadX)
                    .padding(.vertical, h * Self.bezelPadY * stretch)
                    .background(
                        RoundedRectangle(cornerRadius: h * Self.bezelRadius, style: .continuous)
                            .fill(LinearGradient(colors: [Color(rgb: palette.bezel), Color(rgb: palette.backing)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(
                        RoundedRectangle(cornerRadius: h * Self.bezelRadius, style: .continuous)
                            .strokeBorder(Color(rgb: palette.bezelBorder), lineWidth: max(2, h * Self.bezelBorder)))
                    .clipShape(RoundedRectangle(cornerRadius: h * Self.bezelRadius, style: .continuous))
                    .shadow(color: .black.opacity(palette.whiteHardware ? 0.18 : 0.45), radius: h * 0.4, y: h * 0.12)
            } else {
                canvas
            }
        }
    }

    // MARK: LED (D1 static stub, see LedRasterizer)

    private var led: some View {
        let raster = LedRasterizer.raster(frame, model: model)
        let dots = MatrixDotsView(raster: raster, appearance: model.appearance)
        return Group {
            if bezel {
                dots.padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(rgb: model.appearance.bezel)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(rgb: 0x1a1a1a), lineWidth: 3))
            } else { dots }
        }
        .frame(maxWidth: size == .sm ? 160 : (size == .md ? 320 : .infinity))
    }
}

/// A static board picture: `sm`, no clock, no loading drum (thumbnails are
/// never animated — FiestaUI found animating them was two-thirds of the
/// Displays page's main-thread cost). tvOS `PanelPreviewBoard` lineage.
public struct BoardThumbnail: View {
    let frame: BoardFrame
    let model: DisplayModel
    public init(frame: BoardFrame, model: DisplayModel) { self.frame = frame; self.model = model }
    public var body: some View {
        BoardFrameView(frame: frame, model: model, size: .fit, animated: false, loading: false, bezel: true)
    }
}
