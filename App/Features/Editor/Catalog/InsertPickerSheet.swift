import SwiftUI
import FiestaBoardKit
import FiestaBoardDocuments

/// One of the three insert pickers in a sheet (PLAN B22, iOS-F1). Choosing an item closes the
/// sheet and hands back template source; the document inserts it at the caret it had.
struct InsertPickerSheet: View {
    let kind: InsertPickerKind
    @ObservedObject var store: EditorCatalogStore
    /// Note-shaped pages draw code 62 as a heart (web `ColorPickerContent`).
    var drawsHeart = false
    var onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(EditorStrings.cancel) { dismiss() } } }
        }
        .presentationDetents(kind == .variables ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        switch kind {
        case .variables: return EditorStrings.variables
        case .colors: return EditorStrings.colors
        case .formatting: return EditorStrings.formatting
        }
    }

    private func choose(_ source: String) { onInsert(source); dismiss() }

    @ViewBuilder private var content: some View {
        switch kind {
        case .variables:
            VariablePickerView(catalog: store.catalog, usesSample: store.usesSample) { path in choose("{{\(path)}}") }
        case .colors:
            ColorPickerView(colors: store.catalog.colors, drawsHeart: drawsHeart, onInsert: choose)
        case .formatting:
            FormattingPickerView(entries: store.catalog.formatting, colors: store.catalog.colors, onInsert: choose)
        }
    }
}

/// Colours as real board tiles in a grid (the shared tile painter), plus code 62.
struct ColorPickerView: View {
    let colors: [String]
    var drawsHeart = false
    var onInsert: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 12) {
                    ForEach(colors, id: \.self) { color in
                        Button { onInsert(TemplateInsertion.color(color)) } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: ColorPickerView.tile(color, size: 30)).interpolation(.high)
                                Text(color.capitalized).font(.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(color) tile")
                        .accessibilityIdentifier("insertColor_\(color)")
                    }
                }
                Button { onInsert(TemplateInsertion.degree) } label: {
                    Label(drawsHeart ? CatalogStrings.heart : CatalogStrings.degree, systemImage: drawsHeart ? "heart.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insertDegree")
            }
            .padding(16)
        }
    }

    @MainActor static func tile(_ color: String, size: CGFloat) -> UIImage {
        let font = UIFont.systemFont(ofSize: size / 1.1)
        return TemplateChipRenderer.tile(color: color, font: font, traits: .current, outlined: false).0
    }
}

/// Flexible space and repeated fills (web `FormattingPickerContent`): `fill_space_repeat` asks
/// for a colour or a character first.
struct FormattingPickerView: View {
    let entries: [TemplateCatalog.Formatting]
    let colors: [String]
    var onInsert: (String) -> Void
    @State private var pattern: TemplateCatalog.Formatting?
    @State private var custom = ""

    var body: some View {
        List {
            if let pattern {
                Section {
                    Button { self.pattern = nil } label: { Label("Back", systemImage: "chevron.left") }
                }
                Section(CatalogStrings.fillPattern) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(colors, id: \.self) { color in
                            Button { onInsert("{{fill_space_repeat:\(color)}}") } label: {
                                Image(uiImage: ColorPickerView.tile(color, size: 26))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(color) tiles")
                            .accessibilityIdentifier("insertFormatting_{{fill_space_repeat:\(color)}}")
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        ForEach(["-", "=", ".", "*"], id: \.self) { character in
                            Button(character) { onInsert("{{fill_space_repeat:\(character)}}") }
                                .font(.body.monospaced().weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.roundedRectangle)
                                .accessibilityIdentifier("insertFormatting_{{fill_space_repeat:\(character)}}")
                        }
                    }
                    HStack {
                        TextField(CatalogStrings.customCharacter, text: $custom)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .onChange(of: custom) { _, value in if value.count > 1 { custom = String(value.suffix(1)) } }
                        Button(EditorStrings.insert) { onInsert("{{fill_space_repeat:\(custom)}}") }.buttonStyle(.borderless)
                            .disabled(custom.isEmpty || custom == "}" || custom == "{")
                    }
                }
            } else {
                ForEach(entries) { entry in
                    Button {
                        if entry.takesPattern { pattern = entry } else { onInsert(entry.syntax) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Spacer()
                                if entry.takesPattern { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                            }
                            if let summary = entry.summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insertFormatting_\(entry.syntax)")
                }
            }
        }
    }
}
