import SwiftUI
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit

/// Toolbar and keyboard-accessory actions on the document (PLAN B15/B17). One set of actions,
/// shared by the visible toolbar under the title and the keyboard accessory that mirrors it.
@MainActor struct DocumentCommands {
    let model: LocalPageEditorModel
    let buffer: DocumentBuffer
    let pipeline: PreviewPipeline
    /// The server's catalogs (iOS-F1); nil falls back to the built-in sample.
    var catalog: EditorCatalogStore? = nil

    var alignment: String { model.lineAlignment(buffer.caretRow) }
    var wrap: Bool { model.lineWrap(buffer.caretRow) }
    var canUndo: Bool { model.canUndo || buffer.isDirty }
    var canRedo: Bool { model.canRedo && !buffer.isDirty }
    var enabled: Bool { !model.editingFrozen }

    /// Commit typing to the session now (blur, toolbar, undo) and refresh the stage.
    func commitNow() { pipeline.flush() }

    /// Toolbar actions on a row the session doesn't store yet (a new page's display padding)
    /// first store the visible rows.
    private func ensureRowStored(_ row: Int) {
        guard row >= (model.lines?.count ?? 0) else { return }
        if buffer.plainMode { model.commitPlainRows(buffer.rows) } else { model.commitRows(buffer.rows) }
        buffer.markCommitted()
    }
    private func selectedRows() -> [Int] { Array(buffer.caretRows).filter { $0 < max(buffer.rows.count, 1) } }
    func align(_ alignment: String) {
        commitNow()
        for row in selectedRows() { ensureRowStored(row); model.setLineAlignment(row, alignment: alignment) }
        commitNow()
    }
    func setWrap(_ wrap: Bool) {
        commitNow()
        for row in selectedRows() { ensureRowStored(row); model.setLineWrap(row, wrap: wrap) }
        commitNow()
    }
    func undo() { commitNow(); model.undo(); commitNow() }
    /// Inserts template source at the caret as typing (chips appear at once; one undo step).
    func insert(_ source: String) {
        guard enabled else { return }
        buffer.focus()
        buffer.insert(source)
    }
    func insertFormula() { guard enabled else { return }; commitNow(); buffer.requestFormula() }
    /// Variables / Colors / Formatting: a searchable picker in a sheet (iOS-F1, B22).
    func openPicker(_ kind: InsertPickerKind) { guard enabled else { return }; commitNow(); buffer.requestPicker(kind) }
    /// The variables the pickers offer and the chips check: the server's `GET /v1/variables`
    /// (authoritative), else the built-in sample, which may only warn about unknown variables in
    /// the demo (whose variables it is).
    var variables: VariableCatalog { catalog?.variables ?? .sample(authoritative: model.isSimulated) }
    var pickers: InsertPickers {
        InsertPickers(variables: variables, onInsert: insert, onFormula: insertFormula, onPicker: openPicker,
                      variablesEnabled: catalog?.variablesAvailable ?? true,
                      colorsShown: catalog?.colorsAvailable ?? true, formattingShown: catalog?.formattingAvailable ?? true)
    }
    func redo() { commitNow(); model.redo(); commitNow() }
}

/// The visible document toolbar, placed directly under the page title (PLAN B12/B15).
struct DocumentToolbar: View {
    @ObservedObject var model: LocalPageEditorModel
    @ObservedObject var buffer: DocumentBuffer
    var pipeline: PreviewPipeline
    @Binding var rich: Bool
    @EnvironmentObject private var catalog: EditorCatalogStore
    /// Draw on board (iOS-F1) slots in before the insert buttons.
    var slots: AnyView? = nil

    var body: some View {
        let commands = DocumentCommands(model: model, buffer: buffer, pipeline: pipeline, catalog: catalog)
        EditorToolbar(alignment: commands.alignment, wrap: commands.wrap,
                      canUndo: commands.canUndo, canRedo: commands.canRedo, enabled: commands.enabled,
                      pickers: commands.pickers,
                      onUndo: commands.undo, onRedo: commands.redo, onAlign: commands.align, onWrap: commands.setWrap,
                      slots: slots)
    }
}

/// The document column of a legacy template page (PLAN B12/B16): one continuous board-shaped
/// document, line counter and the overflow warning. No per-row controls. The toolbar sits under
/// the title (`DocumentToolbar`); the keyboard accessory mirrors it.
struct TemplateWorkspaceView: View {
    @ObservedObject var model: LocalPageEditorModel
    @ObservedObject var buffer: DocumentBuffer
    var pipeline: PreviewPipeline
    @Binding var isTextInputActive: Bool
    @Binding var rich: Bool
    /// Draw on board, when the page can be drawn on (W4: also offered on the keyboard accessory).
    var onDraw: (() -> Void)? = nil
    /// The chosen display's `charset_issues` from the last render (B16, W4): lowercase on a flap
    /// board, or a character it lacks, is listed, never silently changed in the document.
    var charsetIssues: [TemplateCharsetIssue] = []
    /// iPad portrait with the keyboard down (P5): the document takes the height under the board
    /// and its rows spread to fill it.
    var fillsHeight = false
    var maximumDocumentHeight: CGFloat? = nil
    @State private var tokenEditing: TokenEditing?
    @EnvironmentObject private var catalog: EditorCatalogStore

    private var geometry: TemplateGeometry? { model.authoringGeometry }
    var boardRows: Int { geometry?.rows ?? 6 }
    var boardColumns: Int { geometry?.columns ?? 22 }
    private var uppercase: Bool { !(geometry?.isPanel ?? false) }

    /// The session's rows padded for display to the board's rows (never stored by itself).
    static func displayRows(_ lines: [String], boardRows: Int) -> [String] {
        lines.count >= boardRows ? lines : lines + Array(repeating: "", count: boardRows - lines.count)
    }
    /// Natural height of the document for `rows` rows (text container insets included).
    static func documentHeight(rows: Int) -> CGFloat {
        (CGFloat(rows) * BoardDocumentView.Coordinator.font.lineHeight + 30).rounded(.up)
    }
    /// Natural width of the document column for a board `columns` wide (gutter, insets, margin).
    static func documentWidth(columns: Int) -> CGFloat {
        let advance = ("M" as NSString).size(withAttributes: [.font: BoardDocumentView.Coordinator.font]).width
        return (CGFloat(columns) * advance + RowGutterView.width + 48).rounded(.up)
    }
    /// `1 / 6 lines` counts up to the last row with content; beyond the board, every row.
    static func lineCount(_ rows: [String], boardRows: Int) -> Int {
        if rows.count > boardRows { return rows.count }
        return max(1, (rows.lastIndex(where: { !$0.isEmpty }) ?? 0) + 1)
    }

    var body: some View {
        let rows = buffer.rows
        let count = Self.lineCount(rows, boardRows: boardRows)
        let overflow = count > boardRows
        let commands = DocumentCommands(model: model, buffer: buffer, pipeline: pipeline, catalog: catalog)
        VStack(alignment: .leading, spacing: 6) {
            BoardDocumentView(buffer: buffer, sessionRows: Self.displayRows((rich ? model.lines : model.plainLines) ?? [], boardRows: boardRows),
                              boardRows: boardRows, rich: rich, uppercase: uppercase, editable: !model.editingFrozen,
                              onEdited: { pipeline.edited() }, onCommitNow: { commands.commitNow() },
                              onFocusChange: { isTextInputActive = $0 },
                              accessory: .init(alignment: commands.alignment, wrap: commands.wrap,
                                               canUndo: commands.canUndo, canRedo: commands.canRedo, enabled: commands.enabled,
                                               variablesEnabled: catalog.variablesAvailable,
                                               colorsShown: catalog.colorsAvailable, formattingShown: catalog.formattingAvailable,
                                               drawShown: onDraw != nil),
                              onUndo: commands.undo, onRedo: commands.redo, onAlign: commands.align, onWrap: commands.setWrap,
                              onEditToken: { source, range in editToken(source, range, commands) },
                              variables: commands.variables, boardColumns: boardColumns,
                              onInsert: commands.insert, onFormula: commands.insertFormula, onPicker: commands.openPicker,
                              onDraw: { onDraw?() }, fillsRows: fillsHeight)
                // Hugs its rows (B33: the board stays the largest element); scrolls when capped.
                .frame(minHeight: 80, idealHeight: Self.documentHeight(rows: max(rows.count, boardRows)),
                       maxHeight: fillsHeight ? maximumDocumentHeight : nil)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(overflow ? Color.orange : Color(uiColor: .separator), lineWidth: overflow ? 2 : 0.5))
            if fillsHeight { Spacer(minLength: 0) }
            if rich {
                // The chip at the caret, in full (compact chips show only a short name; AND-P1).
                // W4: its line is always reserved, so moving the caret over chips never nudges
                // the layout; one line, truncated in the middle (the callout has the rest).
                let detail = buffer.chipDetail
                Text(detail ?? " ")
                    .font(.footnote.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(detail == nil ? 0 : 1)
                    .accessibilityHidden(detail == nil)
                    .accessibilityIdentifier(detail == nil ? "" : "chip-detail")
            }
            HStack(alignment: .center) {
                Text(EditorStrings.lineCounter(count, limit: boardRows))
                    .font(.caption.monospacedDigit()).foregroundStyle(overflow ? .orange : .secondary)
                    .accessibilityIdentifier("lineCounter")
                Spacer()
                Picker(EditorStrings.editingMode, selection: Binding(get: { rich }, set: { value in commands.commitNow(); rich = value })) {
                    Text(EditorStrings.rich).tag(true); Text(EditorStrings.plain).tag(false)
                }
                .pickerStyle(.segmented).frame(maxWidth: 128).controlSize(.small)
                .disabled(!commands.enabled)
                .accessibilityIdentifier("editingMode")
            }
            if !rich {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(EditorStrings.plainHelp, id: \.self) { line in
                        Text("• " + line).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("plainHelp")
            }
            ForEach(Array(unknownVariables(rows, commands.variables).prefix(3).enumerated()), id: \.offset) { _, issue in
                Label { Text(issue) } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("unknownVariableIssue")
            }
            if !charsetIssues.isEmpty {
                CharsetIssueList(lines: EditorStrings.charsetIssueGroups(charsetIssues))
            }
            if rich, catalog.isLoaded, !catalog.variablesAvailable {
                // B32: no plugins on this server.
                Label(CatalogStrings.noVariables, systemImage: "puzzlepiece.extension")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CatalogStrings.noVariables)
                    .accessibilityIdentifier("noVariablesNote")
            }
            if overflow {
                Label(EditorStrings.overflowWarning(limit: boardRows), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("rowOverflowWarning")
            }
        }
        .sheet(item: $buffer.formulaRequest, onDismiss: { buffer.focus() }) { request in
            // iOS-F1 (B21): catalogs, colouring and live validation.
            FormulaEditorSheet(store: catalog, initialExpression: request.expression, isEditing: request.replacing != nil) { source in
                if let range = request.replacing { buffer.replace(sourceRange: range, with: source, rich: rich) }
                else { buffer.insertAfterSheet(source) }
            }
        }
        .sheet(item: $buffer.pickerRequest, onDismiss: { buffer.focus() }) { kind in
            InsertPickerSheet(kind: kind, store: catalog, drawsHeart: geometry.map { $0.rows == 3 && $0.columns == 15 } ?? false) { source in
                buffer.insertAfterSheet(source)
            }
        }
        .sheet(item: $tokenEditing) { draft in
            TemplateTokenSheet(initialSource: draft.source, warning: draft.warning) { source in
                buffer.replace(sourceRange: draft.selection, with: source, rich: rich)
                tokenEditing = nil
            }
        }
    }

    /// A second tap on a chip opens it: formulas in the formula sheet, everything else in the
    /// token editor (with the unknown-variable reason when there is one).
    private func editToken(_ source: String, _ range: NSRange, _ commands: DocumentCommands) {
        commands.commitNow()
        let fragment = TemplateSyntax.fragments(source).first
        if fragment?.kind == .formula {
            var expression = String(source.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            if expression.hasPrefix("=") { expression = String(expression.dropFirst()).trimmingCharacters(in: .whitespaces) }
            buffer.requestFormula(editing: range, expression: expression)
            return
        }
        var warning: String?
        if let fragment, case .unknownVariable(let reason)? = TemplateChip(fragment: fragment, variables: commands.variables)?.style { warning = reason }
        tokenEditing = TokenEditing(source: source, selection: range, warning: warning)
    }

    /// "Row 2 · bogus.thing: “bogus” isn't a plugin… The board shows ??? here." (first three).
    private func unknownVariables(_ rows: [String], _ variables: VariableCatalog) -> [String] {
        guard variables.isAuthoritative, rich else { return [] }
        var issues: [String] = []
        for (index, row) in rows.enumerated() {
            for fragment in TemplateSyntax.fragments(row) where fragment.kind == .expression {
                if let chip = TemplateChip(fragment: fragment, variables: variables), case .unknownVariable(let reason) = chip.style {
                    issues.append(EditorStrings.unknownVariableIssue(row: index + 1, name: chip.title, reason: reason))
                }
            }
        }
        return issues
    }
}

private struct TokenEditing: Identifiable {
    let id = UUID()
    let source: String
    let selection: NSRange
    var warning: String?
}
private struct TemplateTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    var warning: String?
    var onApply: (String) -> Void
    init(initialSource: String, warning: String? = nil, onApply: @escaping (String) -> Void) {
        _source = State(initialValue: initialSource); self.warning = warning; self.onApply = onApply
    }
    var body: some View {
        NavigationStack {
            Form {
                if let warning {
                    Section {
                        Label { Text(warning) } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                            .accessibilityIdentifier("tokenWarning")
                    }
                }
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

/// B16 charset issues, grouped per row and reason (P5). Collapsed it is at most three lines, one
/// per group, so the list never grows into the board's room; "Show all" opens the rest in place
/// (scrolling past about eight lines).
struct CharsetIssueList: View {
    var lines: [String]
    static let collapsedCount = 3
    @State private var expanded = false
    @State private var width: CGFloat = 0
    @State private var widest: CGFloat = 0

    /// More groups than fit, or a group that doesn't fit on its one line.
    private var hasMore: Bool { lines.count > Self.collapsedCount || widest > width + 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if expanded {
                    ScrollView { entries(lines, oneLine: false) }
                        .frame(maxHeight: 150)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    entries(Array(lines.prefix(Self.collapsedCount)), oneLine: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((expanded ? lines : Array(lines.prefix(Self.collapsedCount))).joined(separator: "\n"))
            .accessibilityIdentifier("charsetIssues")
            if hasMore || expanded {
                Button(expanded ? EditorStrings.showFewerIssues : EditorStrings.showAllIssues + " (\(lines.count))") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("charsetIssuesShowAll")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // Each group's one-line width, measured off-screen, tells whether a line is cut.
        .background(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.prefix(Self.collapsedCount).enumerated()), id: \.offset) { _, line in row(line).fixedSize() }
            }
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { widest = $0 }
        }
    }

    private func entries(_ shown: [String], oneLine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                row(line).lineLimit(oneLine ? 1 : nil).truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ line: String) -> some View {
        Label { Text(line) } icon: { Image(systemName: "character.cursor.ibeam").foregroundStyle(.orange) }
            .font(.footnote)
    }
}
