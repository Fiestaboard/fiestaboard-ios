import SwiftUI
import FiestaBoardDocuments

/// The Draw tab (web `CanvasDrawTab`, PLAN B24): brush and eraser, the board palette plus any hex
/// colour, zoom 2–16, Clear. Painting writes palette-encoded `pixels` (≤ 62 colours, `.`
/// transparent) and pins `size` to the pad. A stroke is one undo step; the stage follows it live.
struct CanvasDrawTab: View {
    var canvas: LegacyCanvas
    /// The pad's pixel size: the content's own `size`, else the canvas's size on the board.
    var width: Int
    var height: Int
    @ObservedObject var state: CanvasEditorState
    var onLive: (LegacyCanvas) -> Void
    var onCommit: (LegacyCanvas, String) -> Void

    @State private var hexDraft = "#eb4034"
    @State private var stroke: CanvasPixels.Grid?
    @State private var last: (x: Int, y: Int)?

    private var zoom: Int { CanvasEditorState.zooms[state.zoomIndex] }
    private var grid: CanvasPixels.Grid { stroke ?? CanvasPixels.decode(canvas, width: width, height: height) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = canvas.source, !source.isEmpty {
                Text(CanvasStrings.drawSourceHint).font(.caption).foregroundStyle(.secondary)
            } else if canvas.content?["background"].map({ $0 != .null }) == true || !canvas.shapes.isEmpty {
                Text(CanvasStrings.drawLayerHint).font(.caption).foregroundStyle(.secondary)
            }
            tools
            palette
            HStack {
                Text(CanvasStrings.padSize(width, height)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("canvasPadSize")
                Spacer()
                Text(CanvasStrings.padHint).font(.caption2).foregroundStyle(.secondary)
            }
            pad
            if let error = state.drawError {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("canvasDrawError")
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            Picker("Drawing tool", selection: $state.tool) {
                Image(systemName: "paintbrush.pointed").accessibilityLabel(CanvasStrings.brush).tag(CanvasEditorState.Tool.brush)
                Image(systemName: "eraser").accessibilityLabel(CanvasStrings.eraser).tag(CanvasEditorState.Tool.eraser)
            }
            .pickerStyle(.segmented).frame(width: 110)
            .accessibilityIdentifier("canvasDrawTool")
            Spacer(minLength: 4)
            Button { state.zoomIndex = max(0, state.zoomIndex - 1) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(state.zoomIndex == 0).accessibilityLabel(CanvasStrings.zoomOut).accessibilityIdentifier("canvasZoomOut")
            Text("\(zoom)×").font(.caption.monospacedDigit()).frame(minWidth: 28).accessibilityIdentifier("canvasZoom")
            Button { state.zoomIndex = min(CanvasEditorState.zooms.count - 1, state.zoomIndex + 1) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(state.zoomIndex == CanvasEditorState.zooms.count - 1).accessibilityLabel(CanvasStrings.zoomIn).accessibilityIdentifier("canvasZoomIn")
            Button(role: .destructive) { commit(grid.map { $0.map { _ in nil } }, action: "Clear canvas") } label: {
                Label(CanvasStrings.clear, systemImage: "trash")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityIdentifier("canvasClear")
        }
        .buttonStyle(.borderless)
    }

    private var palette: some View {
        HStack(spacing: 6) {
            ForEach(CanvasLimits.boardColors, id: \.name) { entry in
                let c = CanvasRGBA.parse(entry.hex)!
                Button { state.color = c; hexDraft = entry.hex; state.tool = .brush } label: {
                    RoundedRectangle(cornerRadius: 4).fill(c.color).frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.color == c ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: state.color == c ? 3 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.name.capitalized)
                .accessibilityAddTraits(state.color == c ? .isSelected : [])
                .accessibilityIdentifier("canvasColor_\(entry.name)")
            }
            TextField(CanvasStrings.hexLabel, text: $hexDraft)
                .font(.caption.monospaced()).textFieldStyle(.roundedBorder).frame(width: 84)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onChange(of: hexDraft) { _, value in
                    if value.hasPrefix("#"), let c = CanvasRGBA.parse(value) { state.color = c; state.tool = .brush }
                }
                .accessibilityIdentifier("canvasHex")
        }
    }

    private var pad: some View {
        let z = CGFloat(zoom)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for row in grid { for c in row { if let c { bytes += [c.r, c.g, c.b, 255] } else { bytes += [0, 0, 0, 0] } } }
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                if let image = PixelImage.make(bytes, width: width, height: height, checker: true) {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(width) * z, height: CGFloat(height) * z)
                }
                if zoom >= 4 {
                    Canvas { context, size in
                        var lines = Path()
                        for x in 0...width { lines.move(to: CGPoint(x: CGFloat(x) * z, y: 0)); lines.addLine(to: CGPoint(x: CGFloat(x) * z, y: size.height)) }
                        for y in 0...height { lines.move(to: CGPoint(x: 0, y: CGFloat(y) * z)); lines.addLine(to: CGPoint(x: size.width, y: CGFloat(y) * z)) }
                        context.stroke(lines, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: CGFloat(width) * z, height: CGFloat(height) * z)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let size = CGSize(width: CGFloat(width) * z, height: CGFloat(height) * z)
                    guard value.startLocation.x >= 0, value.startLocation.y >= 0, value.startLocation.x <= size.width, value.startLocation.y <= size.height else { return }
                    paint(at: value.location, z)
                }
                .onEnded { _ in endStroke() })
        }
        .frame(maxHeight: 360)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel("Pixel pad, \(width) by \(height) pixels")
        .accessibilityValue("\(grid.reduce(0) { $0 + $1.filter { $0 != nil }.count }) pixels painted")
        .accessibilityIdentifier("canvasPixelPad")
    }

    private func paint(at point: CGPoint, _ z: CGFloat) {
        let x = Int(point.x / z), y = Int(point.y / z)
        guard x >= 0, y >= 0, x < width, y < height else { last = nil; return }
        var next = grid
        let paint: CanvasRGBA? = state.tool == .eraser ? nil : state.color
        let from = last ?? (x, y)
        last = (x, y)
        // Bresenham visits each pixel between sparse touch samples.
        var cx = from.x, cy = from.y
        let dx = abs(x - cx), dy = -abs(y - cy), sx = cx < x ? 1 : -1, sy = cy < y ? 1 : -1
        var err = dx + dy
        while true {
            next[cy][cx] = paint
            if cx == x && cy == y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; cx += sx }
            if e2 <= dx { err += dx; cy += sy }
        }
        stroke = next
        var updated = canvas
        if (try? CanvasPixels.encode(next, into: &updated)) != nil { onLive(updated) }
    }

    private func endStroke() {
        last = nil
        guard let finished = stroke else { return }
        stroke = nil
        commit(finished, action: "Paint")
    }

    private func commit(_ grid: CanvasPixels.Grid, action: String) {
        var updated = canvas
        do {
            try CanvasPixels.encode(grid, into: &updated)
            state.drawError = nil
            onCommit(updated, action)
        } catch {
            state.drawError = CanvasStrings.tooManyColors(CanvasLimits.maxPaletteKeys)
        }
    }
}
