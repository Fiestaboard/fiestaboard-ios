import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// Pages (B11): every page as a card with a static thumbnail rendered by the
/// server (`POST /pages/preview/batch`) and drawn as the selected display,
/// its type badge, and "Not on this display" when its grid differs.
struct PagesListView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    @ObservedObject var thumbnails: PageThumbnails
    let prepare: (String) -> Void
    @State private var search = ""
    @State private var creatingPage = false
    /// The page just created, waiting for the create sheet to close.
    @State private var createdPage: CreatedPage?
    /// The editor for it, shown like every editor (`EditorPresentation`, B29): pushed on
    /// regular width, a full-screen cover on compact.
    @State private var editorPageID: String?
    @State private var showingEditor = false

    struct CreatedPage: Identifiable, Hashable { let id: String }

    private var selected: BoardSummary? { store.boards.first { $0.id == store.selectedBoardID } }
    private var pages: [Page] {
        store.pages.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let library = store.pageLibrary { feedback(library) }
                    if store.pages.isEmpty && !store.connecting {
                        emptyState
                    } else {
                        let wide = geometry.size.width > 700
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 230 : 160), spacing: 14, alignment: .top)],
                                  alignment: .leading, spacing: 18) {
                            ForEach(pages) { page in card(page, wide: wide) }
                        }
                        if pages.isEmpty { Text("No pages match “\(search)”.").foregroundStyle(.secondary) }
                    }
                }
                .padding(16)
                .frame(maxWidth: 1250).frame(maxWidth: .infinity)
            }
            .refreshable { thumbnails.retryFailures(); await store.refreshLibrary().value }
        }
        .navigationTitle("Pages")
        .searchable(text: $search, prompt: "Find a page")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New page", systemImage: "plus") { creatingPage = true }
                    .accessibilityIdentifier("newLibraryPage")
                    .disabled(store.pageLibrary?.capability.canCreate != true)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Reload library", systemImage: "arrow.clockwise") {
                    thumbnails.retryFailures(); store.refreshLibrary()
                }.disabled(store.connecting)
            }
        }
        .sheet(isPresented: $creatingPage, onDismiss: openCreatedPage) {
            if let library = store.pageLibrary {
                NavigationStack {
                    CreateLibraryPageView(library: library, store: store, onCreated: { createdPage = CreatedPage(id: $0) })
                }
            }
        }
        .modifier(EditorPresentation(isPresented: $showingEditor) {
            if let id = editorPageID { PageEditorLoader(pageID: id, store: store) }
        })
        .onChange(of: showingEditor) { _, showing in if !showing { store.pageLibrary?.dismissCompletion() } }
        .onChange(of: store.connectionLabel) { _, _ in creatingPage = false; showingEditor = false }
    }

    /// The create sheet closed: open the new page's editor, if one was made.
    private func openCreatedPage() {
        guard let page = createdPage else { store.pageLibrary?.dismissCompletion(); return }
        createdPage = nil
        editorPageID = page.id; showingEditor = true
    }

    // MARK: cards

    private func card(_ page: Page, wide: Bool) -> some View {
        let geometry = PageGeometry(page)
        return NavigationLink {
            PageDetailView(page: page, store: store, prepare: { prepare(page.id) },
                           thumbnail: geometry == nil ? nil : AnyView(thumbnail(page, geometry: geometry)))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail(page, geometry: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: wide ? 140 : 100)
                Text(page.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                badges(page, geometry: geometry)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pageCard_\(page.id)")
        .onAppear { if geometry != nil { thumbnails.request(page, boardID: store.selectedBoardID) } }
    }

    @ViewBuilder private func badges(_ page: Page, geometry: PageGeometry?) -> some View {
        FlowLayout(spacing: 6) {
            Text(geometry?.label ?? (page.type == "flexible" ? "Flexible" : page.type.capitalized))
                .font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .foregroundStyle(.secondary)
            if let geometry, let summary = selected, !geometry.fits(status.model(for: summary)) {
                Text("Not on this display").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.14))).foregroundStyle(.orange)
                    .accessibilityIdentifier("notOnThisDisplay_\(page.id)")
            }
            if page.type == "single" || page.type == "composite" {
                Text("Edit in web").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().strokeBorder(.secondary.opacity(0.5))).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func thumbnail(_ page: Page, geometry: PageGeometry?) -> some View {
        if let geometry {
            let model = drawModel(geometry)
            let preview = thumbnails.preview(for: page, boardID: store.selectedBoardID)
            BoardThumbnail(frame: frame(page, geometry: geometry, model: model, preview: preview), model: model)
                .accessibilityIdentifier("pageThumbnail_\(page.id)")
                .accessibilityValue(preview == nil ? "loading" : "rendered")
        } else {
            RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                .overlay(Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.secondary))
                .accessibilityHidden(true)
        }
    }

    /// The selected display's model when the page fits it (LED pages as LED);
    /// otherwise a split-flap of the page's own grid.
    private func drawModel(_ geometry: PageGeometry) -> DisplayModel {
        if let summary = selected {
            let model = status.model(for: summary)
            if geometry.fits(model) { return model }
        }
        return .flap(rows: geometry.rows, cols: geometry.cols, deviceType: geometry.deviceType,
                     code62: geometry.deviceType == "flagship" ? .degree : .heart)
    }

    private func frame(_ page: Page, geometry: PageGeometry, model: DisplayModel, preview: PagePreview?) -> BoardFrame {
        PagePreviewFrame.make(preview, geometry: geometry, model: model)
    }

    // MARK: library feedback and empty state

    @ViewBuilder private func feedback(_ library: PageLibraryState) -> some View {
        LibraryFeedbackBox(library: library, store: store)
    }

    /// B32: no pages yet.
    private var emptyState: some View {
        VStack(spacing: 14) {
            BoardThumbnail(frame: .empty(rows: 6, cols: 22), model: .flap(rows: 6, cols: 22))
                .frame(maxWidth: 360)
            Text("No pages created yet.").font(.title3.weight(.semibold))
            Text("Create your first page to display on the board.").foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { creatingPage = true } label: { Label("Create your first page", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .disabled(store.pageLibrary?.capability.canCreate != true)
                .accessibilityIdentifier("createFirstPage")
            if let reason = store.pageManagementDisabledReason {
                Text(reason.message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

/// Library outcome / review prompts, only when there is something to say.
private struct LibraryFeedbackBox: View {
    @ObservedObject var library: PageLibraryState
    @ObservedObject var store: BoardStore
    var body: some View {
        if library.busy || library.phase.message != nil || library.needsReview {
            VStack(alignment: .leading, spacing: 8) {
                PageLibraryFeedback(library: library, store: store, showsCreationCapability: false)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
