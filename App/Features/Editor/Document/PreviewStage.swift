import SwiftUI
import FiestaBoardKit
import FiestaBoardEditorState
import FiestaBoardRender

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
                Text(fitNote).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                        if board.id == selectedBoardID { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                    }
                }
            }
            Button(EditorStrings.noDisplay) { onChooseBoard(nil) }
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

    var body: some View {
        BoardFrameView(frame: BoardFrame.fromLines(lines, rows: rows, cols: cols),
                       model: DisplayModel.flap(rows: rows, cols: cols, deviceType: deviceType),
                       size: .fit, animated: true, loading: loading)
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
