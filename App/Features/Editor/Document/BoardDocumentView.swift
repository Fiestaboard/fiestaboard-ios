import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState

/// The editor surface's live state (PLAN §3.2 "DocumentRows"). Typing lives here, in the text
/// view's own buffer, until the pipeline commits it to the session on idle/blur/toolbar/undo.
@MainActor final class DocumentBuffer: ObservableObject {
    /// Source rows as the user currently sees them (display-padded to the board's rows).
    @Published private(set) var rows: [String] = []
    /// Rows touched by the caret or selection.
    @Published private(set) var caretRows: ClosedRange<Int> = 0...0
    /// Plain mode: rows carry `{wrap}`/alignment prefixes and commit through `commitPlainRows`.
    var plainMode = false
    /// The buffer has typing the session has not seen yet.
    private(set) var isDirty = false
    /// Source last pushed from the session; the session wins only when it changes on its own.
    fileprivate var syncedSource: String?
    fileprivate weak var textView: TemplateUITextView?

    /// The full source of the chip just before the caret, or the first chip in the selection
    /// (`weather.temperature | pad:3`, a formula in full, the ??? reason): the detail line under
    /// the document (`chip-detail`, shared with AND-P1).
    @Published private(set) var chipDetail: String?
    fileprivate func setChipDetail(_ detail: String?) {
        guard detail != chipDetail else { return }
        // Selection callbacks can arrive inside a SwiftUI update; publish on the next turn.
        DispatchQueue.main.async { [weak self] in if self?.chipDetail != detail { self?.chipDetail = detail } }
    }

    var caretRow: Int { caretRows.lowerBound }
    var source: String { rows.joined(separator: "\n") }

    fileprivate func adopt(rows: [String], caret: ClosedRange<Int>, dirty: Bool) {
        if self.rows != rows { self.rows = rows }
        if caretRows != caret { caretRows = caret }
        if dirty { isDirty = true }
    }
    /// The pipeline committed the buffer: the session now equals it.
    func markCommitted() { isDirty = false; syncedSource = source }

    /// Insert source at the caret (replacing the selection), as one edit of the buffer.
    func insert(_ source: String) {
        guard let textView, textView.isEditable else { return }
        textView.insertTemplate(source)
    }
    func resignFocus() { textView?.resignFirstResponder() }
    /// Put the caret back in the document (after a picker or sheet closes).
    func focus() { if let textView, textView.isEditable, !textView.isFirstResponder { textView.becomeFirstResponder() } }
    /// Insert formula was tapped; the workspace presents the formula sheet (iOS-F1 seam).
    @Published var formulaRequest: FormulaRequest?
    /// Variables, Colors or Formatting was tapped; the workspace presents that picker (iOS-F1).
    @Published var pickerRequest: InsertPickerKind?
    func requestPicker(_ kind: InsertPickerKind) {
        savedSelection = textView?.selectedRange
        pickerRequest = kind
    }
    /// Source selection to restore when the formula sheet inserts (the text view loses focus).
    fileprivate(set) var savedSelection: NSRange?
    func requestFormula(editing: NSRange? = nil, expression: String = "") {
        savedSelection = textView?.selectedRange
        formulaRequest = FormulaRequest(replacing: editing, expression: expression)
    }
    /// Insert at the selection saved when the sheet opened, then refocus.
    func insertAfterSheet(_ source: String) {
        guard let textView else { return }
        if let saved = savedSelection, NSMaxRange(saved) <= textView.attributedText.length { textView.selectedRange = saved }
        savedSelection = nil
        focus()
        insert(source)
    }
    /// Replace a source range (e.g. a tapped chip) and treat it as typing.
    func replace(sourceRange: NSRange, with replacement: String, rich: Bool) {
        guard let textView, textView.markedTextRange == nil else { return }
        let source = textView.templateSource as NSString
        guard NSMaxRange(sourceRange) <= source.length else { return }
        let updated = source.replacingCharacters(in: sourceRange, with: replacement)
        let caret = NSRange(location: sourceRange.location + (replacement as NSString).length, length: 0)
        textView.setTemplate(updated, rich: rich, font: BoardDocumentView.Coordinator.font, sourceSelection: caret)
        textView.delegate?.textViewDidChange?(textView)
    }
    var isFocused: Bool { textView?.isFirstResponder ?? false }
}

/// Insert formula / edit a formula pill (iOS-F1 replaces the sheet that answers it).
struct FormulaRequest: Identifiable {
    let id = UUID()
    /// Source range of the pill being edited, nil for a new formula.
    let replacing: NSRange?
    let expression: String
}

/// One continuous editable surface for the whole page: rows are paragraphs of a single
/// TextKit 1 `TemplateUITextView` (PLAN B12, §3.2). Return inserts a row, Backspace at a row's
/// start joins it to the previous one; there is no per-row chrome.
struct BoardDocumentView: UIViewRepresentable {
    struct AccessoryState: Equatable {
        var alignment: String
        var wrap: Bool
        var canUndo: Bool
        var canRedo: Bool
        var enabled: Bool
        /// iOS-F1 (B32): Variables off when the server has none; Colors/Formatting only when listed.
        var variablesEnabled = true
        var colorsShown = true
        var formattingShown = true
        /// W4: Draw on board from the keyboard too (split-flap pages with a cell stage only).
        var drawShown = false
    }
    @ObservedObject var buffer: DocumentBuffer
    /// The session's rows, padded for display to the board's rows.
    var sessionRows: [String]
    var boardRows: Int
    var rich: Bool
    var uppercase: Bool
    var editable: Bool
    var onEdited: () -> Void
    var onCommitNow: () -> Void
    var onFocusChange: (Bool) -> Void
    /// State the keyboard accessory mirrors from the toolbar (caret row's alignment and wrap).
    var accessory: AccessoryState
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onAlign: (String) -> Void
    var onWrap: (Bool) -> Void
    var onEditToken: (String, NSRange) -> Void
    /// Variables known to the server (unknown-variable warning) and offered by the insert menus.
    var variables: VariableCatalog
    var boardColumns: Int = 22
    var onInsert: (String) -> Void = { _ in }
    var onFormula: () -> Void = {}
    /// Opens the Variables / Colors / Formatting picker (iOS-F1).
    var onPicker: (InsertPickerKind) -> Void = { _ in }
    /// Draw on board (W4: reachable from the keyboard accessory, like the toolbar's pencil).
    var onDraw: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BoardDocumentContainer {
        let container = BoardDocumentContainer()
        buffer.plainMode = !rich
        container.boardColumns = boardColumns
        container.dimsOverflow = rich
        let view = container.textView
        view.delegate = context.coordinator
        view.allowsMultiline = true
        view.usesDocumentUndo = true
        view.managesOwnScrolling = false
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 10, left: 4, bottom: 16, right: 8)
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.inlinePredictionType = .no
        view.accessibilityIdentifier = "boardDocument"
        view.accessibilityLabel = "Board document"
        view.onUndo = { [weak coordinator = context.coordinator] in coordinator?.parent.onUndo() }
        view.onRedo = { [weak coordinator = context.coordinator] in coordinator?.parent.onRedo() }
        view.tokenTapped = { [weak coordinator = context.coordinator] source, range in coordinator?.parent.onEditToken(source, range) }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapToken(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.addInteraction(context.coordinator.chipMenu)
        view.variables = variables
        view.fontProvider = { Coordinator.font }
        view.decorate = { [weak container] text in BoardDocumentContainer.dimOverflow(text, columns: container?.effectiveColumns ?? 22) }
        view.inputAccessoryView = context.coordinator.accessoryBar()
        buffer.textView = view
        context.coordinator.configure(view)
        context.coordinator.push(source: sessionRows.joined(separator: "\n"), into: view, caret: NSRange(location: 0, length: 0))
        return container
    }

    func updateUIView(_ container: BoardDocumentContainer, context: Context) {
        let coordinator = context.coordinator
        let modeChanged = coordinator.parent.rich != rich || coordinator.parent.uppercase != uppercase
            || coordinator.parent.variables != variables || coordinator.parent.boardColumns != boardColumns
        coordinator.parent = self
        let view = container.textView
        buffer.plainMode = !rich
        view.variables = variables
        container.boardColumns = boardColumns
        container.dimsOverflow = rich
        view.isEditable = editable
        coordinator.configure(view)
        guard view.markedTextRange == nil else { return }
        let sessionSource = sessionRows.joined(separator: "\n")
        // The session changed on its own (undo/redo, recovery, reload): it wins over the buffer.
        if sessionSource != buffer.syncedSource || modeChanged {
            coordinator.push(source: sessionSource, into: view, caret: view.sourceSelection)
        }
        coordinator.refreshAccessory()
        container.boardRows = boardRows
        container.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
        var parent: BoardDocumentView
        init(_ parent: BoardDocumentView) { self.parent = parent }

        /// The chip callout (P1): a tap on a compact chip shows its full name and filters
        /// (`weather.temperature | pad:3`) in the system edit menu, with Edit and Delete. The edit
        /// menu keeps the keyboard up and the caret where it is.
        lazy var chipMenu = UIEditMenuInteraction(delegate: self)
        private var calloutChip: Int?
        private weak var calloutView: TemplateUITextView?

        /// The chip the detail line describes: the one just before a caret, or the first one a
        /// selection covers.
        static func chipDetail(_ view: TemplateUITextView) -> String? {
            guard let text = view.attributedText, text.length > 0, view.markedTextRange == nil else { return nil }
            let selection = view.selectedRange
            if selection.length > 0 {
                var found: TemplateAttachment?
                let range = NSIntersectionRange(selection, NSRange(location: 0, length: text.length))
                text.enumerateAttribute(.attachment, in: range) { value, _, stop in
                    if let attachment = value as? TemplateAttachment, attachment.chip != nil, !attachment.isTile { found = attachment; stop.pointee = true }
                }
                return found?.fullName
            }
            guard selection.location > 0, selection.location <= text.length,
                  let attachment = text.attribute(.attachment, at: selection.location - 1, effectiveRange: nil) as? TemplateAttachment,
                  attachment.chip != nil, !attachment.isTile else { return nil }
            return attachment.fullName
        }

        static func chipRect(_ view: TemplateUITextView, at index: Int) -> CGRect {
            let glyphRange = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            var rect = view.layoutManager.boundingRect(forGlyphRange: glyphRange, in: view.textContainer)
            rect.origin.x += view.textContainerInset.left; rect.origin.y += view.textContainerInset.top
            return rect
        }
        func showCallout(_ view: TemplateUITextView, chip index: Int) {
            calloutChip = index; calloutView = view
            let rect = Self.chipRect(view, at: index)
            let configuration = UIEditMenuConfiguration(identifier: "chipCallout" as NSString, sourcePoint: CGPoint(x: rect.midX, y: rect.maxY))
            // W4: below the chip (arrow up), so it doesn't cover the board's bottom row above the
            // document; the system still flips it above when the keyboard leaves no room.
            configuration.preferredArrowDirection = .up
            chipMenu.presentEditMenu(with: configuration)
        }
        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let view = calloutView, let index = calloutChip, index < view.attributedText.length,
                  let token = view.attributedText.attribute(.attachment, at: index, effectiveRange: nil) as? TemplateAttachment else { return nil }
            let range = NSRange(location: index, length: 1)
            let open = UIAction(title: token.fullName, image: UIImage(systemName: "pencil")) { [weak self, weak view] _ in
                guard let self, let view else { return }
                view.selectedRange = range
                self.tappedChip = nil
                view.tokenTapped?(token.source, view.sourceSelection)
            }
            open.accessibilityLabel = "Edit \(token.accessibilityLabel ?? token.fullName)"
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak view] _ in
                guard let view, view.isEditable, NSMaxRange(range) <= view.attributedText.length else { return }
                view.selectedRange = range
                view.deleteBackward()
            }
            return UIMenu(children: [open, delete])
        }
        func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
            guard let view = calloutView, let index = calloutChip, index < view.attributedText.length else { return .null }
            return Self.chipRect(view, at: index)
        }

        /// Keyboard accessory: mirrors the document toolbar under the title (Undo · Redo ·
        /// Align left/center/right · Wrap) plus Hide keyboard (`editorHideKeyboard`), so the
        /// toolbar stays in reach while the keyboard covers the screen (PLAN B15/B30).
        private var accessoryItems: [String: UIButton] = [:]
        func accessoryBar() -> UIView {
            let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 48), inputViewStyle: .keyboard)
            bar.allowsSelfSizing = true
            func item(_ id: String, _ title: String, _ symbol: String, _ action: @escaping (Coordinator) -> Void) -> UIButton {
                var configuration = UIButton.Configuration.plain()
                configuration.image = UIImage(systemName: symbol)
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
                let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    action(self)
                })
                button.configurationUpdateHandler = { button in
                    var updated = button.configuration
                    updated?.background.backgroundColor = button.isSelected ? UIColor.tintColor.withAlphaComponent(0.18) : .clear
                    updated?.background.cornerRadius = 8
                    button.configuration = updated
                }
                button.accessibilityLabel = title
                button.accessibilityIdentifier = id
                // 34 pt keeps all ten actions (through Wrap) inside a 440 pt phone's row beside the
                // pinned Hide key; at 40 pt Wrap fell past the edge (W2 integration). Narrower
                // phones still scroll.
                // W4: 32 pt, so Draw on board joins the row and Wrap still fits on a 440 pt phone.
                button.widthAnchor.constraint(equalToConstant: 32).isActive = true
                button.heightAnchor.constraint(equalToConstant: 38).isActive = true
                accessoryItems[id] = button
                return button
            }
            func gap() -> UIView { let view = UIView(); view.widthAnchor.constraint(equalToConstant: 4).isActive = true; return view }
            // iOS-F1: searchable pickers in a sheet replace the wave-2 menus (B22).
            let draw = item("accessory_draw", EditorStrings.drawOnBoard, "pencil.tip.crop.circle") { $0.parent.onDraw() }
            let variables = item("accessory_variables", EditorStrings.variables, "curlybraces") { $0.parent.onPicker(.variables) }
            let colors = item("accessory_colors", EditorStrings.colors, "paintpalette") { $0.parent.onPicker(.colors) }
            let formatting = item("accessory_formatting", EditorStrings.formatting, "textformat") { $0.parent.onPicker(.formatting) }
            let formula = item("accessory_formula", EditorStrings.insertFormula, "function") { $0.parent.onFormula() }
            let undo = item("accessory_undo", EditorStrings.undo, "arrow.uturn.backward") { $0.parent.onUndo() }
            let redo = item("accessory_redo", EditorStrings.redo, "arrow.uturn.forward") { $0.parent.onRedo() }
            let left = item("accessory_alignLeft", EditorStrings.alignLeft, "text.alignleft") { $0.parent.onAlign("left") }
            let center = item("accessory_alignCenter", EditorStrings.alignCenter, "text.aligncenter") { $0.parent.onAlign("center") }
            let right = item("accessory_alignRight", EditorStrings.alignRight, "text.alignright") { $0.parent.onAlign("right") }
            let wrap = item("accessory_wrap", EditorStrings.wrap, "text.word.spacing") { $0.parent.onWrap(!$0.parent.accessory.wrap) }
            let hide = item("editorHideKeyboard", EditorStrings.hideKeyboard, "keyboard.chevron.compact.down") { $0.parent.buffer.resignFocus() }
            // One scrollable row (inserts first, as the web research recommends); Hide stays pinned.
            let stack = UIStackView(arrangedSubviews: [draw, variables, colors, formatting, formula, gap(), undo, redo, gap(), left, center, right, wrap])
            stack.axis = .horizontal; stack.alignment = .center; stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            let scroller = UIScrollView()
            scroller.showsHorizontalScrollIndicator = false
            scroller.translatesAutoresizingMaskIntoConstraints = false
            scroller.addSubview(stack)
            hide.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(scroller); bar.addSubview(hide)
            NSLayoutConstraint.activate([
                scroller.leadingAnchor.constraint(equalTo: bar.layoutMarginsGuide.leadingAnchor, constant: -6),
                scroller.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -2),
                scroller.topAnchor.constraint(equalTo: bar.topAnchor, constant: 4),
                scroller.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -4),
                stack.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
                stack.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
                hide.trailingAnchor.constraint(equalTo: bar.layoutMarginsGuide.trailingAnchor, constant: 6),
                hide.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
            refreshAccessory()
            return bar
        }

        /// Selected/enabled state follows the toolbar (the caret row's alignment and wrap).
        func refreshAccessory() {
            let state = parent.accessory
            func set(_ id: String, selected: Bool = false, enabled: Bool = true) {
                guard let button = accessoryItems[id] else { return }
                if button.isSelected != selected { button.isSelected = selected }
                if button.isEnabled != (enabled && state.enabled) { button.isEnabled = enabled && state.enabled }
            }
            set("accessory_variables", enabled: state.variablesEnabled)
            accessoryItems["accessory_draw"]?.isHidden = !state.drawShown
            accessoryItems["accessory_colors"]?.isHidden = !state.colorsShown
            accessoryItems["accessory_formatting"]?.isHidden = !state.formattingShown
            set("accessory_undo", enabled: state.canUndo)
            set("accessory_redo", enabled: state.canRedo)
            set("accessory_alignLeft", selected: state.alignment == "left")
            set("accessory_alignCenter", selected: state.alignment == "center")
            set("accessory_alignRight", selected: state.alignment == "right")
            set("accessory_wrap", selected: state.wrap)
        }

        func configure(_ view: TemplateUITextView) {
            let capitalization: UITextAutocapitalizationType = parent.uppercase ? .allCharacters : .none
            if view.autocapitalizationType != capitalization {
                view.autocapitalizationType = capitalization
                if view.isFirstResponder { view.reloadInputViews() }
            }
        }
        static var font: UIFont {
            // W4: on iPad the document's rows are larger (body × 1.35, ≈ 23 pt at the default
            // size), so the document reads at arm's length and fills the band under the board.
            let size = UIFont.preferredFont(forTextStyle: .body).pointSize * (UIDevice.current.userInterfaceIdiom == .pad ? 1.35 : 1)
            return UIFont.monospacedSystemFont(ofSize: size.rounded(), weight: .regular)
        }

        func push(source: String, into view: TemplateUITextView, caret: NSRange) {
            view.setTemplate(source, rich: parent.rich, font: Self.font, sourceSelection: caret)
            let buffer = parent.buffer
            buffer.syncedSource = source
            buffer.adopt(rows: source.components(separatedBy: "\n"), caret: caretRows(view), dirty: false)
            (view.superview as? BoardDocumentContainer)?.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
        }

        private func caretRows(_ view: TemplateUITextView) -> ClosedRange<Int> {
            let text = view.attributedText.string as NSString
            let selection = view.selectedRange
            func row(at location: Int) -> Int {
                let end = min(max(0, location), text.length)
                return text.substring(to: end).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            }
            let first = row(at: selection.location)
            let last = row(at: NSMaxRange(selection))
            return first...max(first, last)
        }

        /// Display index of the chip the user just tapped (caret after it, outlined, B14).
        private var tappedChip: Int?

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            // A caret just before or after the tapped chip keeps it "tapped" (a second tap opens it).
            if let tapped = tappedChip, !(view.selectedRange.length == 0 && [tapped, tapped + 1].contains(view.selectedRange.location)) { tappedChip = nil }
            view.updateChipOutlines(tapped: tappedChip)
            let buffer = parent.buffer
            buffer.setChipDetail(Self.chipDetail(view))
            buffer.adopt(rows: buffer.rows, caret: caretRows(view), dirty: false)
            (view.superview as? BoardDocumentContainer)?.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChange(true) }
        func textViewDidEndEditing(_ textView: UITextView) {
            textView.unmarkText(); textViewDidChange(textView)
            parent.onFocusChange(false)
            parent.onCommitNow()
        }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            var source = view.templateSource
            // A completed `{{…}}` typed in rich mode becomes a chip right away.
            if parent.rich, TemplateSyntax.fragments(source).reduce(0, { $0 + $1.displayLength }) != view.attributedText.length {
                let selection = view.sourceSelection
                view.setTemplate(source, rich: true, font: Self.font, sourceSelection: selection)
                source = view.templateSource
            }
            view.accessibilityValue = source
            if let container = view.superview as? BoardDocumentContainer {
                let selection = view.selectedRange
                view.textStorage.beginEditing()
                BoardDocumentContainer.dimOverflow(view.textStorage, columns: container.effectiveColumns)
                view.textStorage.endEditing()
                view.selectedRange = selection
            }
            let rows = source.components(separatedBy: "\n")
            let buffer = parent.buffer
            buffer.setChipDetail(Self.chipDetail(view))
            guard rows != buffer.rows else { return }
            buffer.adopt(rows: rows, caret: caretRows(view), dirty: true)
            (view.superview as? BoardDocumentContainer)?.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
            parent.onEdited()
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", textView.markedTextRange == nil, let view = textView as? TemplateUITextView,
               let handled = returnKey(view, range: range) { return handled }
            guard parent.uppercase, textView.markedTextRange == nil, !text.isEmpty,
                  let view = textView as? TemplateUITextView else { return true }
            // Uppercase only what is typed or pasted, never inside a `{{…}}` token (PLAN §2.2).
            let display = view.attributedText.string as NSString
            let rowStart = display.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: min(range.location, display.length))).location
            let prefixRange = NSRange(location: rowStart == NSNotFound ? 0 : rowStart + 1, length: 0)
            let prefixDisplay = NSRange(location: prefixRange.location, length: max(0, range.location - prefixRange.location))
            let prefix = TemplateUITextView.source(view.attributedText.attributedSubstring(from: prefixDisplay))
            let upper = FlapInputCase.uppercased(text, openBefore: FlapInputCase.isInsideToken(rowPrefix: prefix))
            guard upper != text else { return true }
            view.selectedRange = range
            view.insertText(upper)
            return false
        }
        /// Return moves to the next empty row before it adds one (web research §d.5): on a padded
        /// page, Return at the end of a row whose next row is empty moves the caret there, so a
        /// beginner's first Return never reads "7 / 6". Splitting a row still inserts one (row
        /// metadata follows it through `LineMetadataSplice`). Returns nil to let UIKit insert.
        private func returnKey(_ view: TemplateUITextView, range: NSRange) -> Bool? {
            let text = view.attributedText.string as NSString
            guard range.length == 0 else { return nil }
            let end = range.location
            let atRowEnd = end == text.length || text.character(at: end) == 10
            if atRowEnd, end < text.length {
                let next = text.range(of: "\n", options: [], range: NSRange(location: end + 1, length: text.length - end - 1))
                let nextRowEnd = next.location == NSNotFound ? text.length : next.location
                if nextRowEnd == end + 1 {
                    view.selectedRange = NSRange(location: end + 1, length: 0)
                    return false
                }
            }
            return nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = scrollView as? TemplateUITextView else { return }
            (view.superview as? BoardDocumentContainer)?.refreshGutter(rows: parent.buffer.rows, caretRows: parent.buffer.caretRows)
        }
        @objc func tapToken(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? TemplateUITextView, view.markedTextRange == nil, parent.rich else { return }
            let point = gesture.location(in: view)
            guard let position = view.closestPosition(to: point) else { return }
            let index = view.offset(from: view.beginningOfDocument, to: position)
            for candidate in [index, index - 1] where candidate >= 0 && candidate < view.attributedText.length {
                guard let token = view.attributedText.attribute(.attachment, at: candidate, effectiveRange: nil) as? TemplateAttachment else { continue }
                let range = NSRange(location: candidate, length: 1)
                let glyphRange = view.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var rect = view.layoutManager.boundingRect(forGlyphRange: glyphRange, in: view.textContainer)
                rect.origin.x += view.textContainerInset.left; rect.origin.y += view.textContainerInset.top
                guard rect.insetBy(dx: -3, dy: -3).contains(point) else { continue }
                if tappedChip == candidate {
                    // A second tap on the outlined chip opens it (formula sheet or token editor).
                    chipMenu.dismissMenu()
                    view.selectedRange = range
                    view.tokenTapped?(token.source, view.sourceSelection)
                    return
                }
                // The caret goes after the chip, never inside it; the chip is outlined (B14) and its
                // callout shows the full name (P1).
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.tappedChip = candidate
                    view.selectedRange = NSRange(location: candidate + 1, length: 0)
                    view.updateChipOutlines(tapped: candidate)
                    self.showCallout(view, chip: candidate)
                    if let token = view.attributedText.attribute(.attachment, at: candidate, effectiveRange: nil) as? TemplateAttachment {
                        UIAccessibility.post(notification: .announcement, argument: token.accessibilityLabel)
                    }
                }
                return
            }
            tappedChip = nil
        }
    }
}

/// Gutter + text view, side by side. The gutter tracks the text view's scroll offset.
final class BoardDocumentContainer: UIView {
    let textView = TemplateUITextView(usingTextLayoutManager: false)
    let gutter = RowGutterView()
    /// Placeholder on row 1 only (B12), shown while the whole document is empty.
    private let placeholder = UILabel()
    var boardRows = 6
    /// The board's width in tiles: a faint guide marks it, and text past it is dimmed.
    var boardColumns = 22 { didSet { if oldValue != boardColumns { setNeedsLayout() } } }
    private let columnGuide = CAShapeLayer()
    /// Rich mode only: in Plain mode the token text has no board width.
    var dimsOverflow = true
    var effectiveColumns: Int { dimsOverflow ? boardColumns : Int.max }
    private var lastRows: [String] = []
    private var lastCaret: ClosedRange<Int> = 0...0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(gutter); addSubview(textView)
        placeholder.text = "Type your message"
        placeholder.textColor = .placeholderText
        placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false
        textView.addSubview(placeholder)
        columnGuide.strokeColor = UIColor.separator.cgColor
        columnGuide.lineWidth = 1
        columnGuide.lineDashPattern = [2, 3]
        columnGuide.fillColor = nil
        textView.layer.addSublayer(columnGuide)
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        columnGuide.strokeColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        gutter.frame = CGRect(x: 0, y: 0, width: RowGutterView.width, height: bounds.height)
        textView.frame = CGRect(x: RowGutterView.width, y: 0, width: max(0, bounds.width - RowGutterView.width), height: bounds.height)
        refreshGutter(rows: lastRows, caretRows: lastCaret)
    }
    func refreshGutter(rows: [String], caretRows: ClosedRange<Int>) {
        lastRows = rows; lastCaret = caretRows
        gutter.update(textView: textView, rows: rows, caretRows: caretRows, boardRows: boardRows)
        placeholder.font = BoardDocumentView.Coordinator.font
        placeholder.isHidden = !rows.allSatisfy(\.isEmpty)
        let lineHeight = placeholder.font.lineHeight
        placeholder.frame = CGRect(x: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                                   y: textView.textContainerInset.top, width: max(0, textView.bounds.width - 24), height: lineHeight)
        // Column guide: one segment per row, where the board cuts that row (P1).
        let path = guidePath()
        columnGuide.isHidden = path == nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        columnGuide.path = path
        CATransaction.commit()
    }

    /// Where the board cuts one row of the document (PLAN B16, P1). Text and tiles are one cell;
    /// a chip counts its *board* width (`TemplateAttachment.boardWidth`, e.g. `pad:3` → 3), not its
    /// drawn width, so the guide marks where the board really ends even on chip rows. Flexible
    /// space fills what is left. A token whose width is only known after the server renders it
    /// makes the row `unknown`: no guide and no dimming there.
    enum RowFit: Equatable {
        case unknown
        /// The row fits with `remaining` empty cells after its last character.
        case fits(remaining: Int)
        /// The board cuts inside the character at `index` (display offset), `fraction` of the way
        /// into it (0 for text: the cut is at its leading edge).
        case cut(index: Int, fraction: CGFloat)
    }
    static func rowFit(_ text: NSAttributedString, range: NSRange, columns: Int) -> RowFit {
        var widths: [Int] = []
        var fills = 0
        for index in range.location..<NSMaxRange(range) {
            if let attachment = text.attribute(.attachment, at: index, effectiveRange: nil) as? TemplateAttachment {
                if case .fill? = attachment.chip?.style { fills += 1; widths.append(0); continue }
                guard let width = attachment.boardWidth else { return .unknown }
                widths.append(width)
            } else { widths.append(1) }
        }
        let total = widths.reduce(0, +)
        if fills > 0, total <= columns { return .fits(remaining: 0) }
        var column = 0
        for (offset, width) in widths.enumerated() where width > 0 {
            if column + width > columns {
                return .cut(index: range.location + offset, fraction: CGFloat(columns - column) / CGFloat(width))
            }
            column += width
        }
        return .fits(remaining: columns - total)
    }

    static func hasFill(_ text: NSAttributedString, range: NSRange) -> Bool {
        var found = false
        text.enumerateAttribute(.attachment, in: range) { value, _, stop in
            if case .fill? = (value as? TemplateAttachment)?.chip?.style { found = true; stop.pointee = true }
        }
        return found
    }

    /// Display ranges of each row (paragraph), without the newline.
    static func rowRanges(_ string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = 0
        while true {
            let newline = string.range(of: "\n", options: [], range: NSRange(location: start, length: string.length - start))
            let end = newline.location == NSNotFound ? string.length : newline.location
            ranges.append(NSRange(location: start, length: end - start))
            if newline.location == NSNotFound { break }
            start = end + 1
        }
        return ranges
    }

    /// Dims everything the board cuts off, row by row, from `rowFit` (PLAN B16 / web §d.4).
    static func dimOverflow(_ text: NSMutableAttributedString, columns: Int) {
        let full = NSRange(location: 0, length: text.length)
        text.removeAttribute(.foregroundColor, range: full)
        text.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        guard columns < Int.max else { return }
        for range in rowRanges(text.string as NSString) {
            guard case .cut(let index, let fraction) = rowFit(text, range: range, columns: columns) else { continue }
            let from = fraction > 0 ? index + 1 : index
            if from < NSMaxRange(range) {
                text.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: NSRange(location: from, length: NSMaxRange(range) - from))
            }
        }
    }

    /// The column guide as one short dashed segment per row, each where the board cuts that row
    /// (rows of plain text line up into one straight line, as before; a chip row's segment sits
    /// where its chips' board cells end). Rows of unknown width get none.
    func guidePath() -> CGPath? {
        guard dimsOverflow, let text = textView.attributedText, textView.bounds.width > 0 else { return nil }
        let layout = textView.layoutManager, container = textView.textContainer
        let inset = textView.textContainerInset
        let advance = ("M" as NSString).size(withAttributes: [.font: BoardDocumentView.Coordinator.font]).width
        let origin = inset.left + container.lineFragmentPadding
        let path = UIBezierPath()
        let string = text.string as NSString
        for range in Self.rowRanges(string) {
            // The row's vertical extent: its line fragments (an empty last row is the extra fragment).
            var rowRect: CGRect
            if range.length == 0 && range.location >= string.length {
                rowRect = layout.extraLineFragmentRect
                if rowRect.isEmpty, string.length == 0 { rowRect = CGRect(x: 0, y: 0, width: 0, height: BoardDocumentView.Coordinator.font.lineHeight) }
            } else {
                let characters = NSRange(location: range.location, length: max(1, range.length))
                let glyphs = layout.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                rowRect = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                if glyphs.length > 1 { rowRect = rowRect.union(layout.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)) }
            }
            guard !rowRect.isEmpty else { continue }
            let x: CGFloat
            switch Self.rowFit(text, range: range, columns: boardColumns) {
            case .unknown: continue
            case .fits(let remaining):
                // Flexible space makes the row exactly full: a mark at its end says nothing useful.
                if Self.hasFill(text, range: range) { continue }
                if range.length == 0 { x = origin + CGFloat(remaining) * advance }
                else {
                    let last = layout.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(range) - 1, length: 1), actualCharacterRange: nil)
                    x = layout.boundingRect(forGlyphRange: last, in: container).maxX + inset.left + CGFloat(remaining) * advance
                }
            case .cut(let index, let fraction):
                let glyph = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                let box = layout.boundingRect(forGlyphRange: glyph, in: container)
                x = box.minX + fraction * box.width + inset.left
            }
            let lineX = x.rounded() + 0.5
            guard lineX < textView.bounds.width - 4 else { continue }
            path.move(to: CGPoint(x: lineX, y: rowRect.minY + inset.top))
            path.addLine(to: CGPoint(x: lineX, y: rowRect.maxY + inset.top))
        }
        return path.cgPath
    }
    override var accessibilityElements: [Any]? {
        get { [textView] + (gutter.accessibilityElements ?? []) }
        set {}
    }
}
