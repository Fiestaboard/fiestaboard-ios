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
    /// The buffer has typing the session has not seen yet.
    private(set) var isDirty = false
    /// Source last pushed from the session; the session wins only when it changes on its own.
    fileprivate var syncedSource: String?
    fileprivate weak var textView: TemplateUITextView?

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

/// One continuous editable surface for the whole page: rows are paragraphs of a single
/// TextKit 1 `TemplateUITextView` (PLAN B12, §3.2). Return inserts a row, Backspace at a row's
/// start joins it to the previous one; there is no per-row chrome.
struct BoardDocumentView: UIViewRepresentable {
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
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onEditToken: (String, NSRange) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BoardDocumentContainer {
        let container = BoardDocumentContainer()
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
        view.inputAccessoryView = context.coordinator.accessoryBar()
        buffer.textView = view
        context.coordinator.configure(view)
        context.coordinator.push(source: sessionRows.joined(separator: "\n"), into: view, caret: NSRange(location: 0, length: 0))
        return container
    }

    func updateUIView(_ container: BoardDocumentContainer, context: Context) {
        let coordinator = context.coordinator
        let modeChanged = coordinator.parent.rich != rich || coordinator.parent.uppercase != uppercase
        coordinator.parent = self
        let view = container.textView
        view.isEditable = editable
        coordinator.configure(view)
        guard view.markedTextRange == nil else { return }
        let sessionSource = sessionRows.joined(separator: "\n")
        // The session changed on its own (undo/redo, recovery, reload): it wins over the buffer.
        if sessionSource != buffer.syncedSource || modeChanged {
            coordinator.push(source: sessionSource, into: view, caret: view.sourceSelection)
        }
        container.boardRows = boardRows
        container.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: BoardDocumentView
        init(_ parent: BoardDocumentView) { self.parent = parent }

        /// Keyboard accessory: Undo · Redo · Hide keyboard (`editorHideKeyboard`). The full
        /// toolbar mirror is wave 2 (B30).
        func accessoryBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), primaryAction: UIAction { [weak self] _ in self?.parent.onUndo() })
            undo.accessibilityLabel = EditorStrings.undo
            let redo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.forward"), primaryAction: UIAction { [weak self] _ in self?.parent.onRedo() })
            redo.accessibilityLabel = EditorStrings.redo
            let hide = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction { [weak self] _ in self?.parent.buffer.resignFocus() })
            hide.accessibilityLabel = EditorStrings.hideKeyboard
            hide.accessibilityIdentifier = "editorHideKeyboard"
            bar.items = [undo, redo, .flexibleSpace(), hide]
            bar.sizeToFit()
            return bar
        }

        func configure(_ view: TemplateUITextView) {
            let capitalization: UITextAutocapitalizationType = parent.uppercase ? .allCharacters : .none
            if view.autocapitalizationType != capitalization {
                view.autocapitalizationType = capitalization
                if view.isFirstResponder { view.reloadInputViews() }
            }
        }
        static var font: UIFont {
            let size = UIFont.preferredFont(forTextStyle: .body).pointSize
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            let buffer = parent.buffer
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
            let rows = source.components(separatedBy: "\n")
            let buffer = parent.buffer
            guard rows != buffer.rows else { return }
            buffer.adopt(rows: rows, caret: caretRows(view), dirty: true)
            (view.superview as? BoardDocumentContainer)?.refreshGutter(rows: buffer.rows, caretRows: buffer.caretRows)
            parent.onEdited()
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
                view.selectedRange = range
                view.tokenTapped?(token.source, view.sourceSelection)
                return
            }
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
    }
    override var accessibilityElements: [Any]? {
        get { [textView] + (gutter.accessibilityElements ?? []) }
        set {}
    }
}
