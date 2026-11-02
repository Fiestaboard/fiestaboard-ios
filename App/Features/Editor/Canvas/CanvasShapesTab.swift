import SwiftUI
import FiestaBoardDocuments

/// The Shapes tab (PLAN B24): the canvas drawn on its `content.size` pixel grid with every shape as a
/// touch target. Tap selects, drag moves, handles resize; every value snaps to an integer lexeme.
/// A field holding `{{…}}` locks its axis and shows an "expression" badge. Gradients, polygons and
/// unknown types are hatched "preserved" overlays whose only editor is the numeric inspector, which
/// stays below for every shape.
struct CanvasShapesTab: View {
    var canvas: LegacyCanvas
    /// The content's coordinate space (its `size`, else the canvas's size on the board).
    var width: Int
    var height: Int
    @ObservedObject var state: CanvasEditorState
    var onLive: (LegacyCanvas) -> Void
    var onCommit: (LegacyCanvas, String) -> Void

    private enum Grab { case move(Int, CanvasShape), resize(Int, CanvasShape, CanvasShape.Handle), none }
    @State private var grab: Grab?
    @State private var moved = false

    private var shapes: [CanvasShape] { canvas.shapes.map { CanvasShape($0) ?? CanvasShape([:]) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CanvasStrings.shapesHint).font(.caption).foregroundStyle(.secondary)
            surface
            HStack {
                Menu {
                    ForEach(CanvasShape.addableTypes, id: \.self) { type in
                        Button(CanvasStrings.typeName(type)) { add(type) }.accessibilityIdentifier("canvasAddShape_\(type)")
                    }
                } label: { Label(CanvasStrings.addShape, systemImage: "plus") }
                .accessibilityIdentifier("canvasAddShape")
                .disabled(shapes.count >= 256)
                Spacer()
                Text(CanvasStrings.padSize(width, height)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if shapes.isEmpty {
                Text(CanvasStrings.shapesEmpty).font(.subheadline).foregroundStyle(.secondary)
            } else {
                list
            }
            if let index = state.selectedShape, shapes.indices.contains(index) {
                CanvasShapeInspector(shape: shapes[index], index: index) { updated in
                    var next = canvas; next.shapes[index] = updated.json
                    onCommit(next, "Edit \(CanvasStrings.typeName(updated.type).lowercased())")
                }
                .id("\(canvas.id)-\(index)")
            }
        }
    }

    // MARK: Surface

    private var surface: some View {
        GeometryReader { proxy in
            let z = max(1, min(proxy.size.width / CGFloat(max(width, 1)), 12))
            let image = PixelImage.make(CanvasRaster.rasterize(canvas, width: width, height: height, glyphs: PixelDisplay.glyphs),
                                        width: width, height: height, checker: true)
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(width) * z, height: CGFloat(height) * z)
                }
                ForEach(Array(shapes.enumerated()), id: \.offset) { index, shape in
                    overlay(shape, index: index, z: z)
                }
            }
            .frame(width: CGFloat(width) * z, height: CGFloat(height) * z, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in drag(value, z) }
                .onEnded { value in end(value, z) })
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit)
        .frame(maxHeight: 340)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas shapes, \(width) by \(height) pixels")
        .accessibilityIdentifier("canvasShapesSurface")
    }

    private func box(_ shape: CanvasShape) -> CanvasShape.Box? {
        if let b = shape.bounds() { return b }
        // A gradient without a rect covers the whole content.
        if shape.type == "gradient" { return CanvasShape.Box(x: 0, y: 0, w: Double(width), h: Double(height)) }
        return nil
    }

    @ViewBuilder private func overlay(_ shape: CanvasShape, index: Int, z: CGFloat) -> some View {
        if let b = box(shape) {
            let rect = CGRect(x: b.x * z, y: b.y * z, width: max(b.w * z, 4), height: max(b.h * z, 4))
            let selected = state.selectedShape == index
            ZStack(alignment: .topLeading) {
                if shape.isPreserved {
                    Hatch().stroke(Color.white.opacity(0.55), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height).clipped()
                        .overlay(Rectangle().stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .overlay(alignment: .bottomLeading) { badge(CanvasStrings.preserved, .gray) }
                }
                Rectangle()
                    .stroke(selected ? Color.accentColor : Color.white.opacity(shape.isPreserved ? 0 : 0.6),
                            style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [3, 2]))
                    .frame(width: rect.width, height: rect.height)
                if shape.lockedX || shape.lockedY, !shape.isPreserved {
                    badge(CanvasStrings.expression, .purple).offset(y: -16)
                        .accessibilityIdentifier("canvasExpressionBadge_\(index)")
                }
                if selected {
                    ForEach(shape.handles, id: \.self) { handle in
                        if let p = handlePoint(shape, handle, z) {
                            Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                                .frame(width: 14, height: 14)
                                .position(x: p.x - rect.minX, y: p.y - rect.minY)
                                .accessibilityIdentifier("canvasHandle_\(handle.rawValue)")
                        }
                    }
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(CanvasStrings.shapeTitle(index, shape.type) + (shape.isPreserved ? ", \(CanvasStrings.preserved)" : ""))
            .accessibilityValue(accessibilityValue(shape))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("canvasShapeOverlay_\(index)")
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color, in: Capsule())
    }

    private func accessibilityValue(_ shape: CanvasShape) -> String {
        CanvasShape.fields(shape.type).filter { $0.kind == .number }.map { "\($0.name) \(shape.text($0.name))" }.joined(separator: ", ")
    }

    private func handlePoint(_ shape: CanvasShape, _ handle: CanvasShape.Handle, _ z: CGFloat) -> CGPoint? {
        guard let b = shape.bounds() else { return nil }
        switch handle {
        case .topLeft: return CGPoint(x: b.x * z, y: b.y * z)
        case .topRight: return CGPoint(x: (b.x + b.w) * z, y: b.y * z)
        case .bottomLeft: return CGPoint(x: b.x * z, y: (b.y + b.h) * z)
        case .bottomRight: return CGPoint(x: (b.x + b.w) * z, y: (b.y + b.h) * z)
        case .radius:
            guard let cx = shape.number("cx"), let cy = shape.number("cy"), let r = shape.number("r") else { return nil }
            return CGPoint(x: (cx + abs(r)) * z, y: cy * z)
        case .start:
            guard let x = shape.number("x1"), let y = shape.number("y1") else { return nil }
            return CGPoint(x: (x + 0.5) * z, y: (y + 0.5) * z)
        case .end:
            guard let x = shape.number("x2"), let y = shape.number("y2") else { return nil }
            return CGPoint(x: (x + 0.5) * z, y: (y + 0.5) * z)
        }
    }

    // MARK: Gestures

    private func hit(_ p: CGPoint, _ z: CGFloat) -> Grab {
        if let index = state.selectedShape, shapes.indices.contains(index) {
            for handle in shapes[index].handles {
                if let h = handlePoint(shapes[index], handle, z), hypot(h.x - p.x, h.y - p.y) <= 22 { return .resize(index, shapes[index], handle) }
            }
        }
        // Topmost first; small shapes get a finger-sized target.
        for (index, shape) in shapes.enumerated().reversed() {
            guard let b = box(shape) else { continue }
            let rect = CGRect(x: b.x * z, y: b.y * z, width: b.w * z, height: b.h * z)
            let pad = max(0, (44 - min(rect.width, rect.height)) / 2)
            if rect.insetBy(dx: -pad, dy: -pad).contains(p) { return .move(index, shape) }
        }
        return .none
    }

    private func drag(_ value: DragGesture.Value, _ z: CGFloat) {
        if grab == nil {
            let size = CGSize(width: CGFloat(width) * z, height: CGFloat(height) * z)
            guard value.startLocation.x >= 0, value.startLocation.y >= 0, value.startLocation.x <= size.width, value.startLocation.y <= size.height else { return }
            grab = hit(value.startLocation, z)
            moved = false
            if case .move(let index, _) = grab { state.selectedShape = index }
            if case .resize(let index, _, _) = grab { state.selectedShape = index }
        }
        guard hypot(value.translation.width, value.translation.height) > 3 || moved else { return }
        moved = true
        var next = canvas
        switch grab {
        case .move(let index, let origin):
            next.shapes[index] = CanvasShape.moved(origin, dx: value.translation.width / z, dy: value.translation.height / z).json
        case .resize(let index, let origin, let handle):
            next.shapes[index] = CanvasShape.resized(origin, handle: handle, to: value.location.x / z, value.location.y / z).json
        default: return
        }
        onLive(next)
    }

    private func end(_ value: DragGesture.Value, _ z: CGFloat) {
        defer { grab = nil; moved = false }
        guard let grab else { return }
        if !moved {
            // A tap: select what is under the finger (or clear the selection).
            if case .none = grab { state.selectedShape = nil }
            return
        }
        var next = canvas
        switch grab {
        case .move(let index, let origin):
            next.shapes[index] = CanvasShape.moved(origin, dx: value.translation.width / z, dy: value.translation.height / z).json
            if next.shapes[index] != origin.json { onCommit(next, "Move shape") } else { onLive(canvas) }
        case .resize(let index, let origin, let handle):
            next.shapes[index] = CanvasShape.resized(origin, handle: handle, to: value.location.x / z, value.location.y / z).json
            if next.shapes[index] != origin.json { onCommit(next, "Resize shape") } else { onLive(canvas) }
        case .none: break
        }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(Array(shapes.enumerated()), id: \.offset) { index, shape in
                HStack(spacing: 8) {
                    Button { state.selectedShape = index } label: {
                        HStack(spacing: 6) {
                            Text(CanvasStrings.shapeTitle(index, shape.type)).font(.subheadline)
                            if shape.isPreserved { badge(CanvasStrings.preserved, .gray) }
                            else if shape.hasExpression { badge(CanvasStrings.expression, .purple) }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).accessibilityLabel(CanvasStrings.moveUp)
                    Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == shapes.count - 1).accessibilityLabel(CanvasStrings.moveDown)
                    Button(role: .destructive) { remove(index) } label: { Image(systemName: "trash") }
                        .accessibilityLabel(CanvasStrings.deleteShape)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(state.selectedShape == index ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvasShapeRow_\(index)")
            }
        }
    }

    private func add(_ type: String) {
        var next = canvas
        next.shapes.append(CanvasShape.make(type, size: (width, height)).json)
        state.selectedShape = next.shapes.count - 1
        onCommit(next, "Add \(CanvasStrings.typeName(type).lowercased())")
    }
    private func move(_ index: Int, by offset: Int) {
        var next = canvas
        var list = next.shapes
        let shape = list.remove(at: index)
        list.insert(shape, at: index + offset)
        next.shapes = list
        state.selectedShape = index + offset
        onCommit(next, "Move shape")
    }
    private func remove(_ index: Int) {
        var next = canvas
        next.shapes.remove(at: index)
        state.selectedShape = nil
        onCommit(next, "Delete shape")
    }
}

/// The numeric inspector: each field of the selected shape as text, committed on Return or when
/// the field loses focus (one undo step per field change). Expression fields carry a badge.
struct CanvasShapeInspector: View {
    var shape: CanvasShape
    var index: Int
    var onCommit: (CanvasShape) -> Void

    private var keys: [String] {
        let known = CanvasShape.fields(shape.type).map(\.name)
        // Unknown types: every key the shape has, so the inspector is still their editor.
        let extra = shape.object.keys.filter { $0 != "type" && !known.contains($0) && $0 != "if" }.sorted()
        return (known.isEmpty ? extra : known) + ["if"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(CanvasStrings.shapeTitle(index, shape.type)).font(.subheadline.weight(.semibold))
                if shape.isPreserved { Text(CanvasStrings.preservedHint).font(.caption2).foregroundStyle(.secondary) }
            }
            // Not lazy: every field exists for VoiceOver and UI tests even when scrolled away.
            let rows = stride(from: 0, to: keys.count, by: 3).map { Array(keys[$0..<min($0 + 3, keys.count)]) }
            ForEach(rows, id: \.self) { row in HStack(alignment: .top, spacing: 8) {
                ForEach(row, id: \.self) { key in
                    CanvasFieldEditor(label: CanvasStrings.fieldName(key), value: shape.text(key),
                                      isExpression: shape.isExpression(key), identifier: "canvasField_\(key)") { text in
                        var next = shape; next.setField(key, text: text)
                        if next != shape { onCommit(next) }
                    }
                }
            } }
            Text(CanvasStrings.fieldHint).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvasShapeInspector")
    }
}

/// One text field that keeps what is typed and commits on Return / end of editing.
struct CanvasFieldEditor: View {
    var label: String
    var value: String
    var isExpression = false
    var identifier: String
    var keyboard: UIKeyboardType = .numbersAndPunctuation
    var onCommit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if isExpression {
                    Text(CanvasStrings.expression).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).background(Color.purple, in: Capsule())
                }
            }
            TextField(label, text: $draft)
                .font(.caption.monospaced()).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { onCommit(draft) }
                .onChange(of: focused) { _, isFocused in if !isFocused, draft != value { onCommit(draft) } }
                .accessibilityIdentifier(identifier)
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
    }
}
