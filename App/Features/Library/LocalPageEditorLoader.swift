import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardDocuments
import FiestaBoardEditorState

private typealias LoaderState<Value> = SwiftUI.State<Value>

/// All windows share one file actor so editors serialize access to local draft files.
@MainActor private enum LocalDraftResources {
    static let store = Result { LocalDraftStore(directory: try LocalDraftStore.defaultDirectory()) }
}

/// Advances only from an acknowledged page receipt or explicit scoped readback. The coordinator
/// separately decides when a fetched comparison becomes its editing baseline.
@MainActor private final class RemoteEditorContext {
    var value: PageEditingContext
    init(_ value: PageEditingContext) { self.value = value }
}

/// Owns one fetched snapshot and one editor for the entire sheet presentation.
/// Geometry changes re-evaluate the body without fetching again or replacing the draft.
@MainActor struct LocalPageEditorLoader: View {
    let pageID: String
    @ObservedObject var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @LoaderState private var started = false
    @LoaderState private var editor: LocalPageEditorView?
    @LoaderState private var failure: String?

    var body: some View {
        Group {
            if let editor {
                editor
            } else if let failure {
                ContentUnavailableView {
                    Label("Unable to open local draft", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Close") { dismiss() }
                }
                .navigationTitle("Local draft")
            } else {
                ProgressView("Fetching full page document…")
                    .navigationTitle("Local draft")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .task {
            guard !started else { return }
            started = true
            do {
                let snapshot = try await store.loadPageDocument(id: pageID)
                try Task.checkCancellation()
                // BoardStore validates the captured session generation before returning.
                guard store.status != nil else { return }
                let identity = DraftIdentity(deploymentID: snapshot.deployment.description, pageID: snapshot.id)
                let context = RemoteEditorContext(snapshot.context)
                let boardStore = store
                let actions = EditorRemoteActions(isSimulated: store.status?.isDemo == true, disabledReason: {
                    let access = boardStore.pageEditingAccess(context: context.value)
                    return access.canSave ? nil : access.reason
                }, save: { patch in
                    let capturedContext = context.value
                    let result = try await boardStore.savePage(patch: patch, context: capturedContext)
                    context.value = result.context
                    return EditorSaveResult(data: result.data, incompatibleReferenceCount: result.incompatibleReferenceCount)
                }, fetch: {
                    let capturedContext = context.value
                    let result = try await boardStore.readbackPage(context: capturedContext)
                    context.value = result.context
                    return result.data
                }, validate: { data, target in
                    let capturedContext = context.value
                    return try await boardStore.validatePage(requestData: data, context: capturedContext, target: target)
                }, preview: { data, target in
                    let capturedContext = context.value
                    return try await boardStore.previewPage(requestData: data, context: capturedContext, target: target)
                })
                let boards = store.boards.compactMap { board -> EditorBoardChoice? in
                    guard let target = try? BoardTarget(deployment: snapshot.deployment, boardID: board.id) else { return nil }
                    return EditorBoardChoice(name: board.name, target: target)
                }
                editor = try LocalPageEditorView(rawDocumentData: snapshot.data, identity: identity,
                                                draftStore: LocalDraftResources.store.get(), remote: actions, boards: boards)
            } catch is CancellationError {
                // A dismissed sheet must never reopen when its fetch completes.
            } catch {
                guard !Task.isCancelled, store.status != nil else { return }
                failure = "The full page could not be loaded or its document format is unsupported. Close this sheet and try again. \(error.localizedDescription)"
            }
        }
    }
}
