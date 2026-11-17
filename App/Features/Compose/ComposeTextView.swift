import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState

/// Reuses the editor's source-preserving TextKit control. A committed native
/// edit publishes source and source selection in one immutable value.
struct ComposeTextView: UIViewRepresentable {
    let input: ComposeInput
    var enabled: Bool
    let onChange: (ComposeInput) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TemplateUITextView {
        let view = TemplateUITextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.allowsMultiline = true
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.autocorrectionType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.accessibilityIdentifier = "composeSource"
        view.accessibilityLabel = "Message text"
        context.coordinator.render(view)
        return view
    }
    func updateUIView(_ view: TemplateUITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = enabled
        guard view.markedTextRange == nil else { return }
        let desired = NSRange(location: input.selection.lowerUTF16, length: input.selection.upperUTF16 - input.selection.lowerUTF16)
        if !LosslessJSON.stringsEqual(view.templateSource, input.text) || view.sourceSelection != desired {
            context.coordinator.render(view)
        }
        view.accessibilityValue = input.text
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposeTextView
        private var rendering = false
        init(_ parent: ComposeTextView) { self.parent = parent }
        func render(_ view: TemplateUITextView) {
            rendering = true; defer { rendering = false }
            let input = parent.input
            view.setTemplate(input.text, rich: true, font: .preferredFont(forTextStyle: .body),
                sourceSelection: NSRange(location: input.selection.lowerUTF16, length: input.selection.upperUTF16 - input.selection.lowerUTF16))
        }
        func textViewDidChange(_ textView: UITextView) {
            guard !rendering, textView.markedTextRange == nil, let view = textView as? TemplateUITextView else { return }
            let selection = view.sourceSelection
            let input = ComposeAuthoring.replacingText(view.templateSource, in: parent.input,
                selection: .init(lowerUTF16: selection.location, upperUTF16: NSMaxRange(selection)))
            parent.onChange(input)
            view.accessibilityValue = input.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) { textViewDidChange(textView) }
        func textViewDidEndEditing(_ textView: UITextView) {
            textView.unmarkText(); textViewDidChange(textView)
        }
    }
}
