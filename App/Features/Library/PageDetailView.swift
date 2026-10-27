import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias LibraryState<Value> = SwiftUI.State<Value>

struct PageDetailView: View {
    let page: Page
    @ObservedObject var store: BoardStore
    let prepare: () -> Void
    @LibraryState private var editing = false

    var body: some View {
        Form {
            Section("Server template · read-only") {
                if let lines = page.template {
                    Text(lines.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                } else {
                    Text("This page has no plain-text template projection. Use the web interface for its full preview.")
                }
                Text("Template expressions are shown as source. Plugins are not rendered here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Page editing") {
                Button("Edit local draft") { editing = true }
                    .disabled(store.status == nil || store.connecting)
                    .accessibilityIdentifier("editLocalDraft")
                Text("Edit the full page document, keep a local draft, and explicitly evaluate or save supported changes when the deployment allows it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Destination: \(store.boards.first(where: { $0.id == store.selectedBoardID })?.name ?? "No selected board")")
                Button(store.status?.isDemo == true ? "Simulate showing on board" : "Show on board", action: prepare)
                    .disabled(!store.canWrite)
            }
        }
        .navigationTitle(page.name)
        .sheet(isPresented: $editing) {
            NavigationStack { LocalPageEditorLoader(pageID: page.id, store: store) }
        }
        .onChange(of: store.status == nil) { _, disconnected in if disconnected { editing = false } }
        .onChange(of: store.connectionLabel) { _, _ in editing = false }
    }
}
