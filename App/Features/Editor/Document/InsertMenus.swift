import SwiftUI
import UIKit
import FiestaBoardDocuments

/// The insert buttons' content (PLAN B15): Variables, Colors, Formatting, Insert formula. Wave 2
/// ships simple menus over fixed lists so the keyboard stays up and the caret stays put; iOS-F1
/// replaces `InsertPickers` with the searchable catalog and the formula editor (B21/B22) without
/// touching the toolbar, the accessory or the insertion path (`DocumentBuffer.insert`).
@MainActor struct InsertPickers {
    var variables: VariableCatalog
    var onInsert: (String) -> Void
    var onFormula: () -> Void

    // MARK: SwiftUI (toolbar under the title)

    @ViewBuilder var variablesMenu: some View {
        ForEach(variables.plugins, id: \.id) { plugin in
            Menu(plugin.name) {
                ForEach(plugin.fields, id: \.name) { field in
                    Button { onInsert(TemplateInsertion.variable(plugin.id, field.name)) } label: {
                        Text(field.name)
                        if let preview = field.preview { Text(String(preview.prefix(12))) }
                    }
                    .accessibilityIdentifier("insertVariable_\(plugin.id).\(field.name)")
                }
            }
        }
    }

    @ViewBuilder var colorsMenu: some View {
        ForEach(TemplateInsertion.colors, id: \.self) { color in
            Button { onInsert(TemplateInsertion.color(color)) } label: {
                Label { Text(color.capitalized) } icon: { Image(uiImage: Self.swatch(color)) }
            }
            .accessibilityIdentifier("insertColor_\(color)")
        }
        Divider()
        Button { onInsert(TemplateInsertion.degree) } label: { Text("° Degree") }
            .accessibilityIdentifier("insertDegree")
    }

    @ViewBuilder var formattingMenu: some View {
        ForEach(TemplateInsertion.formatting, id: \.source) { entry in
            Button { onInsert(entry.source) } label: {
                Text(entry.title)
                Text(entry.detail)
            }
            .accessibilityIdentifier("insertFormatting_\(entry.source)")
        }
    }

    // MARK: UIKit (keyboard accessory)

    func variablesUIMenu() -> UIMenu {
        UIMenu(title: EditorStrings.variables, children: variables.plugins.map { plugin in
            UIMenu(title: plugin.name, children: plugin.fields.map { field in
                let action = UIAction(title: field.name, subtitle: field.preview.map { String($0.prefix(12)) }) { _ in
                    onInsert(TemplateInsertion.variable(plugin.id, field.name))
                }
                action.accessibilityIdentifier = "insertVariable_\(plugin.id).\(field.name)"
                return action
            })
        })
    }

    func colorsUIMenu() -> UIMenu {
        let tiles = TemplateInsertion.colors.map { color in
            let action = UIAction(title: color.capitalized, image: Self.swatch(color)) { _ in onInsert(TemplateInsertion.color(color)) }
            action.accessibilityIdentifier = "insertColor_\(color)"
            return action
        }
        let degree = UIAction(title: "° Degree") { _ in onInsert(TemplateInsertion.degree) }
        degree.accessibilityIdentifier = "insertDegree"
        return UIMenu(title: EditorStrings.colors, children: [UIMenu(options: .displayInline, children: tiles), degree])
    }

    func formattingUIMenu() -> UIMenu {
        UIMenu(title: EditorStrings.formatting, children: TemplateInsertion.formatting.map { entry in
            let action = UIAction(title: entry.title, subtitle: entry.detail) { _ in onInsert(entry.source) }
            action.accessibilityIdentifier = "insertFormatting_\(entry.source)"
            return action
        })
    }

    /// A small board tile for menus, drawn by the same painter as the chips.
    static func swatch(_ color: String) -> UIImage {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return TemplateChipRenderer.tile(color: color, font: font, traits: .current, outlined: false).0.withRenderingMode(.alwaysOriginal)
    }
}

/// Insert formula (wave 2): a plain expression box that inserts `{{= … }}` at the caret. iOS-F1's
/// `FormulaEditorSheet` (catalog, colouring, live validation, B21) replaces this sheet.
struct FormulaInsertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expression: String
    @FocusState private var focused: Bool
    var onInsert: (String) -> Void

    init(initialExpression: String = "", onInsert: @escaping (String) -> Void) {
        _expression = State(initialValue: initialExpression); self.onInsert = onInsert
    }

    private static let examples = [
        #"IF(weather.temperature > 70, "WARM", "COOL")"#,
        #"UPPER(date_time.day_of_week)"#,
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("{{=").font(.body.monospaced()).foregroundStyle(.secondary)
                        TextField(EditorStrings.formulaPlaceholder, text: $expression, axis: .vertical)
                            .font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .focused($focused)
                            .accessibilityIdentifier("formulaExpression")
                        Text("}}").font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                } footer: { Text(EditorStrings.formulaFooter) }
                Section(EditorStrings.formulaExamples) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { expression = example } label: { Text(example).font(.footnote.monospaced()) }
                    }
                }
            }
            .navigationTitle(EditorStrings.insertFormula).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(EditorStrings.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(EditorStrings.insert) {
                        if let source = TemplateInsertion.formula(expression) { onInsert(source) }
                        dismiss()
                    }
                    .disabled(TemplateInsertion.formula(expression) == nil)
                    .accessibilityIdentifier("formulaInsert")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
