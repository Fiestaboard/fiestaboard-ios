import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardDocuments
import FiestaBoardEditorState

private typealias LoaderState<Value> = SwiftUI.State<Value>

/// All windows share one file actor so editors serialize access to local draft files.
@MainActor enum LocalDraftResources {
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
                let identity = DraftIdentity(deploymentID: snapshot.scope.deployment.description, installationID: snapshot.scope.installationID, connectionID: snapshot.scope.connectionID, pageID: snapshot.id)
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
                }, previewFlexible: { data, target in
                    let capturedContext = context.value
                    return try await boardStore.previewFlexiblePage(requestData: data, context: capturedContext, target: target)
                })
                let boards = store.boards.compactMap { board -> EditorBoardChoice? in
                    guard let target = try? BoardTarget(deployment: snapshot.deployment, boardID: board.id) else { return nil }
                    return EditorBoardChoice(name: board.name, target: target, rows: board.rows, cols: board.cols,
                                             deviceType: board.deviceType, deviceModel: board.deviceModel, charset: board.charset)
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

/// Recovery is deliberately an inventory and export route. It never installs an old
/// revision as the baseline of an editor belonging to another connection.
@MainActor struct LocalDraftRecoveryView: View {
    @LoaderState private var entries: [DraftRecoveryEntry] = []
    @LoaderState private var pageFailure: String?
    @LoaderState private var collectionFailure: String?
    @LoaderState private var collectionEntries: [CollectionDraftRecoveryEntry] = []
    @LoaderState private var loaded = false
    var body: some View {
        List {
            Section {
                Text("Drafts from previous sign-ins and older app versions stay on this device. Inspect and export their original files here. Exported content can be recovered locally; no server changes are made.")
            }
            if !loaded { ProgressView("Reading local draft files…") }
            if loaded && pageFailure == nil && collectionFailure == nil && entries.isEmpty && collectionEntries.isEmpty {
                Text("No saved local drafts.").foregroundStyle(.secondary)
            }
            Section("Pages") {
                if let pageFailure { Text("Page drafts could not be listed. " + pageFailure) }
                ForEach(entries) { entry in
                    NavigationLink {
                        List {
                            if let snapshot = entry.snapshot {
                                Section("Saved draft") {
                                    LabeledContent("Server", value: snapshot.identity.deploymentID)
                                    LabeledContent("Page", value: snapshot.identity.pageID)
                                    LabeledContent("Scope", value: snapshot.identity.isScoped ? "Connection-scoped draft" : "Unassigned legacy draft")
                                    if let installation = snapshot.identity.installationID { LabeledContent("Installation", value: installation) }
                                    LabeledContent("Saved", value: snapshot.savedAt.formatted())
                                }
                                Section("Local content") {
                                    Text(String(decoding: snapshot.documentData, as: UTF8.self))
                                        .font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                            if let reason = entry.corruptionReason {
                                Section("File needs recovery") {
                                    Text("The saved file could not be read as a valid draft. Its original bytes are preserved.")
                                    Text(reason).font(.caption).textSelection(.enabled)
                                }
                            }
                            Section {
                                LabeledContent("File", value: entry.fileURL.lastPathComponent)
                                ShareLink("Export original draft file", item: entry.fileURL)
                                Text("The original export includes the saved content and its historical baseline for local recovery. It is never applied to the active server session.").font(.footnote)
                            }
                        }
                        .navigationTitle("Draft details")
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.snapshot?.identity.pageID ?? "Damaged draft")
                            Text(entry.snapshot?.identity.isScoped == true ? "Connection draft" : "Unassigned or damaged draft")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Collections") {
                if let collectionFailure { Text("Collection drafts could not be listed. " + collectionFailure) }
                ForEach(collectionEntries) { entry in
                    NavigationLink {
                        CollectionDraftRecoveryDetails(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collectionRecoveryTitle(entry)).lineLimit(2)
                            Text(entry.classification.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text(entry.fileURL.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Draft recovery & export")
        .task {
            do { entries = try await LocalDraftResources.store.get().recoveryInventory() }
            catch { pageFailure = error.localizedDescription }
            do { collectionEntries = try CollectionDraftResources.archive.get().recoveryInventory() }
            catch { collectionFailure = error.localizedDescription }
            loaded = true
        }
    }
}

private func collectionRecoveryTitle(_ entry: CollectionDraftRecoveryEntry) -> String {
    guard let saved = entry.checkpoint else { return "Collection recovery file" }
    if !saved.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return saved.draft.name }
    return saved.collectionID ?? "New collection draft"
}

@MainActor private struct CollectionDraftRecoveryDetails: View {
    let entry: CollectionDraftRecoveryEntry
    var body: some View {
        List {
            Section("Original collection archive") {
                Text(entry.classification.rawValue)
                Text(entry.reason)
                Text("This file is historical recovery material. It is not adopted by the active sign-in and cannot send changes from this screen.")
            }
            if let saved = entry.checkpoint {
                Section("Saved draft evidence") {
                    LabeledContent("Name", value: saved.draft.name)
                    LabeledContent("Collection", value: saved.collectionID ?? "New collection")
                    LabeledContent("Server", value: saved.deploymentID)
                    if let identity = saved.identity {
                        LabeledContent("Saved installation", value: identity.installationID)
                        LabeledContent("Saved connection", value: identity.connectionID.uuidString)
                    }
                    LabeledContent("Saved", value: saved.savedAt.formatted())
                    LabeledContent("Status", value: saved.status.rawValue)
                    LabeledContent("Original revision", value: saved.baseline?.revision ?? "No stored baseline")
                    LabeledContent("Source editing support", value: saved.sourceSupportsEditing ? "Supported when saved" : "Read only when saved")
                    LabeledContent("Time interval text", value: saved.draft.intervalText)
                }
            }
            Section {
                LabeledContent("Original file", value: entry.fileURL.lastPathComponent)
                ShareLink("Export original collection draft file", item: entry.fileURL)
                    .accessibilityIdentifier("exportOriginalCollectionDraft")
                Text("Exports the original file, including its saved content and historical baseline. No server changes are made.").font(.footnote)
            }
        }
        .navigationTitle("Collection draft details")
    }
}
