import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias LibraryState<Value> = SwiftUI.State<Value>

struct PageDetailView: View {
    let page: Page
    @ObservedObject var store: BoardStore
    let prepare: () -> Void
    /// The page as a board (the Pages list's thumbnail), shown first when there is one (P1).
    var thumbnail: AnyView? = nil
    @LibraryState private var editing = false
    @LibraryState private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var editable: Bool { page.supportsTemplateEditing || CapabilityPolicy.supportsFlexibleDocument(page) }
    private var boardName: String? { store.boards.first(where: { $0.id == store.selectedBoardID })?.name }

    // P1: plain words. No "read-only", "local draft", "native draft", "plugins are not rendered
    // here" or "deployment"; the board picture first, then what you can do with the page.
    var body: some View {
        Form {
            if let thumbnail {
                Section {
                    thumbnail.frame(maxWidth: 560).frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                if editable {
                    Button { editing = true } label: { Label(EditorStrings.navigationTitle, systemImage: "pencil") }
                        .disabled(store.status == nil || store.connecting)
                        .accessibilityIdentifier("editLocalDraft")
                } else {
                    Text(LibraryStrings.webOnly)
                    if let url = store.webEditorURL(pageID: page.id) {
                        Link("Open in web editor", destination: url).accessibilityIdentifier("openWebEditor")
                    }
                }
                Button { prepare() } label: { Label(LibraryStrings.showOn(boardName), systemImage: "rectangle.on.rectangle") }
                    .disabled(!store.canWrite)
                if let reason = store.boardActionDisabledReason {
                    Text(LibraryStrings.plain(reason)).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("showOnBoardDisabledReason")
                }
            }
            if let lines = page.template, lines.contains(where: { !$0.isEmpty }) {
                Section(LibraryStrings.textSection) {
                    Text(lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                }
            } else if let blocks = page.blockSummaries {
                Section(LibraryStrings.blocks(blocks.count)) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        if block.kind == "text", let text = block.text {
                            Text(text).font(.body.monospaced()).textSelection(.enabled)
                        } else {
                            Label(block.kind == "canvas" ? "Canvas" : block.kind.capitalized,
                                  systemImage: block.kind == "canvas" ? "paintpalette" : "square.dashed")
                        }
                    }
                }
            }
            if let library = store.pageLibrary {
                Section {
                    PageLibraryFeedback(library: library, store: store, showsCreationCapability: false)
                    Button("Delete page", role: .destructive) {
                        Task {
                            do { try await store.preparePageDeletion(id: page.id); confirmingDelete = true }
                            catch { /* The retained library state presents the error. */ }
                        }
                    }
                    .accessibilityIdentifier("deleteLibraryPage")
                    .disabled(store.pageDeletionDisabledReason(for: page) != nil)
                    // The same reason as Show's above is not repeated.
                    if let reason = store.pageDeletionDisabledReason(for: page), reason != store.boardActionDisabledReason {
                        Text(LibraryStrings.plain(reason)).font(.footnote).foregroundStyle(.secondary)
                    }
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
            Text("This removes the page for everyone. A display showing it moves to another page. This can't be undone.")
        }
        // iOS-E2 (B29): a navigation destination on iPad, a full-screen cover on a phone.
        .modifier(EditorPresentation(isPresented: $editing) { PageEditorLoader(pageID: page.id, store: store) })
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
                                if nameFocused { nameFocused = false }
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
                        Button("Create page") {
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
