import SwiftUI
import FiestaBoardDocuments
import FiestaBoardEditorState

/// Toolbar and keyboard-accessory actions on the document (PLAN B15/B17). One set of actions,
/// shared by the visible toolbar under the title and the keyboard accessory that mirrors it.
@MainActor struct DocumentCommands {
    let model: LocalPageEditorModel
    let buffer: DocumentBuffer
    let pipeline: PreviewPipeline

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
        if row >= (model.lines?.count ?? 0) { model.commitRows(buffer.rows); buffer.markCommitted() }
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
    func redo() { commitNow(); model.redo(); commitNow() }
}

/// The visible document toolbar, placed directly under the page title (PLAN B12/B15).
struct DocumentToolbar: View {
    @ObservedObject var model: LocalPageEditorModel
    @ObservedObject var buffer: DocumentBuffer
    var pipeline: PreviewPipeline
    @Binding var rich: Bool

    var body: some View {
        let commands = DocumentCommands(model: model, buffer: buffer, pipeline: pipeline)
        EditorToolbar(alignment: commands.alignment, wrap: commands.wrap,
                      canUndo: commands.canUndo, canRedo: commands.canRedo, enabled: commands.enabled, rich: rich,
                      onUndo: commands.undo, onRedo: commands.redo, onAlign: commands.align, onWrap: commands.setWrap,
                      onRich: { value in commands.commitNow(); rich = value })
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
    @State private var tokenEditing: TokenEditing?

    private var geometry: TemplateGeometry? { model.authoringGeometry }
    var boardRows: Int { geometry?.rows ?? 6 }
    private var uppercase: Bool { !(geometry?.isPanel ?? false) }

    /// The session's rows padded for display to the board's rows (never stored by itself).
    static func displayRows(_ lines: [String], boardRows: Int) -> [String] {
        lines.count >= boardRows ? lines : lines + Array(repeating: "", count: boardRows - lines.count)
    }
    /// Natural height of the document for `rows` rows (text container insets included).
    static func documentHeight(rows: Int) -> CGFloat {
        (CGFloat(rows) * BoardDocumentView.Coordinator.font.lineHeight + 30).rounded(.up)
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
        let commands = DocumentCommands(model: model, buffer: buffer, pipeline: pipeline)
        VStack(alignment: .leading, spacing: 6) {
            BoardDocumentView(buffer: buffer, sessionRows: Self.displayRows(model.lines ?? [], boardRows: boardRows),
                              boardRows: boardRows, rich: rich, uppercase: uppercase, editable: !model.editingFrozen,
                              onEdited: { pipeline.edited() }, onCommitNow: { commands.commitNow() },
                              onFocusChange: { isTextInputActive = $0 },
                              accessory: .init(alignment: commands.alignment, wrap: commands.wrap,
                                               canUndo: commands.canUndo, canRedo: commands.canRedo, enabled: commands.enabled),
                              onUndo: commands.undo, onRedo: commands.redo, onAlign: commands.align, onWrap: commands.setWrap,
                              onEditToken: { source, range in commands.commitNow(); tokenEditing = TokenEditing(source: source, selection: range) })
                // Hugs its rows (B33: the board stays the largest element); scrolls when capped.
                .frame(minHeight: 80, idealHeight: Self.documentHeight(rows: max(rows.count, boardRows)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(overflow ? Color.orange : Color(uiColor: .separator), lineWidth: overflow ? 2 : 0.5))
            HStack(alignment: .firstTextBaseline) {
                Text(EditorStrings.lineCounter(count, limit: boardRows))
                    .font(.caption.monospacedDigit()).foregroundStyle(overflow ? .orange : .secondary)
                    .accessibilityIdentifier("lineCounter")
                Spacer()
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
        .sheet(item: $tokenEditing) { draft in
            TemplateTokenSheet(initialSource: draft.source) { source in
                buffer.replace(sourceRange: draft.selection, with: source, rich: rich)
                tokenEditing = nil
            }
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
