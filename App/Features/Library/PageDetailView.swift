import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias LibraryState<Value> = SwiftUI.State<Value>

struct PageDetailView: View {
    let page: Page
    @ObservedObject var store: BoardStore
    let prepare: () -> Void
    @LibraryState private var editing = false
    @LibraryState private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Page content · read-only") {
                if let lines = page.template {
                    Text(lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                } else {
                    Text("This page has no plain-text template projection. Use the web interface for its full preview.")
                }
                if page.template != nil {
                    Text("Template expressions are shown as source. Plugins are not rendered here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Page editing") {
                if !page.supportsTemplateEditing {
                    Text("Use the web editor to edit this document and preview it for each display.")
                } else {
                    Button("Edit local draft") { editing = true }
                        .disabled(store.status == nil || store.connecting)
                        .accessibilityIdentifier("editLocalDraft")
                    Text("Edit the full page document, keep a local draft, and explicitly evaluate or save supported changes when the deployment allows it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let library = store.pageLibrary {
                Section("Manage page") {
                    PageLibraryFeedback(library: library, store: store)
                    Button("Delete page", role: .destructive) {
                        Task {
                            do { try await store.preparePageDeletion(id: page.id); confirmingDelete = true }
                            catch { /* The retained library state presents the error. */ }
                        }
                    }
                    .accessibilityIdentifier("deleteLibraryPage")
                    .disabled(!library.canDelete || !page.supportsTemplateEditing)
                }
            }
            Section {
                Text("Destination: \(store.boards.first(where: { $0.id == store.selectedBoardID })?.name ?? "No selected board")")
                Button(store.status?.isDemo == true ? "Simulate showing on board" : "Show on board", action: prepare)
                    .disabled(!store.canWrite)
            }
        }
        .navigationTitle(page.name)
        .alert("Delete \(store.pageLibrary?.deletion?.page.name ?? page.name)?", isPresented: $confirmingDelete) {
            Button("Delete page", role: .destructive) {
                Task {
                    do { try await store.deleteLibraryPage(); dismiss() }
                    catch { /* Keep recovery visible; never retry a deletion automatically. */ }
                }
            }
            Button("Cancel", role: .cancel) { store.cancelPageDeletion() }
        } message: {
            Text("This removes the page from the server. References can prevent deletion; an active display may receive a replacement page. This cannot be undone here.")
        }
        .sheet(isPresented: $editing) {
            NavigationStack { LocalPageEditorLoader(pageID: page.id, store: store) }
        }
        .onChange(of: store.status == nil) { _, disconnected in if disconnected { editing = false } }
        .onChange(of: store.connectionLabel) { _, _ in editing = false }
    }
}

struct PageLibraryFeedback: View {
    @ObservedObject var library: PageLibraryState
    @ObservedObject var store: BoardStore
    var body: some View {
        if library.busy { ProgressView("Updating library…") }
        if let message = library.phase.message {
            Text(message).font(.callout).accessibilityIdentifier("pageLibraryOutcome")
        }
        if library.needsReview {
            Button("Read current library and displays") { Task { await store.reviewPageLibrary() } }
                .disabled(library.busy)
            if case .reviewed = library.phase {
                Button("I reviewed the library · allow a new request") { store.acknowledgePageLibraryReview() }
            }
        }
        if !library.capability.canCreate && !library.capability.canDelete {
            Text("Page creation and deletion are available in Demo, or on FiestaBoard 10.1.20 after enabling changes in Settings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct CreateLibraryPageView: View {
    @ObservedObject var library: PageLibraryState
    @ObservedObject var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @LibraryState private var createdID: String?
    var body: some View {
        Group {
            if let id = createdID {
                LocalPageEditorLoader(pageID: id, store: store)
            } else {
                Form {
                    Section("Page") {
                        TextField("New page name", text: $library.name)
                            .submitLabel(.done)
                            .onSubmit { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                            .disabled(library.busy)
                        Picker("Display format", selection: $library.isPanel) {
                            Text("Split-flap · 6 × 22").tag(false)
                            Text("LED panel").tag(true)
                        }.accessibilityIdentifier("pageFamilyPicker").disabled(library.busy)
                        if library.isPanel {
                            Stepper("Rows: \(library.rows)", value: $library.rows, in: 1...64).disabled(library.busy)
                            Stepper("Columns: \(library.columns)", value: $library.columns, in: 1...256).disabled(library.busy)
                            Text("Match the character grid configured for your LED display.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Button(library.capability.isSimulated ? "Create simulated page" : "Create page") {
                            Task {
                                do { createdID = try await store.createLibraryPage() }
                                catch { /* Input and recovery remain in the retained library state. */ }
                            }
                        }
                        .accessibilityIdentifier("createLibraryPage")
                        .disabled(!library.canCreate || library.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Creates a blank template and opens its editor. Creating a page does not select it on a display.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section { PageLibraryFeedback(library: library, store: store) }
                }
                .navigationTitle("New page")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
        }
        .interactiveDismissDisabled(library.busy)
    }
}
