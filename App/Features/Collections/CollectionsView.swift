import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardEditorState

private typealias CollectionViewState<Value> = SwiftUI.State<Value>

@MainActor struct CollectionsView: View {
    @ObservedObject var store: BoardStore
    @CollectionViewState private var search = ""
    @CollectionViewState private var destination: CollectionDestination?
    private var filtered: [PageCollection] {
        store.collections.filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.id.localizedStandardContains(search) }
    }
    var body: some View {
        List {
            Section {
                Text("Collections choose among member pages. Saving changes stored content; selecting content for a board is a separate action.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.collectionsLoading { ProgressView("Loading collections…") }
            if let message = store.collectionMessage {
                Section { Text(message).foregroundStyle(.secondary); Button("Try again") { store.refreshCollections() } }
            }
            if filtered.isEmpty && !store.collectionsLoading {
                ContentUnavailableView(search.isEmpty ? "No collections" : "No matching collections", systemImage: "rectangle.stack",
                                       description: Text(search.isEmpty ? "Create a collection from pages in your library." : "Try another name or collection ID."))
            }
            ForEach(filtered) { collection in
                Button { destination = .init(collectionID: collection.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(collection.name).foregroundStyle(.primary)
                        Text("\(collection.pageIDs.count) pages · \(collection.selectionMode)").font(.subheadline).foregroundStyle(.secondary)
                        if collection.editProtocol != "collection-revision-v1" || !collection.supportsEditing {
                            Label("Read only", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .accessibilityHint("Open collection details and editor")
            }
        }
        .navigationTitle("Collections")
        .searchable(text: $search, prompt: "Name or collection ID")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create collection", systemImage: "plus") { destination = .init(collectionID: nil) }
                    .accessibilityIdentifier("createCollection")
            }
        }
        .refreshable { await store.refreshCollections().value }
        .task { await store.refreshCollections().value }
        .sheet(item: $destination, onDismiss: { store.refreshCollections() }) { item in
            NavigationStack { CollectionEditorLoader(store: store, collectionID: item.collectionID) }
        }
    }
}

private struct CollectionDestination: Identifiable {
    let id = UUID()
    let collectionID: String?
}

@MainActor private final class CollectionContextBridge {
    var context: CollectionEditingContext
    init(_ context: CollectionEditingContext) { self.context = context }
}

@MainActor enum CollectionDraftResources {
    static let archive = Result { CollectionDraftArchive(directory: try CollectionDraftArchive.defaultDirectory()) }
}

@MainActor private struct CollectionEditorLoader: View {
    @ObservedObject var store: BoardStore
    let collectionID: String?
    @Environment(\.dismiss) private var dismiss
    @CollectionViewState private var started = false
    @CollectionViewState private var model: CollectionEditorModel?
    @CollectionViewState private var pages: [Page] = []
    @CollectionViewState private var failure: String?
    var body: some View {
        Group {
            if let model { CollectionEditorView(model: model, pages: pages) }
            else if let failure {
                ContentUnavailableView {
                    Label("Unable to open collection", systemImage: "exclamationmark.triangle")
                } description: { Text(failure) } actions: { Button("Close") { dismiss() } }
            } else {
                ProgressView("Opening collection…")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .task {
            guard !started else { return }; started = true
            do {
                let snapshot = try await store.beginCollectionEditor(id: collectionID)
                try Task.checkCancellation()
                let bridge = CollectionContextBridge(snapshot.context)
                let boardStore = store
                let actions = CollectionEditorActions(save: { input, originalExpectedRevision in
                    // The model owns the original revision. A comparison advances only the bridge.
                    let receipt = try await boardStore.saveCollection(input, expectedRevision: originalExpectedRevision, context: bridge.context)
                    bridge.context = receipt.context
                    guard let collection = receipt.collection else { throw FiestaBoardError.unknownMutationOutcome }
                    return collection
                }, delete: { originalExpectedRevision in
                    try await boardStore.deleteCollection(expectedRevision: originalExpectedRevision, context: bridge.context)
                }, compare: {
                    do {
                        let receipt = try await boardStore.readbackCollection(context: bridge.context)
                        bridge.context = receipt.context
                        return receipt.collection
                    } catch FiestaBoardError.rejected(status: 404) { return nil }
                })
                pages = snapshot.pages.filter { $0.type != "collection" }
                model = CollectionEditorModel(identity: CollectionDraftIdentity(scope: snapshot.scope, collectionID: snapshot.context.collectionID), collection: snapshot.collection,
                    canSave: snapshot.canSave, isSimulated: snapshot.isDemo, archive: try CollectionDraftResources.archive.get(), actions: actions)
            } catch is CancellationError {
            } catch { failure = error.localizedDescription }
        }
    }
}
