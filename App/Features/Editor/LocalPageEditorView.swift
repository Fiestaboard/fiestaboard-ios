import SwiftUI
import UIKit
import FiestaBoardDocuments

private typealias EditorState<Value> = SwiftUI.State<Value>

/// Present this view in a sheet or navigation destination using a full raw page response.
/// This screen writes local drafts only. It never sends page updates to a server.
@MainActor
public struct LocalPageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LocalPageEditorModel
    @EditorState private var confirmClose = false
    @EditorState private var isTextInputActive = false

    public init(rawDocumentData: Data, identity: DraftIdentity, draftStore: LocalDraftStore) throws {
        let model = try LocalPageEditorModel(
            rawDocumentData: rawDocumentData, identity: identity, draftStore: draftStore
        )
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section {
                Label("Local draft only", systemImage: "internaldrive")
                Text("Changes stay on this device. Template expressions and formatting tokens are edited as raw text.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(model.hasUnsavedChanges ? "Unsaved local changes" : "No unsaved local changes")
                    .font(.footnote)
            }
            if let recovery = model.recoveryNotice {
                Section("Draft recovery") {
                    Text(recovery)
                    if model.canRecover {
                        Button("Recover local draft") { commitTextInput(); model.recoverDraft() }
                    }
                    if model.hasCorruptDraft {
                        Button("Preserve damaged draft separately") { Task { await model.preserveCorruptDraft() } }
                    } else {
                        Button("Keep fetched page") { model.dismissRecovery() }
                    }
                }
            }
            Section("Page name") {
                TextField("Name", text: Binding(get: { model.name }, set: { model.setName($0) }))
                    .autocorrectionDisabled()
            }
            if let lines = model.lines {
                Section("Raw template · fixed line slots") {
                    Text("Each line keeps its original metadata. Adding, removing, or reordering lines is unavailable in this editor.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(lines.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text("Line \(index + 1)").font(.caption).foregroundStyle(.secondary)
                            RawTemplateTextView(text: Binding(
                                get: { model.lines?[safe: index] ?? "" },
                                set: { model.setLine(index, text: $0) }
                            ), isEditing: $isTextInputActive)
                            .frame(minHeight: 72)
                        }
                    }
                }
            } else {
                Section("Read-only content") {
                    Text("This page’s content mode or metadata cannot be safely edited here. Its full raw document is preserved.")
                    Text(model.pageType).font(.caption.monospaced())
                    Text(model.readOnlyDocumentText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                Button("Save local draft") {
                    commitTextInput()
                    Task { await model.saveDraft() }
                }
                    .disabled(model.isSaving)
                HStack {
                    Button("Undo") { commitTextInput(); model.undo() }.disabled(!model.canUndo)
                    Spacer()
                    Button("Redo") { commitTextInput(); model.redo() }.disabled(!model.canRedo)
                }
            }
        }
        .navigationTitle("Local page editor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.hasUnsavedChanges || model.isSaving || isTextInputActive)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    commitTextInput()
                    if model.hasUnsavedChanges { confirmClose = true } else { dismiss() }
                }.disabled(model.isSaving)
            }
        }
        .confirmationDialog("Keep your local changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save local draft and close") {
                Task { if await model.saveDraft() { dismiss() } }
            }
            Button("Discard unsaved changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Discarding leaves any previously saved local draft in place.")
        }
        .task { await model.checkRecovery() }
    }

    private func commitTextInput() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// TextKit 1 storage/layout on purpose: preserves raw strings and native marked-text input.
/// Formatting is not converted to HTML or attributed content. UI/IME parity needs device tests.
private struct RawTemplateTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.widthTracksTextView = true
        let view = UITextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.isScrollEnabled = true
        view.accessibilityLabel = "Raw template line"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil, view.text != text else { return }
        let selection = view.selectedRange
        view.text = text
        let length = (text as NSString).length
        view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RawTemplateTextView
        init(_ parent: RawTemplateTextView) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isEditing = true }
        func textViewDidEndEditing(_ textView: UITextView) {
            textView.unmarkText()
            parent.text = textView.text
            parent.isEditing = false
        }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
            if textView.text != parent.text { textView.text = parent.text }
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            !text.contains("\n") && !text.contains("\r")
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
