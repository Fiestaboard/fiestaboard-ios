import SwiftUI
import FiestaBoardKit

/// The Variables picker (PLAN B22): a search field, then each plugin as a section with its icon
/// and readable name, group headers, pills per field with a faded 12-character value preview,
/// and array items as expandable rows with their index (or a hint when the array is empty).
/// Search filters across plugin, field, dotted path and words split on `._-`. A pill hands back
/// the variable's path; the document wraps it as `{{path}}`, the formula editor inserts it bare.
struct VariablePickerView: View {
    let catalog: TemplateCatalog
    var usesSample = false
    var autoFocusSearch = true
    var onInsert: (String) -> Void
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if !catalog.hasVariables && !usesSample {
                emptyState(CatalogStrings.noVariables, symbol: "puzzlepiece.extension")
                    .accessibilityIdentifier("noVariablesNote")
            } else {
                let plugins = catalog.filtered(query)
                if plugins.isEmpty {
                    emptyState(CatalogStrings.noMatches(query), symbol: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if usesSample {
                                Text(CatalogStrings.sampleNote).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(plugins) { plugin in section(plugin) }
                        }
                        .padding(12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .onAppear { if autoFocusSearch { searchFocused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("variablePicker")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(CatalogStrings.searchVariables, text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityIdentifier("variableSearch")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.borderless).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private func emptyState(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func section(_ plugin: TemplateCatalog.Plugin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: EditorCatalogStore.symbol(for: plugin))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                Text(plugin.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("variablePlugin_\(plugin.id)")
            ForEach(plugin.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    if !group.label.isEmpty {
                        Text(group.label.uppercased()).font(.caption2.weight(.semibold)).tracking(1)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    PillFlowLayout(spacing: 6) {
                        ForEach(group.fields) { field in pill(field, label: field.label) }
                    }
                }
            }
            ForEach(plugin.arrays) { array in arraySection(plugin, array) }
        }
    }

    @ViewBuilder private func arraySection(_ plugin: TemplateCatalog.Plugin, _ array: TemplateCatalog.ArrayVariable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(TemplateCatalog.titleCase(array.name)) (\(array.items.count))".uppercased())
                .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            if array.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CatalogStrings.arrayHint(array.name)).font(.caption)
                    Text("Example: \(array.name).0.*").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("variableArrayHint_\(array.name)")
            }
            ForEach(array.items) { item in
                let key = "\(plugin.id).\(array.name).\(item.index)"
                DisclosureGroup(isExpanded: Binding(get: { !query.isEmpty || expanded.contains(key) },
                                                    set: { open in if open { expanded.insert(key) } else { expanded.remove(key) } })) {
                    PillFlowLayout(spacing: 6) {
                        ForEach(item.fields) { field in
                            pill(field, label: field.label)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(item.index)").font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(uiColor: .separator)))
                        Text(item.label ?? "Item \(item.index)").font(.subheadline).lineLimit(1)
                    }
                    // On the label: an identifier on the group would also rename its pills.
                    .accessibilityIdentifier("variableArrayItem_\(array.name)_\(item.index)")
                }
            }
        }
    }

    private func pill(_ field: TemplateCatalog.Field, label: String) -> some View {
        Button { onInsert(field.path) } label: {
            HStack(spacing: 5) {
                Text(label).font(.subheadline.weight(.medium))
                if let preview = field.shortPreview {
                    Text(preview).font(.caption2).foregroundStyle(.secondary).opacity(0.8)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(TemplateChipRenderer.violet.swiftUI)
            .background(Color(uiColor: TemplateChipRenderer.violet).opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(uiColor: TemplateChipRenderer.violet).opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .buttonStyle(.plain)
        // Readable label on screen; the raw path stays in the hint (and in search).
        .accessibilityLabel(field.preview.map { "\(label), now \($0)" } ?? label)
        .accessibilityHint([field.summary, "{{\(field.path)}}"].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier("insertVariable_\(field.path)")
    }
}

private extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}

/// Wraps its children into rows (pills).
struct PillFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
