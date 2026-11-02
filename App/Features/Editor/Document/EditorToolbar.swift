import SwiftUI

/// The document toolbar under the title (PLAN B15): Variables · Colors · Formatting · Insert
/// formula, then Undo · Redo, Align left/center/right and Wrap, all icon-only with long-press
/// labels, reflecting the caret row. The keyboard accessory mirrors it (`BoardDocumentView`).
/// Draw on board (iOS-F1) and Sync from board slot in through `slots`. Rich | Plain sits under
/// the document, beside the line counter, so the toolbar fits one row on a phone.
struct EditorToolbar: View {
    var alignment: String
    var wrap: Bool
    var canUndo: Bool
    var canRedo: Bool
    var enabled: Bool
    var pickers: InsertPickers
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onAlign: (String) -> Void
    var onWrap: (Bool) -> Void
    /// Wave-3 buttons (Draw on board, Sync from board).
    var slots: AnyView? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
        .disabled(!enabled)
        .padding(.vertical, 2)
    }

    private var row: some View {
        HStack(spacing: 2) {
            if let slots { slots; divider }
            menu(EditorStrings.variables, "curlybraces", id: "toolbar_variables") { pickers.variablesMenu }
            menu(EditorStrings.colors, "paintpalette", id: "toolbar_colors") { pickers.colorsMenu }
            menu(EditorStrings.formatting, "textformat", id: "toolbar_formatting") { pickers.formattingMenu }
            button(EditorStrings.insertFormula, "function", id: "toolbar_formula") { pickers.onFormula() }
            divider
            button(EditorStrings.undo, "arrow.uturn.backward", id: "toolbar_undo", disabled: !canUndo) { onUndo() }
            button(EditorStrings.redo, "arrow.uturn.forward", id: "toolbar_redo", disabled: !canRedo) { onRedo() }
            divider
            button(EditorStrings.alignLeft, "text.alignleft", id: "toolbar_alignLeft", selected: alignment == "left") { onAlign("left") }
            button(EditorStrings.alignCenter, "text.aligncenter", id: "toolbar_alignCenter", selected: alignment == "center") { onAlign("center") }
            button(EditorStrings.alignRight, "text.alignright", id: "toolbar_alignRight", selected: alignment == "right") { onAlign("right") }
            button(EditorStrings.wrap, "text.word.spacing", id: "toolbar_wrap", selected: wrap) { onWrap(!wrap) }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var divider: some View { Divider().frame(height: 20).padding(.horizontal, 3) }

    private func icon(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .frame(width: 34, height: 32)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }

    private func menu<Content: View>(_ title: String, _ symbol: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { icon(symbol, selected: false) }
            .menuStyle(.button).buttonStyle(.borderless)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
    }

    private func button(_ title: String, _ symbol: String, id: String, selected: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol, selected: selected) }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .help(title)
            .contextMenu { Text(title) }
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(id)
    }
}
