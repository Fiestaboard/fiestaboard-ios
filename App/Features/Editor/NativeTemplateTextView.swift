import SwiftUI
import UIKit
import FiestaBoardDocuments

@MainActor final class TemplateTextSelection {
    var range = NSRange(location: 0, length: 0)
    var pendingCaret: NSRange?
}

/// TextKit authoring view. Attachments retain their exact source; clipboard operations
/// export template syntax instead of image/RTF placeholders. Marked text is never rebuilt.
struct NativeTemplateTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    var rich: Bool
    var selection: TemplateTextSelection
    var allowsMultiline = false
    var documentUndo = false
    var onEditToken: (String, NSRange) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TemplateUITextView {
        let view = TemplateUITextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.allowsMultiline = allowsMultiline
        view.usesDocumentUndo = documentUndo
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.accessibilityIdentifier = "templateRowText"
        view.accessibilityLabel = allowsMultiline ? "Block text" : "Row text"
        view.tokenTapped = { [weak coordinator = context.coordinator] source, range in coordinator?.parent.onEditToken(source, range) }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapToken(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.render(view, source: text, sourceSelection: selection.range)
        return view
    }
    func updateUIView(_ view: TemplateUITextView, context: Context) {
        let coordinator = context.coordinator
        let modeChanged = coordinator.parent.rich != rich
        coordinator.parent = self
        guard view.markedTextRange == nil else { return }
        if selection.pendingCaret != nil || modeChanged || !LosslessJSON.stringsEqual(view.templateSource, text) {
            let selection = selection.pendingCaret ?? view.sourceSelection
            self.selection.pendingCaret = nil
            coordinator.render(view, source: text, sourceSelection: selection)
        }
        view.accessibilityValue = text
    }
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        var parent: NativeTemplateTextView
        init(_ parent: NativeTemplateTextView) { self.parent = parent }
        func render(_ view: TemplateUITextView, source: String, sourceSelection: NSRange) {
            let font = UIFont.preferredFont(forTextStyle: .body)
            view.setTemplate(source, rich: parent.rich, font: font, sourceSelection: sourceSelection)
            parent.selection.range = view.sourceSelection
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            parent.selection.range = view.sourceSelection
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isEditing = true }
        func textViewDidEndEditing(_ textView: UITextView) {
            textView.unmarkText(); textViewDidChange(textView); parent.isEditing = false
        }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            let source = view.templateSource
            let selection = view.sourceSelection
            parent.text = source
            parent.selection.range = selection
            // Tokenization after committed text input only; no uppercase/Unicode normalization.
            if !LosslessJSON.stringsEqual(source, parent.text) { render(view, source: parent.text, sourceSelection: selection) }
            else if parent.rich && TemplateSyntax.fragments(source).reduce(0, { $0 + $1.displayLength }) != view.attributedText.length {
                render(view, source: source, sourceSelection: selection)
            }
            view.accessibilityValue = source
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Multiline authoring uses explicit row operations; never silently flatten paste.
            parent.allowsMultiline || (!text.contains("\n") && !text.contains("\r"))
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

final class TemplateUITextView: UITextView {
    var allowsMultiline = false
    var usesDocumentUndo = false
    override var undoManager: UndoManager? { usesDocumentUndo ? nil : super.undoManager }
    /// Hardware ⌘Z / ⌘⇧Z / ⌘Y reach the session's undo, not UIKit's (PLAN B17).
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    /// Whether layoutSubviews may toggle scrolling for short single rows (the row editor);
    /// the document surface always scrolls.
    var managesOwnScrolling = true

    override var keyCommands: [UIKeyCommand]? {
        guard onUndo != nil || onRedo != nil else { return super.keyCommands }
        let commands = [
            UIKeyCommand(title: "Undo", action: #selector(sessionUndo), input: "z", modifierFlags: .command),
            UIKeyCommand(title: "Redo", action: #selector(sessionRedo), input: "z", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: "Redo", action: #selector(sessionRedo), input: "y", modifierFlags: .command)
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return (super.keyCommands ?? []) + commands
    }
    @objc private func sessionUndo() { onUndo?() }
    @objc private func sessionRedo() { onRedo?() }

    /// Replaces the whole content with `source`, as attachments (rich) or raw text (plain),
    /// placing the selection at the given source range. Never call with marked text.
    func setTemplate(_ source: String, rich: Bool, font: UIFont, sourceSelection: NSRange, color: UIColor = .label) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let result = NSMutableAttributedString(string: "")
        if rich {
            for fragment in TemplateSyntax.fragments(source) {
                if fragment.kind == .text { result.append(NSAttributedString(string: fragment.source, attributes: attributes)) }
                else { result.append(NSAttributedString(attachment: TemplateAttachment(fragment: fragment, font: font))) }
            }
        } else { result.append(NSAttributedString(string: source, attributes: attributes)) }
        attributedText = result
        typingAttributes = attributes
        let start = rich ? TemplateSyntax.displayOffset(sourceOffset: sourceSelection.location, in: source) : sourceSelection.location
        let end = rich ? TemplateSyntax.displayOffset(sourceOffset: NSMaxRange(sourceSelection), in: source) : NSMaxRange(sourceSelection)
        let safeStart = min(start, result.length)
        selectedRange = NSRange(location: safeStart, length: max(0, min(end, result.length) - safeStart))
        accessibilityValue = source
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard managesOwnScrolling else { return }
        // A short row must not consume vertical gestures intended for the surrounding
        // editor. Long source still scrolls inside its native text viewport.
        let needsScrolling = contentSize.height > bounds.height + 1
        if isScrollEnabled != needsScrolling { isScrollEnabled = needsScrolling }
    }
    var tokenTapped: ((String, NSRange) -> Void)?
    var templateSource: String { Self.source(attributedText ?? NSAttributedString()) }
    var sourceSelection: NSRange {
        let text = attributedText ?? NSAttributedString()
        let start = min(selectedRange.location, text.length)
        let length = min(selectedRange.length, text.length - start)
        return NSRange(location: Self.source(text.attributedSubstring(from: NSRange(location: 0, length: start))).utf16.count,
                       length: Self.source(text.attributedSubstring(from: NSRange(location: start, length: length))).utf16.count)
    }
    static func source(_ value: NSAttributedString) -> String {
        var source = ""
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            if let token = attributes[.attachment] as? TemplateAttachment { source += token.source }
            else { source += (value.string as NSString).substring(with: range) }
        }
        return source
    }
    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = Self.source(attributedText.attributedSubstring(from: selectedRange))
    }
    override func cut(_ sender: Any?) { copy(sender); insertText("") }
    override func paste(_ sender: Any?) {
        guard let source = UIPasteboard.general.string else { return }
        guard allowsMultiline || (!source.contains("\n") && !source.contains("\r")) else {
            UIAccessibility.post(notification: .announcement, argument: "Use separate rows for multiline text.")
            return
        }
        insertTemplate(source)
    }
    func insertTemplate(_ source: String) {
        guard allowsMultiline || (!source.contains("\n") && !source.contains("\r")) else { return }
        insertText(source)
    }
}

final class TemplateAttachment: NSTextAttachment {
    let source: String
    init(fragment: TemplateSyntax.Fragment, font: UIFont) {
        source = fragment.source
        super.init(data: nil, ofType: nil)
        let label = fragment.label
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let width = min(230, max(34, (label as NSString).size(withAttributes: attributes).width + 18))
        let height = font.lineHeight + 6
        image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            UIColor.tertiarySystemFill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 7).fill()
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
            var labelAttributes = attributes; labelAttributes[.paragraphStyle] = style
            (label as NSString).draw(in: CGRect(x: 9, y: 3, width: width - 18, height: height - 6), withAttributes: labelAttributes)
        }
        bounds = CGRect(x: 0, y: font.descender - 3, width: width, height: height)
    }
    required init?(coder: NSCoder) { return nil }
}
