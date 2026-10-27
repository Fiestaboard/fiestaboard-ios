import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit

private typealias EditorState<Value> = SwiftUI.State<Value>

/// Present this view in a sheet or navigation destination using a full raw page response.
/// Local checkpoints and explicit revision-checked server storage are distinct actions.
@MainActor
public struct LocalPageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LocalPageEditorModel
    @EditorState private var confirmClose = false
    @EditorState private var confirmServerSave = false
    @EditorState private var confirmRemoteReload = false
    @EditorState private var isTextInputActive = false

    public init(rawDocumentData: Data, identity: DraftIdentity, draftStore: LocalDraftStore, remote: EditorRemoteActions? = nil, boards: [EditorBoardChoice] = []) throws {
        let model = try LocalPageEditorModel(
            rawDocumentData: rawDocumentData, identity: identity, draftStore: draftStore, remote: remote, boards: boards
        )
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section {
                Label("Local draft", systemImage: "internaldrive")
                Text("Save local draft keeps changes on this device. A separate confirmed server save updates stored page content. Template expressions and formatting tokens are edited as raw text.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(model.hasUnsavedChanges ? "Unsaved local changes" : "No unsaved local changes")
                    .font(.footnote)
                Text(model.hasServerChanges ? "Changed from server baseline" : "Matches server baseline")
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
                    .disabled(model.editingFrozen)
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
                            .disabled(model.editingFrozen)
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
            evaluationSection
            serverSection
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                Button("Save local draft") {
                    commitTextInput()
                    Task { await model.saveDraft() }
                }
                    .disabled(model.isSaving || model.editingFrozen)
                HStack {
                    Button("Undo") { commitTextInput(); model.undo() }.disabled(!model.canUndo || model.editingFrozen)
                    Spacer()
                    Button("Redo") { commitTextInput(); model.redo() }.disabled(!model.canRedo || model.editingFrozen)
                }
            }
        }
        .navigationTitle("Page editor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.hasUnsavedChanges || model.isSaving || model.editingFrozen || isTextInputActive)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    commitTextInput()
                    if model.hasUnsavedChanges { confirmClose = true } else { model.endEditingSession(); dismiss() }
                }.disabled(model.isSaving || model.editingFrozen)
            }
        }
        .confirmationDialog("Keep your local changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save local draft and close") {
                Task { if await model.saveDraft() { model.endEditingSession(); dismiss() } }
            }
            Button("Discard unsaved changes", role: .destructive) { model.endEditingSession(); dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Discarding leaves any previously saved local draft in place.")
        }
        .confirmationDialog(model.isSimulated ? "Simulate saving this page?" : "Save page on server?", isPresented: $confirmServerSave, titleVisibility: .visible) {
            Button(model.isSimulated ? "Simulate save" : "Save page on server") { Task { await model.saveToServer() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save ‘\(model.name)’ (page \(model.identity.pageID)) on \(model.identity.deploymentID). This updates the persisted page and may change content used by running displays. This action does not directly send a board command. A local snapshot is saved before the request.")
        }
        .confirmationDialog("Reload compared server page?", isPresented: $confirmRemoteReload, titleVisibility: .visible) {
            Button("Preserve local draft and reload", role: .destructive) { Task { await model.reloadComparedRemote() } }
            Button("Keep local work", role: .cancel) {}
        } message: {
            Text("Your current local work will be saved before replacing the editor. Undo history will be cleared so an old server revision cannot return.")
        }
        .task { await model.checkRecovery() }
    }

    @ViewBuilder private var serverSection: some View {
        Section("Stored page") {
            if let reason = model.serverSaveDisabledReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            Button(model.isSimulated ? "Simulate saving page" : "Save page on server…") {
                commitTextInput(); confirmServerSave = true
            }.disabled(!model.canSaveToServer).accessibilityIdentifier("savePageOnServer")
            Button("Fetch server page for comparison") {
                commitTextInput(); Task { await model.fetchRemoteComparison() }
            }.disabled(!model.canFetchRemote)
            DisclosureGroup("Current local document · select to copy") {
                Text(model.readOnlyDocumentText).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let comparison = model.remoteComparisonText {
                DisclosureGroup("Compared server document") {
                    Text(comparison).font(.caption.monospaced()).textSelection(.enabled)
                }
                Text("Your local work is still in the editor. Reloading preserves it in a local draft and adopts this server revision.").font(.footnote)
                Button("Reload compared page…") { commitTextInput(); confirmRemoteReload = true }
                    .disabled(model.editingFrozen || model.isSaving)
            }
            if model.editingFrozen { ProgressView("Preserving draft or contacting server…") }
        }
    }

    @ViewBuilder private var evaluationSection: some View {
        Section("Template evaluation") {
            Picker("Board for evaluation", selection: Binding(get: { model.selectedBoardID }, set: { model.chooseBoard($0) })) {
                Text("Choose a board").tag(String?.none)
                ForEach(model.boards) { board in Text(board.name).tag(Optional(board.id)) }
            }.disabled(model.editingFrozen)
            HStack {
                Button("Validate") { commitTextInput(); Task { await model.evaluate(preview: false) } }
                    .accessibilityIdentifier("validatePage")
                Spacer()
                Button("Preview") { commitTextInput(); Task { await model.evaluate(preview: true) } }
                    .accessibilityIdentifier("previewPage")
            }.disabled(!model.canEvaluate || model.isEvaluating)
            Text("Evaluation uses the current raw document and selected board. It does not update the page or send content to a display.")
                .font(.footnote).foregroundStyle(.secondary)
            if model.isEvaluating { ProgressView("Evaluating…") }
            if let result = model.validation {
                Text(result.isSimulated ? "Demo validation · simulated" : "Server validation")
                    .font(.caption).foregroundStyle(.secondary)
                Text(result.valid ? "No template syntax errors reported." : "Template syntax errors")
                ForEach(Array(result.errors.enumerated()), id: \.offset) { _, issue in
                    Text("Line \(issue.line), column \(issue.column): \(issue.message)").font(.footnote)
                }
            }
            if let result = model.preview {
                Text(result.isSimulated ? "Demo preview · simulated, expressions are not evaluated" : "Server-rendered text preview")
                    .font(.caption).foregroundStyle(.secondary)
                Text(result.lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                if let charset = result.charset { Text("Character set: \(charset)").font(.caption) }
                Text("Character warnings: \(result.charsetIssueCount) · Canvas warnings: \(result.canvasIssueCount)").font(.footnote)
                if result.hasLayers {
                    Text("This result includes visual layers. This text-only preview cannot display those layers; use the web preview to inspect them.")
                        .font(.footnote)
                }
                DisclosureGroup("Full evaluation result and warnings") {
                    Text(String(decoding: result.rawData, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
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
        guard view.markedTextRange == nil, !LosslessJSON.stringsEqual(view.text ?? "", text) else { return }
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
            if !LosslessJSON.stringsEqual(textView.text ?? "", parent.text) { textView.text = parent.text }
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            !text.contains("\n") && !text.contains("\r")
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
