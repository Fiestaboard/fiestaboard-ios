import SwiftUI
import FiestaBoardDocuments
import FiestaBoardEditorState

/// Authoring canvas and contextual row inspector. The canvas is deliberately a design
/// projection: live variables, wrapping and fill expansion require server evaluation.
struct TemplateWorkspaceView: View {
    @ObservedObject var model: LocalPageEditorModel
    @Binding var isTextInputActive: Bool
    @State private var selectedRow = 0
    @State private var rich = true
    @State private var textSelection = TemplateTextSelection()
    @State private var tokenEditing: TokenEditing?
    @State private var availableWidth: CGFloat = 0
    @State private var confirmRemove = false

    private var geometry: TemplateGeometry? { model.authoringGeometry }
    private var isPanel: Bool { geometry?.isPanel ?? false }
    private var columns: Int { geometry?.columns ?? 0 }
    private var rows: [String] { model.lines ?? [] }
    private var hasSelection: Bool { rows.indices.contains(selectedRow) }
    private var rowBinding: Binding<String> { Binding(get: { hasSelection ? rows[selectedRow] : "" }, set: { if hasSelection { model.setLine(selectedRow, text: $0) } }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(geometry == nil ? "Template design" : (isPanel ? "LED design" : "Split-flap design"), systemImage: "rectangle.split.3x3")
                    .font(.headline)
                Spacer()
                Text(geometry.map { "\($0.rows) × \($0.columns)" } ?? "Unknown size").font(.caption).foregroundStyle(.secondary)
            }
            if availableWidth >= 760 {
                HStack(alignment: .top, spacing: 24) {
                    canvas.frame(maxWidth: .infinity)
                    inspector.frame(width: 310)
                }
            } else {
                canvas
                inspector
            }
            Text("Design view · Dynamic tokens appear as ◇. Server preview determines final values, spacing, wrapping, and supported characters.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { availableWidth = $0 })
        .onChange(of: rows.count) { _, count in selectedRow = max(0, min(selectedRow, count - 1)) }
        .disabled(model.editingFrozen)
        .sheet(item: $tokenEditing) { draft in
            TemplateTokenSheet(initialSource: draft.source) { source in
                applyToken(source, selection: draft.selection)
                tokenEditing = nil
            }
        }
        .confirmationDialog("Delete row \(selectedRow + 1)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Delete row", role: .destructive) { finishTyping(); model.removeLine(selectedRow) }
        } message: { Text("The row’s text and formatting will be removed. You can undo this change.") }
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                ContentUnavailableView("Start your page", systemImage: "character.cursor.ibeam", description: Text("Add a row, then type or insert a dynamic token."))
                Button("Add first row", systemImage: "plus") { model.insertLine(after: nil); selectedRow = 0 }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("addFirstTemplateRow")
            } else {
                if geometry == nil {
                    Label("Board size unavailable. Source editing is still available.", systemImage: "questionmark.square.dashed").font(.footnote)
                }
                if let geometry, rows.count > geometry.rows {
                    Label("\(rows.count - geometry.rows) authored rows extend beyond the board height.", systemImage: "arrow.down.to.line").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 5) {
                            ForEach(rows.indices, id: \.self) { index in
                                Button {
                                    finishTyping(); textSelection = TemplateTextSelection(); selectedRow = index
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                                        if geometry != nil {
                                            TemplateDesignRow(source: rows[index], columns: columns, panel: isPanel, alignment: model.lineAlignment(index))
                                            .frame(height: 36)
                                        } else { Text(rows[index].isEmpty ? "Empty row" : rows[index]).lineLimit(1).frame(height: 36) }
                                    }
                                    .padding(5)
                                    .background(selectedRow == index ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedRow == index ? Color.accentColor : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Row \(index + 1)")
                                .accessibilityValue(rows[index].isEmpty ? "Empty" : rows[index])
                                .accessibilityAddTraits(selectedRow == index ? [.isSelected] : [])
                                .accessibilityIdentifier("templateCanvasRow\(index)")
                            }
                        }.padding(3)
                    }.scrollDisabled(rows.count <= 6)
                    .frame(height: min(360, CGFloat(rows.count) * 51 + 6))
                    .frame(width: max(280, min(availableWidth >= 760 ? availableWidth - 334 : availableWidth, CGFloat(columns) * 24) - 4, CGFloat(columns) * 12 + 44))
                }
                HStack {
                    Button("Add row", systemImage: "plus") { finishTyping(); model.insertLine(after: selectedRow); textSelection = TemplateTextSelection(); selectedRow = min(selectedRow + 1, rows.count - 1) }
                        .accessibilityIdentifier("addTemplateRow")
                    Spacer()
                    Menu {
                        Button("Duplicate row", systemImage: "plus.square.on.square") { finishTyping(); model.duplicateLine(selectedRow); textSelection = TemplateTextSelection(); selectedRow += 1 }
                        Button("Move row up", systemImage: "arrow.up") { move(by: -1) }.disabled(selectedRow == 0)
                        Button("Move row down", systemImage: "arrow.down") { move(by: 1) }.disabled(selectedRow + 1 >= rows.count)
                        Button("Delete row", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    } label: { Label("Row actions", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("templateRowActions")
                }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if hasSelection {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Row \(selectedRow + 1)").font(.headline)
                    Spacer()
                    Picker("Editing mode", selection: $rich) {
                        Text("Rich").tag(true); Text("Source").tag(false)
                    }.pickerStyle(.segmented).frame(maxWidth: 180)
                    .onChange(of: rich) { _, _ in finishTyping() }
                }
                NativeTemplateTextView(text: rowBinding, isEditing: $isTextInputActive, rich: rich, selection: textSelection) { source, range in
                    finishTyping(); tokenEditing = TokenEditing(source: source, selection: range)
                }
                .id(selectedRow)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
                HStack(spacing: 12) {
                    Menu {
                        Button("Variable", systemImage: "curlybraces") { editNewToken("{{weather.temperature}}") }
                        Button("Formula", systemImage: "function") { editNewToken("{{= 1 + 1 }}") }
                        Button("Flexible space", systemImage: "arrow.left.and.right") { insert("{{fill_space}}") }
                        Button("Repeating fill", systemImage: "repeat") { editNewToken("{{fill_space_repeat:-}}") }
                        if geometry?.isPanel == false {
                            Section("Color tile") {
                                ForEach(TemplateSyntax.tileColors.filter { $0 != "purple" }, id: \.self) { color in
                                    Button(color.capitalized) { insert("{{\(color)}}") }
                                }
                            }
                        }
                    } label: { Label("Insert", systemImage: "plus.circle") }
                    .accessibilityIdentifier("insertTemplateToken")
                    Spacer()
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { finishTyping() }
                        .labelStyle(.iconOnly).accessibilityIdentifier("editorHideKeyboard")
                }.buttonStyle(.bordered)
                Picker("Alignment", selection: Binding(get: { model.lineAlignment(selectedRow) }, set: { finishTyping(); model.setLineAlignment(selectedRow, alignment: $0) })) {
                    Label("Left", systemImage: "text.alignleft").tag("left")
                    Label("Center", systemImage: "text.aligncenter").tag("center")
                    Label("Right", systemImage: "text.alignright").tag("right")
                }.pickerStyle(.segmented).accessibilityIdentifier("templateAlignment")
                Toggle("Wrap text", isOn: Binding(get: { model.lineWrap(selectedRow) }, set: { finishTyping(); model.setLineWrap(selectedRow, wrap: $0) }))
                Text("Tap a token to edit its source. Copying rich text keeps its template syntax.")
                    .font(.caption).foregroundStyle(.secondary)
                if isPanel {
                    Text("LED spans and icons are preserved. New color and icon choices are not available yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func finishTyping() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func insert(_ source: String) { finishTyping(); applyToken(source, selection: textSelection.range) }
    private func applyToken(_ source: String, selection: NSRange) {
        guard hasSelection, !model.editingFrozen else { return }
        let original = rows[selectedRow] as NSString
        guard selection.location <= original.length, NSMaxRange(selection) <= original.length else { return }
        textSelection.pendingCaret = NSRange(location: selection.location + source.utf16.count, length: 0)
        model.setLine(selectedRow, text: original.replacingCharacters(in: selection, with: source))
    }
    private func editNewToken(_ source: String) { finishTyping(); tokenEditing = TokenEditing(source: source, selection: textSelection.range) }
    private func move(by offset: Int) { finishTyping(); let next = selectedRow + offset; model.moveLine(selectedRow, to: next); textSelection = TemplateTextSelection(); selectedRow = next }
}

private struct TemplateDesignRow: View {
    let source: String
    let columns: Int
    let panel: Bool
    let alignment: String
    private struct Cell { let text: String; let color: Color? }
    private var cells: [Cell] {
        var cells: [Cell] = []
        for token in TemplateSyntax.fragments(source) {
            if token.kind == .tile { cells.append(Cell(text: "", color: color(token.label))) }
            else if token.kind == .text { cells += token.source.map { Cell(text: String($0), color: nil) } }
            else { cells.append(Cell(text: token.kind == .fill ? "↔" : "◇", color: nil)) }
        }
        let leading = max(0, columns - cells.count)
        if alignment == "right" { cells.insert(contentsOf: Array(repeating: Cell(text: "", color: nil), count: leading), at: 0) }
        if alignment == "center" { cells.insert(contentsOf: Array(repeating: Cell(text: "", color: nil), count: leading / 2), at: 0) }
        return Array(cells.prefix(columns))
    }
    var body: some View {
        Canvas { context, size in
            let values = cells
            let width = size.width / CGFloat(columns)
            for index in 0..<columns {
                let cell = index < values.count ? values[index] : Cell(text: "", color: nil)
                let rect = CGRect(x: CGFloat(index) * width + 1, y: 1, width: max(1, width - 2), height: size.height - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: panel ? 2 : 3), with: .color(cell.color ?? Color(white: 0.12)))
                if !panel {
                    context.fill(Path(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: 1)), with: .color(.black.opacity(0.4)))
                }
                context.draw(Text(cell.text).font(.system(size: min(19, width * 0.8), weight: .medium, design: .monospaced)).foregroundStyle(.white), at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }.accessibilityHidden(true)
    }
    private func color(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "blue": .blue
        case "purple", "violet": .purple
        case "white", "filled": .white
        default: .black
        }
    }
}

private struct TokenEditing: Identifiable {
    let id = UUID()
    let source: String
    let selection: NSRange
}
private struct TemplateTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    var onApply: (String) -> Void
    init(initialSource: String, onApply: @escaping (String) -> Void) {
        _source = State(initialValue: initialSource); self.onApply = onApply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Template token") {
                    TextField("Token source", text: $source, axis: .vertical)
                        .font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityIdentifier("tokenSource")
                    Text("Keep the braces and any filters. The server evaluates the expression.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit token").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") { onApply(source) }
                        .disabled(source.isEmpty || source.contains("\n") || source.contains("\r"))
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
