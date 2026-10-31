import SwiftUI

/// The document toolbar (PLAN B15). D1 ships Undo · Redo · Align left/center/right · Wrap,
/// reflecting the caret row; the slots for Draw on board, Variables, Colors, Formatting,
/// Insert formula and Sync from board are reserved here for waves 2/3 (`slots`).
struct EditorToolbar: View {
    var alignment: String
    var wrap: Bool
    var canUndo: Bool
    var canRedo: Bool
    var enabled: Bool
    var rich: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onAlign: (String) -> Void
    var onWrap: (Bool) -> Void
    var onRich: (Bool) -> Void
    /// Wave-2/3 buttons (Draw on board, Variables, Colors, Formatting, Insert formula, Sync).
    var slots: AnyView? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let slots { slots }
            button(EditorStrings.undo, "arrow.uturn.backward", id: "toolbar_undo", disabled: !canUndo) { onUndo() }
            button(EditorStrings.redo, "arrow.uturn.forward", id: "toolbar_redo", disabled: !canRedo) { onRedo() }
            divider
            button(EditorStrings.alignLeft, "text.alignleft", id: "toolbar_alignLeft", selected: alignment == "left") { onAlign("left") }
            button(EditorStrings.alignCenter, "text.aligncenter", id: "toolbar_alignCenter", selected: alignment == "center") { onAlign("center") }
            button(EditorStrings.alignRight, "text.alignright", id: "toolbar_alignRight", selected: alignment == "right") { onAlign("right") }
            divider
            button(EditorStrings.wrap, "text.word.spacing", id: "toolbar_wrap", selected: wrap) { onWrap(!wrap) }
            Spacer(minLength: 4)
            Picker(EditorStrings.rich, selection: Binding(get: { rich }, set: { onRich($0) })) {
                Text(EditorStrings.rich).tag(true); Text(EditorStrings.plain).tag(false)
            }
            .pickerStyle(.segmented).frame(maxWidth: 124)
            .accessibilityIdentifier("editingMode")
        }
        .disabled(!enabled)
        .padding(.vertical, 4)
    }

    private var divider: some View { Divider().frame(height: 20).padding(.horizontal, 2) }

    private func button(_ title: String, _ symbol: String, id: String, selected: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 34, height: 30)
                .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(title)
        .contextMenu { Text(title) }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
