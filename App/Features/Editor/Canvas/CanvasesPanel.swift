import SwiftUI
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit

/// The editor's pixel canvases on an LED pixel board (web `CanvasesPanel`, PLAN B24): the page's
/// canvases, Add canvas, and for the one being edited its ID, area (drag-select grid plus row /
/// column fields), bleed, scale, text mode and the Draw | Shapes tabs. Every change is one undo
/// step in the page's session; gestures show on the stage while they run.
struct CanvasesPanel: View {
    @ObservedObject var model: LocalPageEditorModel
    @ObservedObject var state: CanvasEditorState
    var display: PixelDisplay
    /// The page's character grid.
    var gridRows: Int
    var gridCols: Int
    /// After every committed change (the stage re-renders through the pipeline).
    var onCommitted: () -> Void

    @State private var idDraft = ""

    private var canvases: [LegacyCanvas] { state.canvases(model) }
    private var index: Int? { state.selectedIndex(canvases) }
    private var editable: Bool { model.canvasesAreEditable && !model.editingFrozen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.canvasesAreEditable {
                Text(CanvasStrings.readOnly).font(.footnote).foregroundStyle(.orange)
            }
            problems
            if canvases.isEmpty {
                Text(CanvasStrings.empty).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("canvasesEmpty")
            } else {
                list
                if let index { editor(canvases[index], at: index).disabled(!editable) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvasesPanel")
    }

    // MARK: Header and list

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(CanvasStrings.title).font(.headline)
                Spacer()
                Button(EditorStrings.undo, systemImage: "arrow.uturn.backward") { model.undo(); after() }
                    .labelStyle(.iconOnly).disabled(!model.canUndo || model.editingFrozen).accessibilityIdentifier("canvasUndo")
                Button(EditorStrings.redo, systemImage: "arrow.uturn.forward") { model.redo(); after() }
                    .labelStyle(.iconOnly).disabled(!model.canRedo || model.editingFrozen).accessibilityIdentifier("canvasRedo")
                Button { add() } label: { Label(CanvasStrings.add, systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!editable || canvases.count >= CanvasLimits.maxCanvases)
                    .accessibilityIdentifier("addCanvas")
            }
            Text(CanvasStrings.description).font(.caption).foregroundStyle(.secondary)
            if canvases.count >= CanvasLimits.maxCanvases {
                Text(CanvasStrings.limitReached(CanvasLimits.maxCanvases)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var problems: some View {
        let issues = (model.previewStale ? [] : model.lastPreview?.canvasIssues ?? [])
        let local = model.canvasesAreEditable ? model.canvasProblems : []
        if !issues.isEmpty || !local.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(CanvasStrings.issuesTitle).font(.caption.weight(.semibold))
                ForEach(local, id: \.self) { Text($0).font(.caption) }
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text("\(issue.canvasID ?? "canvas") · \(issue.path ?? ""): \(issue.message)").font(.caption)
                }
            }
            .foregroundStyle(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("canvasIssues")
        }
    }

    private var list: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(canvases, id: \.id) { canvas in
                    let selected = canvas.id == canvases[index ?? 0].id
                    Button { select(canvas.id) } label: {
                        Text(canvas.id.isEmpty ? "—" : canvas.id).font(.subheadline.monospaced())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground), in: Capsule())
                            .overlay(Capsule().stroke(selected ? Color.accentColor : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit canvas \(canvas.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("canvasChip_\(canvas.id)")
                }
            }
        }
    }

    // MARK: One canvas

    private func editor(_ canvas: LegacyCanvas, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            idRow(canvas, at: index)
            area(canvas, at: index)
            options(canvas, at: index)
            Picker("Canvas tools", selection: $state.tab) {
                Text(CanvasStrings.tabDraw).tag(CanvasEditorState.Tab.draw)
                Text(CanvasStrings.tabShapes).tag(CanvasEditorState.Tab.shapes)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("canvasTabs")
            let pad = padSize(canvas)
            switch state.tab {
            case .draw:
                CanvasDrawTab(canvas: canvas, width: pad.width, height: pad.height, state: state,
                              onLive: { live(index, $0) }, onCommit: { commit(index, $0, action: $1) })
            case .shapes:
                CanvasShapesTab(canvas: canvas, width: pad.width, height: pad.height, state: state,
                                onLive: { live(index, $0) }, onCommit: { commit(index, $0, action: $1) })
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator)))
        .onAppear { idDraft = canvas.id }
        .onChange(of: canvas.id) { _, id in idDraft = id }
    }

    private func idRow(_ canvas: LegacyCanvas, at index: Int) -> some View {
        let taken = canvases.enumerated().contains { $0.offset != index && $0.element.id == idDraft }
        let valid = CanvasLimits.validID(idDraft) && !taken
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CanvasStrings.idLabel).font(.caption).foregroundStyle(.secondary)
                TextField(CanvasStrings.idLabel, text: $idDraft)
                    .font(.subheadline.monospaced()).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit {
                        if valid, idDraft != canvas.id { var next = canvas; next.id = idDraft; state.selectedID = idDraft; commit(index, next, action: "Rename canvas") }
                    }
                    .accessibilityIdentifier("canvasID")
                Text(valid ? CanvasStrings.idHint : CanvasStrings.idInvalid).font(.caption2).foregroundStyle(valid ? Color.secondary : Color.red)
            }
            Spacer()
            Button(role: .destructive) { remove(index) } label: { Label(CanvasStrings.delete, systemImage: "trash") }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Delete canvas \(canvas.id)")
                .accessibilityIdentifier("deleteCanvas")
        }
    }

    private func area(_ canvas: LegacyCanvas, at index: Int) -> some View {
        let area = canvas.area ?? CanvasArea(row: 1, col: 1, rows: 1, cols: 1)
        let pitch = CGFloat(display.board.glyphWidth + 1) / CGFloat(display.board.glyphHeight + 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(CanvasStrings.areaLabel).font(.caption.weight(.medium))
            CanvasAreaPicker(rows: gridRows, cols: gridCols, canvases: canvases, activeID: canvas.id, cellAspect: pitch,
                             onChanging: { var next = canvas; next.area = $0; live(index, next) },
                             onCommit: { var next = canvas; next.area = $0; commit(index, next, action: "Change canvas area") })
            HStack(spacing: 8) {
                areaField(CanvasStrings.areaRow, area.row, id: "canvasAreaRow", canvas: canvas, index: index) { var a = area; a.row = $0; return a }
                areaField(CanvasStrings.areaCol, area.col, id: "canvasAreaCol", canvas: canvas, index: index) { var a = area; a.col = $0; return a }
                areaField(CanvasStrings.areaRows, area.rows, id: "canvasAreaRows", canvas: canvas, index: index) { var a = area; a.rows = $0; return a }
                areaField(CanvasStrings.areaCols, area.cols, id: "canvasAreaCols", canvas: canvas, index: index) { var a = area; a.cols = $0; return a }
            }
            Text(CanvasStrings.areaPickerHint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func areaField(_ label: String, _ value: Int, id: String, canvas: LegacyCanvas, index: Int,
                           _ change: @escaping (Int) -> CanvasArea) -> some View {
        CanvasFieldEditor(label: label, value: String(value), identifier: id, keyboard: .numberPad) { text in
            guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n >= 1 else { return }
            var next = canvas; next.area = change(n)
            if next != canvas { commit(index, next, action: "Change canvas area") }
        }
    }

    private func options(_ canvas: LegacyCanvas, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CanvasStrings.bleedLabel).font(.caption.weight(.medium))
            HStack(spacing: 6) {
                ForEach(CanvasLimits.bleedSides, id: \.self) { side in
                    let on = canvas.bleed.contains(side)
                    Button {
                        var next = canvas; var sides = canvas.bleed
                        if on { sides.remove(side) } else { sides.insert(side) }
                        next.bleed = sides
                        commit(index, next, action: "Change bleed")
                    } label: {
                        Label(CanvasStrings.bleedNames[side] ?? side, systemImage: on ? "checkmark.square.fill" : "square")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(on ? .accentColor : .secondary)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("canvasBleed_\(side)")
                }
            }
            HStack(spacing: 16) {
                Stepper(value: Binding(get: { canvas.scale }, set: { value in
                    var next = canvas; next.scale = value; commit(index, next, action: "Change scale")
                }), in: 1...CanvasLimits.maxScale) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(CanvasStrings.scaleLabel).font(.caption).foregroundStyle(.secondary)
                        Text(CanvasStrings.scaleOption(canvas.scale)).font(.subheadline.monospacedDigit())
                    }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("canvasScale")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(CanvasStrings.textModeLabel).font(.caption).foregroundStyle(.secondary)
                Picker(CanvasStrings.textModeLabel, selection: Binding(get: { canvas.textMode }, set: { mode in
                    var next = canvas; next.textMode = mode; commit(index, next, action: "Change text under canvas")
                })) {
                    Text(CanvasStrings.textHide).tag("hide")
                    Text(CanvasStrings.textFlow).tag("flow")
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
                .accessibilityIdentifier("canvasTextMode")
            }
        }
    }

    /// The pad's pixel size: the content's own `size`, else the canvas's pixel size on the board.
    private func padSize(_ canvas: LegacyCanvas) -> (width: Int, height: Int) {
        if let size = canvas.contentSize { return (min(CanvasLimits.maxPixels, max(1, size.width)), min(CanvasLimits.maxPixels, max(1, size.height))) }
        if let placement = CanvasPlacement.of(canvas, board: display.board) {
            return (min(CanvasLimits.maxPixels, placement.width), min(CanvasLimits.maxPixels, placement.height))
        }
        return (32, 32)
    }

    // MARK: Writes

    private func select(_ id: String) {
        state.selectedID = id; state.selectedShape = nil
    }
    private func live(_ index: Int, _ canvas: LegacyCanvas) {
        var next = model.canvases
        guard next.indices.contains(index) else { return }
        next[index] = canvas
        state.live = next
    }
    private func commit(_ index: Int, _ canvas: LegacyCanvas, action: String) {
        var next = model.canvases
        guard next.indices.contains(index) else { state.live = nil; return }
        next[index] = canvas
        state.live = nil
        model.setCanvases(next, action: action)
        after()
    }
    private func add() {
        let current = model.canvases
        let id = LegacyCanvas.nextID(current)
        // Starts over the top-left half of the board: easy to see, easy to move (web).
        let area = CanvasArea(row: 1, col: 1, rows: max(1, (gridRows + 1) / 2), cols: max(1, (gridCols + 1) / 2))
        model.setCanvases(current + [LegacyCanvas.make(id: id, area: area)], action: "Add canvas")
        state.selectedID = id; state.selectedShape = nil
        after()
    }
    private func remove(_ index: Int) {
        var next = model.canvases
        guard next.indices.contains(index) else { return }
        next.remove(at: index)
        model.setCanvases(next, action: "Delete canvas")
        state.selectedID = next.first?.id; state.selectedShape = nil
        after()
    }
    private func after() {
        state.live = nil
        onCommitted()
    }
}
