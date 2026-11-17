import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit
import FiestaBoardRender

private typealias PageState<Value> = SwiftUI.State<Value>

/// Native workspaces share the scoped model; the legacy form and recovery inventory are retired.
@MainActor struct PageEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LocalPageEditorModel
    @PageState private var isTextInputActive = false
    @PageState private var confirmClose = false
    @PageState private var confirmReload = false

    init(rawDocumentData: Data, identity: DraftIdentity, draftStore: LocalDraftStore,
         remote: EditorRemoteActions? = nil, boards: [EditorBoardChoice] = []) throws {
        let model = try LocalPageEditorModel(rawDocumentData: rawDocumentData,
            identity: identity, draftStore: draftStore, remote: remote, boards: boards, boardMemory: .standard)
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        if !model.supportsFlexibleEditing && model.lines != nil {
            EditorRoot(model: model)
        } else if model.supportsFlexibleEditing {
            flexibleEditor
        } else {
            ContentUnavailableView("Open this page on the web", systemImage: "safari",
                description: Text("This page uses a format the native editor cannot edit."))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { close() } } }
        }
    }

    private var flexibleEditor: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Page name", text: Binding(get: { model.name }, set: { model.setName($0) }))
                        .disabled(model.editingFrozen).id("pageName")
                    FlexibleWorkspaceView(model: model, isTextInputActive: $isTextInputActive) { issue in
                        let destination = issue.key == "name" ? "pageName" :
                            issue.blockID == nil ? "flexiblePageOptions" :
                            issue.shapeIndex != nil ? "canvasShapeInspector" : "flexibleInspector"
                        withAnimation { proxy.scrollTo(destination, anchor: .top) }
                    }
                    preview
                    if let reason = model.serverSaveDisabledReason { Text(reason).font(.footnote) }
                    if model.remoteStatus == .conflict || model.remoteStatus == .unknownOutcome {
                        Button("Check saved page") { commitTextInput(); Task { await model.fetchRemoteComparison() } }
                            .disabled(!model.canFetchRemote)
                    }
                    if model.remoteComparisonText != nil {
                        Text("The saved page is ready to reload.").font(.footnote)
                        Button("Reload saved page") { confirmReload = true }
                            .disabled(model.editingFrozen || model.isSaving)
                    }
                    if model.editingFrozen { ProgressView("Saving…") }
                    if let message = model.message { Text(message).foregroundStyle(.secondary) }
                }.padding().frame(maxWidth: 1120).frame(maxWidth: .infinity)
            }
            .navigationTitle("Edit page")
            .navigationBarBackButtonHidden(true)
            .preference(key: EditorIsOpenKey.self, value: true)
            .interactiveDismissDisabled(model.hasUnsavedChanges || model.isSaving || model.editingFrozen || isTextInputActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        commitTextInput()
                        if model.hasUnsavedChanges { confirmClose = true } else { close() }
                    }.disabled(model.isSaving || model.editingFrozen)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { commitTextInput() }
                        .accessibilityIdentifier("flexibleHideKeyboard")
                    Button("Undo", systemImage: "arrow.uturn.backward") { commitTextInput(); model.undo() }
                        .disabled(!model.canUndo || model.editingFrozen).keyboardShortcut("z", modifiers: .command)
                    Button("Redo", systemImage: "arrow.uturn.forward") { commitTextInput(); model.redo() }
                        .disabled(!model.canRedo || model.editingFrozen).keyboardShortcut("z", modifiers: [.command, .shift])
                    Button("Save") { commitTextInput(); Task { await model.saveToServer() } }
                        .disabled(!model.canSaveToServer).accessibilityIdentifier("savePageOnServer")
                }
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { close() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Reload saved page?", isPresented: $confirmReload, titleVisibility: .visible) {
                Button("Reload", role: .destructive) { Task { await model.reloadComparedRemote() } }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var preview: some View {
        Picker("Display", selection: Binding(get: { model.selectedBoardID }, set: { model.chooseBoard($0) })) {
            Text("Choose a display").tag(String?.none)
            ForEach(model.boards) { board in Text(board.name).tag(Optional(board.id)) }
        }.disabled(model.editingFrozen).accessibilityIdentifier("evaluationBoardPicker")
        Button("Preview") { commitTextInput(); Task { await model.evaluate(preview: true) } }
            .disabled(!model.canEvaluate).accessibilityIdentifier("previewPage")
        if let result = model.flexiblePreview {
            switch result.surface {
            case .physical(let frame): PhysicalFrameView(frame: frame)
            case .unsupported: Text("Open the web preview for this format.")
            case .legacy: Text(result.lines.joined(separator: "\n")).font(.body.monospaced())
            }
            ForEach(Array(result.layoutWarnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) }
            ForEach(Array(result.canvasWarnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) }
        }
    }

    private func close() { model.endEditingSession(); dismiss() }
    private func commitTextInput() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
