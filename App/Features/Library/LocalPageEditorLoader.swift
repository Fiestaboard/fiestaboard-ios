import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardDocuments

private typealias LoaderState<Value> = SwiftUI.State<Value>

/// All windows share one file actor so editors serialize access to local draft files.
@MainActor private enum LocalDraftResources {
    static let store = Result { LocalDraftStore(directory: try LocalDraftStore.defaultDirectory()) }
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
                editor = try LocalPageEditorView(rawDocumentData: snapshot.data, identity: identity,
                                                draftStore: LocalDraftResources.store.get())
            } catch is CancellationError {
                // A dismissed sheet must never reopen when its fetch completes.
            } catch {
                guard !Task.isCancelled, store.status != nil else { return }
                failure = "The full page could not be loaded or its document format is unsupported. Close this sheet and try again. \(error.localizedDescription)"
            }
        }
    }
}
