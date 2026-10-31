import SwiftUI
import FiestaBoardKit
import FiestaBoardEditorState

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
            StageBoard(lines: lines, rows: rows, cols: cols, isPanel: isPanel, loading: false)
                .accessibilityIdentifier("boardStage")
        }
    }
}

/// Board drawing for the stage. Interim (pre-`d1-hooks-ios`): a static tile grid drawn from the
/// markup lines. After the render module merges this becomes `BoardFrameView(animated: true)`.
struct StageBoard: View {
    var lines: [String]
    var rows: Int
    var cols: Int
    var isPanel: Bool
    var loading: Bool

    private struct Cell { var text: String; var color: Color? }
    private static let colors: [String: Color] = [
        "red": Color(red: 0xeb / 255, green: 0x40 / 255, blue: 0x34 / 255),
        "orange": Color(red: 0xf5 / 255, green: 0xa6 / 255, blue: 0x23 / 255),
        "yellow": Color(red: 0xf8 / 255, green: 0xe7 / 255, blue: 0x1c / 255),
        "green": Color(red: 0x7e / 255, green: 0xd3 / 255, blue: 0x21 / 255),
        "blue": Color(red: 0x4a / 255, green: 0x90 / 255, blue: 0xe2 / 255),
        "violet": Color(red: 0x90 / 255, green: 0x13 / 255, blue: 0xfe / 255),
        "purple": Color(red: 0x90 / 255, green: 0x13 / 255, blue: 0xfe / 255),
        "white": .white, "black": .black, "filled": .white
    ]
    private func cells(_ line: String) -> [Cell] {
        var result: [Cell] = []
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "{", let close = line[index...].firstIndex(of: "}"),
               let color = Self.colors[String(line[line.index(after: index)..<close]).lowercased()] {
                result.append(Cell(text: "", color: color)); index = line.index(after: close); continue
            }
            result.append(Cell(text: String(line[index]), color: nil)); index = line.index(after: index)
        }
        return result
    }

    var body: some View {
        let grid = (0..<rows).map { row in row < lines.count ? cells(lines[row]) : [] }
        Canvas { context, size in
            let pad = size.width * 0.02
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: pad), with: .color(Color(white: 0.02)))
            let inner = CGRect(x: pad, y: pad, width: size.width - 2 * pad, height: size.height - 2 * pad)
            let pitchX = inner.width / CGFloat(max(1, cols))
            let pitchY = inner.height / CGFloat(max(1, rows))
            for row in 0..<rows {
                for col in 0..<cols {
                    let cell = col < grid[row].count ? grid[row][col] : Cell(text: "", color: nil)
                    let rect = CGRect(x: inner.minX + CGFloat(col) * pitchX + pitchX * 0.07, y: inner.minY + CGFloat(row) * pitchY + pitchY * 0.06,
                                      width: pitchX * 0.86, height: pitchY * 0.88)
                    context.fill(Path(roundedRect: rect, cornerRadius: isPanel ? 1 : rect.width * 0.12), with: .color(cell.color ?? Color(white: 0.05)))
                    if !isPanel {
                        context.fill(Path(CGRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1)), with: .color(.black.opacity(0.7)))
                    }
                    if !cell.text.isEmpty, cell.text != " " {
                        context.draw(Text(cell.text).font(.system(size: rect.height * 0.62, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0xf0 / 255, green: 0xf0 / 255, blue: 0xe8 / 255)), at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
            }
        }
        .aspectRatio(CGFloat(cols) * 0.70 / CGFloat(max(1, rows)) * 1.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(loading ? "Loading board" : "Board preview")
        .accessibilityValue(lines.prefix(rows).joined(separator: "\n"))
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
