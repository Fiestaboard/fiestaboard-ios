import SwiftUI
import FiestaBoardKit
import FiestaBoardEditorState
import FiestaBoardRender
import FiestaBoardDocuments

/// The pinned live board above the document (PLAN §3.3 "Stage", B19/B20). Header: size readout,
/// display picker, fit note, updating/retry. Body: the board, never a text dump.
struct PreviewStage: View {
    /// Markup lines to draw (server render, or the local projection).
    var lines: [String]
    var rows: Int
    var cols: Int
    var isPanel: Bool
    /// Physical pixel surface from the server, drawn instead of cells when present.
    var physical: PhysicalPreviewFrame?
    var state: PreviewPipeline.State
    var boards: [EditorBoardChoice]
    var selectedBoardID: String?
    var fitNote: String?
    var footnote: String?
    var disabled: Bool
    var onChooseBoard: (String?) -> Void
    var onRetry: () -> Void
    var onRefresh: () -> Void
    /// The page's board shape and its change (PLAN B20); nil hides the size section.
    var geometry: PageGeometry? = nil
    var onChooseGeometry: ((PageGeometry) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            board
                .frame(maxWidth: .infinity)
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(EditorStrings.sizeReadout(rows: rows, cols: cols))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .accessibilityLabel("Board size \(rows) by \(cols)")
                .accessibilityIdentifier("boardSizeReadout")
            picker
            if let fitNote {
                Text(fitNote).font(.caption).foregroundStyle(.orange).lineLimit(1)
                    .accessibilityIdentifier("boardFitNote")
            }
            Spacer(minLength: 4)
            if state.isUpdating {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(EditorStrings.updating).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("previewUpdating")
            } else if state.failure != nil {
                Button { onRetry() } label: {
                    Label("\(EditorStrings.previewUnavailable) · \(EditorStrings.retry)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
                .buttonStyle(.borderless).tint(.orange)
                .accessibilityIdentifier("previewRetry")
            }
            Button(EditorStrings.previewNow, systemImage: "arrow.clockwise") { onRefresh() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).font(.caption)
                .disabled(disabled || selectedBoardID == nil)
                .accessibilityIdentifier("previewPage")
        }
    }

    private var picker: some View {
        HStack(spacing: 0) { menu }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("boardDisplayPicker")
    }

    private var menu: some View {
        Menu {
            Section(EditorStrings.yourDisplays) {
                ForEach(boards) { board in
                    Button { onChooseBoard(board.id) } label: {
                        let title = EditorStrings.displayChoice(board.name, rows: board.rows, cols: board.cols, fits: board.fits(rows: rows, cols: cols))
                        if board.id == selectedBoardID { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            }
            Button(EditorStrings.noDisplay) { onChooseBoard(nil) }
            if let geometry, let onChooseGeometry {
                Section(EditorStrings.boardSize) {
                    ForEach(Self.shapes(current: geometry), id: \.self) { shape in
                        Button { onChooseGeometry(shape) } label: {
                            let title = EditorStrings.shapeName(shape)
                            if shape == geometry { Label(title, systemImage: "checkmark") } else { Text(title) }
                        }
                        .accessibilityIdentifier("boardShape_\(shape.deviceType)_\(shape.rows)x\(shape.columns)")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(boards.first(where: { $0.id == selectedBoardID })?.name ?? EditorStrings.displayPickerLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.subheadline)
        }
        .disabled(disabled)
        .accessibilityLabel(EditorStrings.displayPickerLabel)
        .accessibilityValue(boards.first(where: { $0.id == selectedBoardID })?.name ?? "None")
        .accessibilityIdentifier("evaluationBoardPicker")
    }

    /// Flagship / Note / Note array presets, plus the page's own shape when it is another one.
    static func shapes(current: PageGeometry) -> [PageGeometry] {
        var shapes: [PageGeometry] = [.flagship, .note, .noteArray(wide: 2, tall: 1), .noteArray(wide: 2, tall: 2), .noteArray(wide: 3, tall: 2)]
        if !shapes.contains(current) { shapes.append(current) }
        return shapes
    }

    @ViewBuilder private var board: some View {
        if let physical {
            VStack(spacing: 4) {
                PhysicalFrameView(frame: physical)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("boardStage")
            .accessibilityValue(lines.joined(separator: "\n"))
        } else {
            StageBoard(lines: lines, rows: rows, cols: cols, isPanel: isPanel, loading: state.adoptedRenders == 0 && state.isUpdating)
                .accessibilityIdentifier("boardStage")
        }
    }
}

/// Board drawing for the stage: the shared renderer (`FiestaBoardRender`, iOS-R1), animated so
/// tiles flip through the drum as the frame changes (B19). The stage's model is the page's
/// geometry; the chosen display only sets the render's `board_id` in D1.
struct StageBoard: View {
    var lines: [String]
    var rows: Int
    var cols: Int
    var isPanel: Bool
    var loading: Bool

    private var deviceType: String {
        if isPanel { return "panel" }
        switch (rows, cols) {
        case (6, 22): return "flagship"
        case (3, 15): return "note"
        default: return "note_array"
        }
    }

    /// How much taller than its width-derived height the board may grow into free space (P1).
    static let maxStretch: CGFloat = 1.3

    var body: some View {
        let model = DisplayModel.flap(rows: rows, cols: cols, deviceType: deviceType)
        let aspect = CGFloat(BoardFrameView.flapAspect(model))
        StretchBoardLayout(aspect: aspect, maxStretch: Self.maxStretch) {
            GeometryReader { proxy in
                // Width-bound board, drawn at its natural aspect, then made taller (tiles and
                // letters) to fill the height the stage was given; never wider than the room.
                let natural = proxy.size.width / aspect
                let stretch = min(Self.maxStretch, max(1, proxy.size.height / max(natural, 1)))
                BoardFrameView(frame: BoardFrame.fromLines(lines, rows: rows, cols: cols), model: model,
                               size: .fit, animated: true, loading: loading)
                    .frame(width: proxy.size.width, height: natural)
                    .scaleEffect(x: 1, y: stretch, anchor: .top)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
    }
}

/// Sizes the stage's board (P1, free space): with no height offered it is width-bound at the
/// board's aspect (as before); offered more height it grows up to `maxStretch` × that; offered
/// less it shrinks to fit (keeping its aspect), so it is never covered.
struct StretchBoardLayout: Layout {
    var aspect: CGFloat
    var maxStretch: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        let natural = width / max(aspect, 0.01)
        guard let height = proposal.height, height.isFinite else { return CGSize(width: width, height: natural) }
        if height >= natural { return CGSize(width: width, height: min(height, natural * maxStretch)) }
        return CGSize(width: height * aspect, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// The backend supplies a complete opaque RGBA surface. Display its exact aspect
/// ratio with nearest-neighbor sampling; no character-grid geometry participates.
struct PhysicalFrameView: View {
    let frame: PhysicalPreviewFrame
    private var image: CGImage? {
        guard let provider = CGDataProvider(data: frame.rgba as CFData) else { return nil }
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable().interpolation(.none)
                .aspectRatio(CGFloat(frame.width) / CGFloat(frame.height), contentMode: .fit)
                .accessibilityHidden(false)
                .accessibilityLabel("Server preview, \(frame.width) by \(frame.height) pixels")
                .accessibilityIdentifier("physicalPreview")
            Text("\(frame.width) × \(frame.height) pixels").font(.caption)
        } else {
            Text("The visual preview could not be displayed.")
        }
    }
}
