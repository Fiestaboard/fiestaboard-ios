import SwiftUI
import FiestaBoardKit

enum ComposePicker: String, Identifiable {
    case variables, textColor, tiles, icons, formatting, formula
    var id: String { rawValue }
    var title: String {
        switch self {
        case .variables: "Variables"
        case .textColor: "Text color"
        case .tiles: "Colors"
        case .icons: "Icon"
        case .formatting: "Formatting"
        case .formula: "Formula"
        }
    }
}

struct ComposeInsertSheet: View {
    let kind: ComposePicker
    let catalog: TemplateCatalog?
    let functions: FunctionCatalog?
    let tools: ComposeTools
    let validate: (String) async throws -> FormulaCheck
    let insert: (String, Bool) -> Void
    @State private var expression = ""
    @State private var check: FormulaCheck?
    @State private var checking = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .variables:
                    if let catalog { VariablePickerView(catalog: catalog, usesSample: false) { insert("{{\($0)}}", false) } }
                case .textColor:
                    List(catalog?.colors ?? [], id: \.self) { color in
                        Button(color.capitalized) { insert(color, true) }
                    }
                case .tiles:
                    if tools.tiles { ColorPickerView(colors: catalog?.colors ?? []) { insert($0, false) } }
                case .icons:
                    List(tools.icons, id: \.self) { icon in Button(icon) { insert("{{icon.\(icon)}}", false) } }
                case .formatting:
                    if let catalog { FormattingPickerView(entries: catalog.formatting, colors: tools.tiles ? catalog.colors : []) { insert($0, false) } }
                case .formula: formula
                }
            }
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationSizing(.form)
    }
    private var formula: some View {
        Form {
            Section("Expression") {
                TextField("Formula expression", text: $expression, axis: .vertical)
                    .font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("composeFormulaSource")
                if checking { ProgressView("Checking…") }
                if let check { Text(check.valid ? "Formula is valid" : check.messages.joined(separator: "\n")).font(.callout) }
                if let issue { Text(issue).font(.callout) }
                Button("Insert formula") { insert("{{= \(expression) }}", false) }
                    .disabled(check?.valid != true || checking)
            }
            if let functions {
                ForEach(functions.categories) { category in
                    Section(category.name.capitalized) {
                        ForEach(category.functions) { function in
                            Button { expression += function.signature } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(function.name).font(.body.monospaced())
                                    Text(function.signature).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: expression) {
            check = nil; issue = nil
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { checking = false; return }
            checking = true
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await validate(expression)
                guard !Task.isCancelled else { return }
                check = result; checking = false
            } catch {
                guard !Task.isCancelled else { return }
                checking = false; issue = "Validation unavailable. Try again when connected."
            }
        }
    }
}
