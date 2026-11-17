import SwiftUI
import UIKit
import FiestaBoardKit
import FiestaBoardDocuments

/// The formula editor (PLAN B21, web `FormulaEditorPanel.tsx`): a `{{=` … `}}` framed code box
/// with syntax colouring (functions violet, strings green, numbers orange, variables sky), a
/// Functions | Variables picker (phone: stacked under the box; wide: a column beside it),
/// 300 ms validation (green check and border / red X, border and the server's message without
/// "Formula "), and Insert/Done enabled only for the expression that last validated as valid.
/// Nothing evaluates the formula here (parity with the web).
struct FormulaEditorSheet: View {
    @ObservedObject var store: EditorCatalogStore
    /// The bare expression of the pill being edited; empty for a new formula.
    let initialExpression: String
    let isEditing: Bool
    var onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var validator: FormulaValidator
    @StateObject private var code = FormulaCodeController()
    @State private var tab = Tab.functions
    @State private var collapsed: Set<String> = []

    enum Tab: String, CaseIterable { case functions, variables }

    init(store: EditorCatalogStore, initialExpression: String, isEditing: Bool, onConfirm: @escaping (String) -> Void) {
        self.store = store
        self.initialExpression = initialExpression
        self.isEditing = isEditing
        self.onConfirm = onConfirm
        _validator = StateObject(wrappedValue: FormulaValidator { [weak store] expression in
            guard let store else { throw CancellationError() }
            return try await store.check(expression)
        })
    }

    private var expression: String { FormulaHighlighter.flatten(code.text) }
    /// Unchanged text gives back the original bytes (pretty-printing drops spaces after commas).
    private var confirmedExpression: String {
        let flat = expression
        return flat == FormulaHighlighter.flatten(FormulaHighlighter.pretty(initialExpression)) && !initialExpression.isEmpty
            ? initialExpression.trimmingCharacters(in: .whitespacesAndNewlines) : flat
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // W4: side by side whenever the sheet is wide enough (the iPad page sheet, ≥ 600 pt),
                // not only at a regular size class, which an iPad sheet never reported.
                if sizeClass == .regular || proxy.size.width >= 600 {
                    HStack(spacing: 0) {
                        catalogColumn.frame(width: min(340, proxy.size.width * 0.42))
                        Divider()
                        editorColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                } else {
                    VStack(spacing: 0) {
                        editorColumn
                        Divider()
                        catalogColumn
                    }
                }
            }
            .navigationTitle(isEditing ? CatalogStrings.editFormula : EditorStrings.insertFormula)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EditorStrings.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? CatalogStrings.done : EditorStrings.insert) { confirm() }
                        .bold()
                        .disabled(!validator.canConfirm(expression))
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("formulaConfirm")
                }
            }
        }
        .accessibilityIdentifier("formulaEditor")
        .presentationDetents([.large])
        // iPad: a page-sized sheet, wide enough for the catalog beside the code (W4).
        .presentationSizing(.page)
        .onAppear {
            code.load(FormulaHighlighter.pretty(initialExpression), selectAll: isEditing)
            validator.update(expression)
        }
        .onChange(of: code.text) { _, _ in validator.update(expression) }
    }

    private func confirm() {
        guard validator.canConfirm(expression), let source = TemplateInsertion.formula(confirmedExpression) else { return }
        onConfirm(source)
        dismiss()
    }

    // MARK: Editor

    private var statusColor: Color {
        switch validator.status {
        case .valid: return .green
        case .invalid: return .red
        default: return Color(uiColor: .separator)
        }
    }

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMULA").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack {
                    Text("{{=").font(.callout.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    statusIcon
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground))
                Divider().overlay(statusColor.opacity(0.5))
                FormulaCodeView(controller: code)
                    .frame(minHeight: 96, idealHeight: 140, maxHeight: sizeClass == .regular ? .infinity : 180)
                Divider().overlay(statusColor.opacity(0.5))
                HStack {
                    Text("}}").font(.callout.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(statusColor, lineWidth: validator.status == .idle || validator.status == .validating ? 1 : 2))
            messages
        }
        .padding(12)
    }

    @ViewBuilder private var statusIcon: some View {
        Group {
            switch validator.status {
            case .idle: Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            case .validating: ProgressView().controlSize(.small)
            case .valid: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(statusLabel)
        .accessibilityValue(validator.status.label)
        .accessibilityIdentifier("formulaStatus")
    }

    private var statusLabel: String {
        switch validator.status {
        case .idle: return "Not checked"
        case .validating: return CatalogStrings.formulaChecking
        case .valid: return CatalogStrings.formulaValid
        case .invalid(let messages): return messages.joined(separator: "; ")
        }
    }

    @ViewBuilder private var messages: some View {
        switch validator.status {
        case .invalid(let lines):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("formulaErrors")
        case .valid:
            Label(CatalogStrings.formulaValid, systemImage: "checkmark").font(.footnote).foregroundStyle(.green)
        default:
            Text(CatalogStrings.formulaHint).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Catalog column

    private var catalogColumn: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(CatalogStrings.functions).tag(Tab.functions)
                Text(EditorStrings.variables).tag(Tab.variables)
            }
            .pickerStyle(.segmented).padding(10)
            .accessibilityIdentifier("formulaTabs")
            switch tab {
            case .functions: functionList
            case .variables:
                VariablePickerView(catalog: store.catalog, usesSample: store.usesSample, autoFocusSearch: false) { path in
                    code.insert(path)
                }
            }
        }
    }

    private var functionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                ForEach(store.functions.categories) { category in
                    let accent = Self.accent(category.name)
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            if collapsed.contains(category.name) { collapsed.remove(category.name) } else { collapsed.insert(category.name) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: Self.icon(category.name)).font(.caption.weight(.semibold))
                                Text(FunctionCatalog.title(category.name)).font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: collapsed.contains(category.name) ? "chevron.right" : "chevron.down").font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color(uiColor: .secondarySystemBackground))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("formulaCategory_\(category.name)")
                        if !collapsed.contains(category.name) {
                            ForEach(category.functions) { function in
                                Button { code.scaffold(function.name) } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(function.name).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(.primary)
                                            Text(function.signature).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        if !function.summary.isEmpty {
                                            Text(function.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(function.name), \(function.signature). \(function.summary)")
                                .accessibilityIdentifier("formulaFunction_\(function.name)")
                            }
                        }
                    }
                    .overlay(alignment: .leading) { Rectangle().fill(accent.opacity(0.6)).frame(width: 2) }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
    }

    /// Category accents (web `CATEGORY_META`): violet, orange, teal, emerald, sky, amber, pink.
    static func accent(_ category: String) -> Color {
        switch category {
        case "logic": return Color(red: 0.65, green: 0.55, blue: 0.98)
        case "array": return Color(red: 0.98, green: 0.57, blue: 0.24)
        case "date": return Color(red: 0.18, green: 0.83, blue: 0.75)
        case "math": return Color(red: 0.20, green: 0.83, blue: 0.60)
        case "text": return Color(red: 0.22, green: 0.74, blue: 0.97)
        case "convert": return Color(red: 0.98, green: 0.75, blue: 0.14)
        case "color": return Color(red: 0.96, green: 0.45, blue: 0.71)
        default: return .secondary
        }
    }
    static func icon(_ category: String) -> String {
        switch category {
        case "logic": return "arrow.triangle.branch"
        case "array": return "list.bullet"
        case "date": return "calendar.badge.clock"
        case "math": return "number"
        case "text": return "textformat"
        case "convert": return "arrow.left.arrow.right"
        case "color": return "paintpalette"
        default: return "questionmark.square.dashed"
        }
    }
}

/// The code box's text and caret, shared between the SwiftUI sheet and its `UITextView`.
@MainActor final class FormulaCodeController: ObservableObject {
    @Published var text = ""
    fileprivate weak var view: UITextView?
    fileprivate var pendingSelection: NSRange?

    func load(_ text: String, selectAll: Bool) {
        self.text = text
        pendingSelection = selectAll ? NSRange(location: 0, length: (text as NSString).length) : NSRange(location: (text as NSString).length, length: 0)
        if let view { FormulaCodeView.apply(text, to: view, selection: pendingSelection) }
    }
    /// A function row: the whole expression becomes `NAME(` / `)` with the caret inside (web).
    func scaffold(_ name: String) {
        let scaffold = FormulaHighlighter.scaffold(name)
        text = scaffold.text
        pendingSelection = NSRange(location: scaffold.caret, length: 0)
        if let view { FormulaCodeView.apply(text, to: view, selection: pendingSelection); view.becomeFirstResponder() }
    }
    /// A variable pill: the bare path at the caret.
    func insert(_ token: String) {
        guard let view else { text += token; return }
        let selection = view.selectedRange
        let updated = (view.text as NSString).replacingCharacters(in: selection, with: token)
        text = updated
        let caret = NSRange(location: selection.location + (token as NSString).length, length: 0)
        FormulaCodeView.apply(updated, to: view, selection: caret)
        view.becomeFirstResponder()
    }
}

/// Monospace code view coloured by `FormulaHighlighter` (TextKit; no smart quotes, no
/// autocorrection: a curly quote would break a string literal).
struct FormulaCodeView: UIViewRepresentable {
    @ObservedObject var controller: FormulaCodeController

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.inlinePredictionType = .no
        // iPad: no shortcuts bar over the code (Cancel/Insert carry the actions).
        view.inputAssistantItem.leadingBarButtonGroups = []
        view.inputAssistantItem.trailingBarButtonGroups = []
        view.backgroundColor = .systemBackground
        view.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityIdentifier = "formulaExpression"
        view.accessibilityLabel = "Formula expression"
        controller.view = view
        Self.apply(controller.text, to: view, selection: controller.pendingSelection)
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != controller.text { Self.apply(controller.text, to: view, selection: controller.pendingSelection) }
    }

    static var font: UIFont { UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular)) }

    static func color(_ kind: FormulaHighlighter.Kind) -> UIColor {
        switch kind {
        case .function: return UIColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1)   // #8b5cf6
        case .string: return UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1)     // #16a34a
        case .number: return UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 1)     // #ea580c
        case .variable: return UIColor(red: 0.008, green: 0.518, blue: 0.780, alpha: 1)   // #0284c7
        case .operator, .punctuation: return .secondaryLabel
        }
    }

    static func attributed(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
        for token in FormulaHighlighter.tokens(text) {
            result.addAttribute(.foregroundColor, value: color(token.kind), range: token.range)
            if token.kind == .function {
                result.addAttribute(.font, value: UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .semibold)), range: token.range)
            }
        }
        return result
    }

    static func apply(_ text: String, to view: UITextView, selection: NSRange?) {
        let keep = selection ?? view.selectedRange
        view.attributedText = attributed(text)
        view.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
        let length = (text as NSString).length
        let location = min(keep.location, length)
        view.selectedRange = NSRange(location: location, length: min(keep.length, length - location))
        view.accessibilityValue = text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: FormulaCodeController
        init(_ controller: FormulaCodeController) { self.controller = controller }
        func textViewDidChange(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let selection = view.selectedRange
            // Recolour in place, keeping the caret.
            FormulaCodeView.apply(view.text, to: view, selection: selection)
            controller.pendingSelection = nil
            if controller.text != view.text { controller.text = view.text }
        }
    }
}
