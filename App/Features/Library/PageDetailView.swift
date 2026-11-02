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
                    LabeledContent("Content type", value: page.type)
                    if let format = page.deviceType { LabeledContent("Display format", value: format) }
                    if let blocks = page.blockSummaries {
                        Text("\(blocks.count) content blocks").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            if block.kind == "text", let text = block.text {
                                Text(text).font(.body.monospaced()).textSelection(.enabled)
                            } else {
                                Label(block.kind == "canvas" ? "Canvas" : block.kind.capitalized,
                                    systemImage: block.kind == "canvas" ? "paintpalette" : "square.dashed")
                            }
                        }
                        Text("Content summary · expressions and visual blocks are not rendered.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if page.template != nil {
                    Text("Template expressions are shown as source. Plugins are not rendered here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Page editing") {
                if !page.supportsTemplateEditing && !CapabilityPolicy.supportsFlexibleDocument(page) {
                    Text("This document cannot be edited in this native draft. Open the web editor for its full content and display previews.")
                    if let url = store.webEditorURL(pageID: page.id) {
                        Link("Open in web editor", destination: url).accessibilityIdentifier("openWebEditor")
                    }
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
                    PageLibraryFeedback(library: library, store: store, showsCreationCapability: false)
                    Button("Delete page", role: .destructive) {
                        Task {
                            do { try await store.preparePageDeletion(id: page.id); confirmingDelete = true }
                            catch { /* The retained library state presents the error. */ }
                        }
                    }
                    .accessibilityIdentifier("deleteLibraryPage")
                    .disabled(store.pageDeletionDisabledReason(for: page) != nil)
                    if let reason = store.pageDeletionDisabledReason(for: page) {
                        Text(reason.message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("Destination: \(store.boards.first(where: { $0.id == store.selectedBoardID })?.name ?? "No selected board")")
                Button(store.status?.isDemo == true ? "Simulate showing on board" : "Show on board", action: prepare)
                    .disabled(!store.canWrite)
                if let reason = store.boardActionDisabledReason {
                    Text(reason.message).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("showOnBoardDisabledReason")
                }
            }
        }
        .frame(maxWidth: 1000).frame(maxWidth: .infinity)
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
            // iOS-E1 (D1 gate): page-sized on iPad so the editor's stage sits beside the document.
            NavigationStack { LocalPageEditorLoader(pageID: page.id, store: store) }
                .presentationSizing(.page)
        }
        .onChange(of: store.status == nil) { _, disconnected in if disconnected { editing = false } }
        .onChange(of: store.connectionLabel) { _, _ in editing = false }
    }
}

struct PageLibraryFeedback: View {
    @ObservedObject var library: PageLibraryState
    @ObservedObject var store: BoardStore
    var showsCreationCapability = true
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
        if showsCreationCapability, let reason = store.pageManagementDisabledReason {
            Text(reason.message)
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct CreateLibraryPageView: View {
    @ObservedObject var library: PageLibraryState
    @ObservedObject var store: BoardStore
    /// Called with the new page's id; the Pages list then opens its editor the
    /// way every editor opens (B29), after this sheet has gone.
    var onCreated: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    var body: some View {
        Group {
                Form {
                    Section("Page") {
                        TextField("New page name", text: $library.name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .disabled(library.busy)
                            // iPad: the keyboard's own Hide key hides the keyboard but leaves
                            // the field first responder, so the next tap (the format menu)
                            // brought the keyboard back. Resign with it (E1 open issue 5).
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                                nameFocused = false
                            }
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
                                do { let id = try await store.createLibraryPage(); onCreated(id); dismiss() }
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
        .interactiveDismissDisabled(library.busy)
    }
}
