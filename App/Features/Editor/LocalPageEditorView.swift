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
        ScrollViewReader { proxy in
        Form {
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
                    .disabled(model.editingFrozen || !model.supportsLocalAuthoring).id("pageName")
            }
            if model.supportsFlexibleEditing {
                Section {
                    FlexibleWorkspaceView(model: model, isTextInputActive: $isTextInputActive) { issue in
                        let destination: String
                        if issue.key == "name" { destination = "pageName" }
                        else if issue.blockID == nil { destination = "flexiblePageOptions" }
                        else if issue.shapeIndex != nil { destination = "canvasShapeInspector" }
                        else { destination = "flexibleInspector" }
                        DispatchQueue.main.async { withAnimation { proxy.scrollTo(destination, anchor: .top) } }
                    }
                }
            } else if model.lines != nil {
                Section {
                    TemplateWorkspaceView(model: model, isTextInputActive: $isTextInputActive)
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
            Section("Draft status") {
                LabeledContent("Local", value: model.hasUnsavedChanges ? "Unsaved local changes" : "No unsaved local changes")
                LabeledContent("Server", value: model.serverSnapshotStatus)
                DisclosureGroup("Saving and evaluation help") {
                    Text("Save local draft keeps a recovery copy on this device. A confirmed server save updates stored page content. Evaluation uses the current document and selected display without updating stored content or sending to hardware.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.font(.footnote)
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
            }
        }
        .frame(maxWidth: 1120)
        .frame(maxWidth: .infinity)
        .presentationSizing(.page)
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { commitTextInput(); model.undo() }
                    .help(model.undoActionName.map { "Undo " + $0 } ?? "Undo")
                    .disabled(!model.canUndo || model.editingFrozen).keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { commitTextInput(); model.redo() }
                    .help(model.redoActionName.map { "Redo " + $0 } ?? "Redo")
                    .disabled(!model.canRedo || model.editingFrozen).keyboardShortcut("z", modifiers: [.command, .shift])
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
        Section(model.supportsFlexibleEditing ? "Flexible preview" : "Template evaluation") {
            Picker("Board for evaluation", selection: Binding(get: { model.selectedBoardID }, set: { model.chooseBoard($0) })) {
                Text("Choose a board").tag(String?.none)
                ForEach(model.boards) { board in Text(board.name).tag(Optional(board.id)) }
            }.disabled(model.editingFrozen).accessibilityIdentifier("evaluationBoardPicker")
            HStack {
                if !model.supportsFlexibleEditing {
                    Button("Validate") { commitTextInput(); Task { await model.evaluate(preview: false) } }
                        .accessibilityIdentifier("validatePage")
                }
                Spacer()
                Button("Preview") { commitTextInput(); Task { await model.evaluate(preview: true) } }
                    .accessibilityIdentifier("previewPage")
            }.disabled(!model.canEvaluate || model.isEvaluating)
            if model.isEvaluating { ProgressView("Evaluating…") }
            if let result = model.validation {
                Text(result.isSimulated ? "Demo validation · simulated" : "Server validation")
                    .font(.caption).foregroundStyle(.secondary)
                Text(result.valid ? "No template syntax errors reported." : "Template syntax errors")
                ForEach(Array(result.errors.enumerated()), id: \.offset) { _, issue in
                    Text("Line \(issue.line), column \(issue.column): \(issue.message)").font(.footnote)
                }
            }
            if let result = model.flexiblePreview {
                Text("Server preview · requested board: \(model.boards.first(where: { $0.id == model.selectedBoardID })?.name ?? "Unselected")")
                    .font(.caption).foregroundStyle(.secondary)
                switch result.surface {
                case .physical(let frame): PhysicalFrameView(frame: frame)
                case .unsupported: Text("This server uses an unsupported visual preview format.")
                case .legacy:
                    Text(result.lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                    if result.hasLayers { Text("Visual overlays are retained; inspect the full result or web preview.").font(.footnote) }
                }
                Text("Layout warnings: \(result.layoutIssueCount) · Canvas warnings: \(result.canvasIssueCount)").font(.footnote)
                ForEach(Array(result.layoutWarnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.footnote)
                }
                ForEach(Array(result.canvasWarnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "paintbrush").font(.footnote)
                }
                DisclosureGroup("Full preview and warnings") {
                    Text(String(decoding: result.rawData, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            if let result = model.preview {
                Text(result.isSimulated ? "Demo preview · simulated, expressions are not evaluated" : "Server preview")
                    .font(.caption).foregroundStyle(.secondary)
                switch result.surface {
                case .physical(let frame):
                    PhysicalFrameView(frame: frame)
                case .unsupported:
                    Text("This server uses a visual preview format this app does not support.")
                case .legacy:
                    Text(result.lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                    if result.hasLayers {
                        Text("This preview includes visual overlays. Use the web preview to inspect them.").font(.footnote)
                    }
                }
                if let charset = result.charset { Text("Character set: \(charset)").font(.caption) }
                Text("Character warnings: \(result.charsetIssueCount) · Canvas warnings: \(result.canvasIssueCount)").font(.footnote)
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

/// The backend supplies a complete opaque RGBA surface. Display its exact aspect
/// ratio with nearest-neighbor sampling; no character-grid geometry participates.
private struct PhysicalFrameView: View {
    let frame: PhysicalPreviewFrame
    private var image: CGImage? {
        guard let provider = CGDataProvider(data: frame.rgba as CFData) else { return nil }
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable().interpolation(.none)
                .aspectRatio(CGFloat(frame.width) / CGFloat(frame.height), contentMode: .fit)
                .accessibilityHidden(false)
                .accessibilityLabel("Server preview, \(frame.width) by \(frame.height) pixels")
                .accessibilityIdentifier("physicalPreview")
            Text("\(frame.width) × \(frame.height) pixels").font(.caption)
        } else {
            Text("The visual preview could not be displayed.")
        }
    }
}
