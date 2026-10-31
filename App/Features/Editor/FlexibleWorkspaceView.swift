import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState

/// Native authoring over the retained document. Width changes keep model, selection and draft intact.
@MainActor struct FlexibleWorkspaceView: View {
    @ObservedObject var model: LocalPageEditorModel
    @Binding var isTextInputActive: Bool
    var onRevealIssue: (FlexibleIssue) -> Void = { _ in }
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var selectedID: String?
    @State private var selectedShape: Int?
    @State private var selection = TemplateTextSelection()
    @State private var rich = true
    @State private var expression = "{{weather.temperature}}"
    @State private var insertionRange = NSRange(location: 0, length: 0)
    @State private var showExpression = false
    @State private var removeBlock = false
    @State private var removeShape = false
    @State private var showPageStyle = false
    @State private var showBlockStyle = false
    @State private var announcement = ""
    @State private var repairContainer: FlexibleLocation?
    @State private var repairInherits = false
    @FocusState private var fieldFocus: String?
    private var block: FlexibleBlock? { model.blocks.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.flexibleIssues.isEmpty {
                DisclosureGroup("Repair \(model.flexibleIssues.count) document fields", isExpanded: .constant(true)) {
                    ForEach(model.flexibleIssues) { issue in
                        Button {
                            finishTyping()
                            selectedID = issue.blockID ?? selectedID
                            selectedShape = issue.shapeIndex
                            if issue.blockID == nil { showPageStyle = true }
                            if case .blockStyle = issue.location { showBlockStyle = true }
                            DispatchQueue.main.async { fieldFocus = fieldID(issue.location, issue.key) }
                            announcement = issue.message
                            onRevealIssue(issue)
                        } label: {
                            Label("\(issue.blockID ?? "Page") · \(issue.message)", systemImage: "exclamationmark.triangle")
                                .font(.footnote).multilineTextAlignment(.leading)
                        }.accessibilityIdentifier("flexibleIssue_\(issue.key)")
                    }
                }.foregroundStyle(.red)
            }
            let layout = widthClass == .regular
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            layout {
                blockList.frame(width: widthClass == .regular ? 210 : nil)
                inspector.frame(maxWidth: widthClass == .regular ? 620 : .infinity, alignment: .leading)
            }
            DisclosureGroup("Page style, layout and targets", isExpanded: $showPageStyle) {
                VStack(alignment: .leading, spacing: 12) {
                    containerControls(.pageStyle, title: "page style", optional: true)
                    styleFields(.pageStyle)
                    containerControls(.layout, title: "layout", optional: true)
                    choice("Vertical alignment", .layout, "valign", ["top", "middle", "bottom", "spread"])
                    choice("Layout", .layout, "kind", ["stack"])
                    draftField("Gap", .layout, "gap", numeric: true, named: ["none", "small", "medium", "large"])
                    containerControls(.targets, title: "target restrictions", optional: true)
                    targetField("Allowed board IDs", key: "boards")
                    targetField("Allowed technologies", key: "technology")
                    Text("Separate target IDs with commas. Empty means an empty restriction list; use Inherit to remove the restriction.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.disclosureGroupStyle(FlexibleInspectorDisclosureStyle())
                .id("flexiblePageOptions")
            if !announcement.isEmpty { Text(announcement).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("flexibleActionOutcome") }
        }
        // This workspace is one Form row. Automatic styling promotes sibling actions
        // to the whole row; borderless buttons keep each text/Canvas action independent.
        .buttonStyle(.borderless)
        .disabled(model.editingFrozen)
        .onAppear { if selectedID == nil { selectedID = model.blocks.first?.id } }
        .onChange(of: model.blocks) { old, new in
            if !new.contains(where: { $0.id == selectedID }) { selectedID = new.first?.id; selectedShape = nil; selection = TemplateTextSelection() }
            // History may change another block. Reveal the first changed block.
            if let changed = new.first(where: { item in old.first(where: { $0.id == item.id }) != item }), old.count == new.count, changed.id != selectedID { selectedID = changed.id; selectedShape = nil }
        }
        .onChange(of: model.documentRevision) { _, _ in
            guard let location = model.historyFocus else { return }
            switch location {
            case .shape(let id, let index):
                selectedID = id
                selectedShape = model.shapes(id).isEmpty ? nil : min(index, model.shapes(id).count - 1)
            case .block(let id), .blockStyle(let id), .canvas(let id), .content(let id):
                if model.blocks.contains(where: { $0.id == id }) { selectedID = id }
            default: break
            }
        }
        .confirmationDialog("Reset this field?", isPresented: Binding(get: { repairContainer != nil }, set: { if !$0 { repairContainer = nil } }), titleVisibility: .visible) {
            if let location = repairContainer {
                Button(repairInherits ? "Use inherited value" : "Replace invalid container", role: .destructive) {
                    finishTyping(); model.resetFlexibleContainer(location, inherit: repairInherits)
                    repairContainer = nil; announcement = "Field reset. Undo restores its prior value."
                }
            }
            Button("Cancel", role: .cancel) { repairContainer = nil }
        } message: { Text("The selected value will be replaced. Undo restores its full previous content.") }
        .sheet(isPresented: $showExpression) {
            NavigationStack {
                Form {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Expression source", identifier: "flexibleExpressionSource_label")
                        TextField("Expression source", text: $expression, axis: .vertical)
                            .font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityIdentifier("flexibleExpressionSource")
                    }
                }
                .navigationTitle("Insert expression").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showExpression = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Insert") {
                            if let id = selectedID {
                                model.insertText(expression, blockID: id, selection: insertionRange)
                                selection.pendingCaret = NSRange(location: insertionRange.location + expression.utf16.count, length: 0)
                                announcement = "Inserted expression at the selected text."
                            }
                            showExpression = false
                        }.disabled(expression.isEmpty)
                    }
                }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("Remove selected block?", isPresented: $removeBlock, titleVisibility: .visible) {
            Button("Remove block", role: .destructive) { if let id = selectedID { finishTyping(); model.removeBlock(id); announcement = "Removed block. Undo restores its full content." } }
        }
        .confirmationDialog("Remove selected shape?", isPresented: $removeShape, titleVisibility: .visible) {
            Button("Remove shape", role: .destructive) { if let id = selectedID, let index = selectedShape { finishTyping(); model.removeShape(index, blockID: id); selectedShape = nil; announcement = "Removed shape. Undo restores it." } }
        }
    }
    private var blockList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Blocks").font(.headline)
                Spacer()
                Menu {
                    ForEach(["text", "canvas", "spacer"], id: \.self) { kind in
                        Button("Add \(kind.capitalized)", systemImage: icon(kind)) {
                            finishTyping(); selectedID = model.addBlock(kind); selectedShape = nil; selection = TemplateTextSelection(); announcement = "Added \(kind) block."
                        }.accessibilityIdentifier("addFlexible_\(kind)")
                    }
                } label: { Label("Add block", systemImage: "plus") }
                .disabled(model.blocks.count >= 32).accessibilityIdentifier("addFlexibleBlock")
            }
            ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, item in
                Button {
                    finishTyping(); selectedID = item.id; selectedShape = nil; selection = TemplateTextSelection()
                } label: {
                    HStack {
                        Image(systemName: icon(item.kind))
                        VStack(alignment: .leading) {
                            Text("\(index + 1). \(item.kind.capitalized)")
                            if case .string(let text) = item.value["text"] { Text(text.isEmpty ? "Empty text" : text).font(.caption).lineLimit(2) }
                            if !item.isKnown { Text("Preserved · read-only").font(.caption) }
                        }
                        Spacer()
                        if selectedID == item.id { Image(systemName: "checkmark") }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 6)
                    .accessibilityIdentifier("flexibleBlock_\(item.id)")
                    .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
            }
        }
    }
    @ViewBuilder private var inspector: some View {
        if let block {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(block.kind.capitalized) block").font(.headline)
                    Spacer()
                    Menu {
                        if let index = model.blocks.firstIndex(where: { $0.id == block.id }) {
                            Button("Move block up", systemImage: "arrow.up") { moveBlock(block.id, to: index - 1) }.disabled(index == 0)
                            Button("Move block down", systemImage: "arrow.down") { moveBlock(block.id, to: index + 1) }.disabled(index + 1 >= model.blocks.count)
                        }
                        Button("Remove block", systemImage: "trash", role: .destructive) { removeBlock = true }
                    } label: { Label("Block actions", systemImage: "ellipsis.circle") }.accessibilityIdentifier("flexibleBlockActions")
                }
                if block.kind == "text" {
                    Picker("Text mode", selection: $rich) { Text("Rich").tag(true); Text("Source").tag(false) }.pickerStyle(.segmented)
                    fieldLabel("Block text", identifier: "flexibleTextEditor_label")
                    NativeTemplateTextView(text: Binding(get: { model.flexibleText(.block(block.id), key: "text") }, set: { model.setFlexible(.block(block.id), key: "text", value: .string($0)) }), isEditing: $isTextInputActive, rich: rich, selection: selection, allowsMultiline: true, documentUndo: true) { source, range in
                        insertionRange = range; expression = source; finishTyping(); showExpression = true
                    }
                    .id(block.id).frame(height: 150).accessibilityIdentifier("flexibleTextEditor")
                    Button("Insert variable or expression", systemImage: "curlybraces") {
                        finishTyping(); insertionRange = selection.range; showExpression = true
                    }.accessibilityIdentifier("insertFlexibleExpression")
                } else if block.kind == "canvas" {
                    canvasInspector(block.id)
                } else if block.kind == "spacer" {
                    Text("This block reserves space using its style height.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("This block type is retained in full. Its content is read-only in this app.").font(.footnote)
                }
                if block.isKnown {
                    draftField("Condition expression", .block(block.id), "if")
                    draftField("Priority", .block(block.id), "priority", numeric: true)
                    DisclosureGroup("Block style", isExpanded: $showBlockStyle) {
                        containerControls(.blockStyle(block.id), title: "block style", optional: true)
                        styleFields(.blockStyle(block.id))
                    }.disclosureGroupStyle(FlexibleInspectorDisclosureStyle())
                }
            }.id("flexibleInspector")
        } else {
            Text("Add or select a block to edit its content.").foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func canvasInspector(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            containerControls(.canvas(id), title: "Canvas body", optional: false)
            Picker("Canvas input", selection: Binding(get: { model.flexibleValue(.canvas(id), key: "source") != nil && model.flexibleValue(.canvas(id), key: "source") != .null }, set: { source in
                finishTyping(); model.setFlexible(.canvas(id), key: "source", value: source ? .string("{{plugin.canvas}}") : nil)
            })) {
                Text("Drawing").tag(false); Text("Source expression").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("canvasInputMode")
            Text("Canvas drawing and fallback").font(.subheadline.bold())
            draftField("Source expression (optional)", .canvas(id), "source")
            containerControls(.content(id), title: "drawing content", optional: false)
            Text("A source expression may provide the drawing. The drawing below remains its fallback content.").font(.caption).foregroundStyle(.secondary)
            HStack {
                contentSize(id, axis: 0, title: "Width")
                contentSize(id, axis: 1, title: "Height")
            }
            draftField("Background", .content(id), "background")
            HStack {
                Text("Shapes").font(.subheadline.bold()); Spacer()
                Menu {
                    ForEach(["text", "rect", "line"], id: \.self) { kind in
                        Button("Add \(kind == "rect" ? "rectangle" : kind)") {
                            finishTyping(); model.addShape(kind, blockID: id); selectedShape = model.shapes(id).count - 1; announcement = "Added \(kind) shape."
                        }.accessibilityIdentifier("addShape_\(kind)")
                    }
                } label: { Label("Add shape", systemImage: "plus") }.accessibilityIdentifier("addCanvasShape").disabled(model.shapes(id).count >= 256)
            }
            ForEach(Array(model.shapes(id).enumerated()), id: \.offset) { index, shape in
                let kind = shapeKind(shape)
                Button {
                    finishTyping(); selectedShape = index
                } label: {
                    HStack {
                        Text("\(index + 1). \(kind == "rect" ? "Rectangle" : kind.capitalized)")
                        if !["text", "rect", "line"].contains(kind) { Text("Preserved · read-only").font(.caption) }
                        Spacer(); if selectedShape == index { Image(systemName: "checkmark") }
                    }
                }.accessibilityIdentifier("canvasShape_\(index)")
            }
            if let index = selectedShape, model.shapes(id).indices.contains(index) {
                shapeInspector(id, index: index)
            }
            Text("Drawing brushes and palette editing are planned. Existing palettes, pixels and other known shapes are retained.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func shapeInspector(_ id: String, index: Int) -> some View {
        let kind = shapeKind(model.shapes(id)[index])
        let location = FlexibleLocation.shape(id, index)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(kind.capitalized) \(index + 1)").font(.subheadline.bold()); Spacer()
                Button("Move shape up", systemImage: "arrow.up") { moveShape(id, index, by: -1) }.labelStyle(.iconOnly).disabled(index == 0)
                Button("Move shape down", systemImage: "arrow.down") { moveShape(id, index, by: 1) }.labelStyle(.iconOnly).disabled(index + 1 >= model.shapes(id).count)
                Button("Remove shape", systemImage: "trash", role: .destructive) { removeShape = true }.labelStyle(.iconOnly)
            }
            if ["text", "rect", "line"].contains(kind) {
                let keys = kind == "line" ? ["x1", "y1", "x2", "y2", "width"] : (kind == "rect" ? ["x", "y", "w", "h"] : ["x", "y"])
                ForEach(keys, id: \.self) { key in
                    HStack(alignment: .lastTextBaseline) {
                        draftField(fieldTitle(key), location, key, numeric: true)
                        Button("Decrease \(fieldTitle(key))", systemImage: "minus.circle") { adjust(location, key, by: -1) }.labelStyle(.iconOnly)
                        Button("Increase \(fieldTitle(key))", systemImage: "plus.circle") { adjust(location, key, by: 1) }.labelStyle(.iconOnly)
                    }
                }
                if kind == "text" {
                    draftField("Shape text", location, "text")
                    draftField("Text color", location, "color")
                    choice("Font", location, "font", ["3x5", "5x7"])
                } else if kind == "rect" {
                    draftField("Fill", location, "fill"); draftField("Stroke", location, "stroke")
                } else { draftField("Stroke", location, "stroke") }
            } else {
                Text("This shape is preserved without conversion. Remove it explicitly to repair unsupported content, or use the web editor.").font(.footnote)
            }
        }.padding(.top, 8).id("canvasShapeInspector")
    }
    private func styleFields(_ location: FlexibleLocation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            choice("Alignment", location, "align", ["left", "center", "right"])
            draftField("Font request", location, "font")
            draftField("Size", location, "size", numeric: true, named: ["small", "medium", "large", "xlarge", "fit"])
            draftField("Color", location, "color")
            draftField("Background", location, "background")
            choice("Letter case", location, "case", ["as-is", "upper", "lower"])
            choice("Overflow", location, "overflow", ["wrap", "shrink", "ellipsis", "scroll"])
            draftField("Height", location, "height", numeric: true, named: ["auto", "fill"])
        }
    }
    private func draftField(_ title: String, _ location: FlexibleLocation, _ key: String, numeric: Bool = false, named: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title, identifier: "flexibleField_\(key)_label")
            HStack(alignment: .firstTextBaseline) {
                TextField(title, text: Binding(get: { model.flexibleText(location, key: key) }, set: { text in
                    let value: LosslessJSON = numeric && !named.contains(text) ? FlexibleNumber.draft(text) : .string(text)
                    model.setFlexible(location, key: key, value: value)
                }), axis: .vertical)
                // The containing Form row can be taller than the viewport when styles
                // expand. Preserve the field's intrinsic lines instead of compressing them.
                .fixedSize(horizontal: false, vertical: true)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($fieldFocus, equals: fieldID(location, key))
                .accessibilityLabel(title).accessibilityIdentifier("flexibleField_\(key)")
                if model.flexibleValue(location, key: key) != nil {
                    Button("Inherit \(title)", systemImage: "arrow.uturn.backward") { finishTyping(); model.setFlexible(location, key: key, value: nil) }
                        .labelStyle(.iconOnly).accessibilityIdentifier("inheritFlexible_\(key)")
                }
            }
        }
    }
    private func choice(_ title: String, _ location: FlexibleLocation, _ key: String, _ values: [String]) -> some View {
        Picker(title, selection: Binding(get: { model.flexibleText(location, key: key) }, set: { model.setFlexible(location, key: key, value: $0.isEmpty ? nil : .string($0)) })) {
            Text("Inherit").tag("")
            let current = model.flexibleText(location, key: key)
            if !current.isEmpty && !values.contains(current) { Text(current).tag(current) }
            ForEach(values, id: \.self) { Text($0.capitalized).tag($0) }
        }.accessibilityIdentifier("flexibleChoice_\(key)")
    }
    private func targetField(_ title: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title, identifier: "flexibleTargets_\(key)_label")
            HStack {
                TextField(title, text: Binding(get: {
                    if case .array(let list) = model.flexibleValue(.targets, key: key) { list.map { FlexibleNumber.display($0) }.joined(separator: ", ") } else { model.flexibleText(.targets, key: key) }
                }, set: { text in model.setFlexible(.targets, key: key, value: .array(text.isEmpty ? [] : text.components(separatedBy: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) })) }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never).focused($fieldFocus, equals: fieldID(.targets, key))
                    .accessibilityIdentifier("flexibleTargets_\(key)")
                Button("Inherit \(title)", systemImage: "arrow.uturn.backward") { model.setFlexible(.targets, key: key, value: nil) }.labelStyle(.iconOnly)
            }
        }
    }
    private func contentSize(_ id: String, axis: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Canvas \(title)", identifier: "canvasSize_\(axis)_label")
            TextField(title, text: Binding(get: {
                if case .array(let values) = model.flexibleValue(.content(id), key: "size"), values.indices.contains(axis) { FlexibleNumber.display(values[axis]) } else { "" }
            }, set: { model.setContentSize(id, axis: axis, text: $0) }))
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .focused($fieldFocus, equals: fieldID(.content(id), axis == 0 ? "size" : "sizeHeight"))
            .accessibilityLabel("Canvas \(title)").accessibilityIdentifier("canvasSize_\(axis)")
        }
    }
    private func fieldLabel(_ title: String, identifier: String) -> some View {
        Text(title).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
    @ViewBuilder private func containerControls(_ location: FlexibleLocation, title: String, optional: Bool) -> some View {
        let value = model.flexibleContainerValue(location)
        if let value, value != .null {
            if case .object = value {
                if optional {
                    Button("Inherit \(title)") { repairInherits = true; repairContainer = location }
                        .font(.caption)
                }
            } else {
                Button("Repair invalid \(title)", systemImage: "wrench.and.screwdriver") {
                    repairInherits = optional; repairContainer = location
                }.accessibilityIdentifier("repairFlexibleContainer")
            }
        }
    }
    private func fieldID(_ location: FlexibleLocation, _ key: String) -> String { "\(location)/\(key)" }
    private func fieldTitle(_ key: String) -> String { ["x": "X position", "y": "Y position", "w": "Width", "h": "Height", "x1": "Start X", "y1": "Start Y", "x2": "End X", "y2": "End Y", "width": "Line width"][key] ?? key }
    private func icon(_ kind: String) -> String { kind == "text" ? "text.alignleft" : kind == "canvas" ? "paintpalette" : "square.dashed" }
    private func shapeKind(_ shape: LosslessJSON) -> String { if case .object(let object) = shape { FlexibleNumber.display(object["type"]) } else { "unknown" } }
    private func finishTyping() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func moveBlock(_ id: String, to index: Int) { finishTyping(); model.moveBlock(id, to: index); announcement = "Moved block to position \(index + 1)." }
    private func moveShape(_ id: String, _ index: Int, by offset: Int) { finishTyping(); model.moveShape(index, to: index + offset, blockID: id); selectedShape = index + offset; announcement = "Moved shape to position \(index + offset + 1)." }
    private func adjust(_ location: FlexibleLocation, _ key: String, by offset: Int) {
        guard case .number(let source) = model.flexibleValue(location, key: key), let current = Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")) else { announcement = "Enter a valid number before adjusting \(fieldTitle(key))."; return }
        finishTyping(); model.setFlexible(location, key: key, value: .number(NSDecimalNumber(decimal: current + Decimal(offset)).stringValue)); announcement = "Adjusted \(fieldTitle(key))."
    }
}

/// Each inspector header owns one explicit action inside the shared Form row.
/// Automatic DisclosureGroup headers can otherwise toggle sibling disclosures.
private struct FlexibleInspectorDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { configuration.isExpanded.toggle() }
            } label: {
                HStack {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }.foregroundStyle(.primary).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}
