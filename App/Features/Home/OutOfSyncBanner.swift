import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// B9: what another app put on the board, and what to do about it (web
/// `board-out-of-sync-banner.tsx`). Restore goes through the usual review sheet.
struct OutOfSyncBanner: View {
    let face: OutOfSync
    let summary: BoardSummary
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    let restore: () -> Void
    @State private var saving = false
    @State private var saved: (id: String, name: String, grid: [[Int]])?
    @State private var failed = false

    var body: some View {
        let time = OutOfSync.displayTime(face.detectedAt)
        let live = face.face != .kept
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(face.title(time: time)).font(.subheadline.weight(.semibold))
                    Text(face.detail(time: time)).font(.subheadline).foregroundStyle(.secondary)
                    if live && summary.paused {
                        Text(OutOfSync.holdPaused).font(.footnote).foregroundStyle(.secondary)
                    }
                    if failed { Text("Couldn't save the board as a page. Try again.").font(.footnote).foregroundStyle(.red) }
                }
            } icon: {
                Image(systemName: live ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(live ? .orange : .blue)
            }
            HStack(spacing: 10) {
                if face.offersRestore {
                    Button { restore() } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered).disabled(!store.canWrite)
                        .accessibilityIdentifier("outOfSyncRestore")
                }
                if face.offersSave, let grid = face.grid {
                    if let saved, saved.grid == grid {
                        Label("Saved as “\(saved.name)”", systemImage: "checkmark").font(.footnote).lineLimit(1)
                        if let page = store.pages.first(where: { $0.id == saved.id }) {
                            NavigationLink("Open page") { PageDetailView(page: page, store: store, prepare: {}) }.font(.footnote)
                        }
                    } else {
                        Button { save(grid) } label: { Label("Save as page", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.bordered)
                            .disabled(saving || store.pageLibrary?.capability.canCreate != true)
                            .accessibilityIdentifier("outOfSyncSave")
                    }
                }
                if face.offersDismiss {
                    // A server write (DELETE /board/external-frame): only when changes are on.
                    Button("Dismiss") { Task { await status.dismissExternalFrame() } }
                        .disabled(!store.canWrite)
                        .accessibilityIdentifier("outOfSyncDismiss")
                }
            }
            .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((live ? Color.orange : Color.blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("outOfSyncBanner_\(face.face.rawValue)")
    }

    private func save(_ grid: [[Int]]) {
        let model = status.model(for: summary)
        let family: PageCreationFamily = summary.deviceType == "flagship" && summary.rows == 6 && summary.cols == 22
            ? .flagship : .panel(rows: summary.rows, cols: summary.cols)
        let name = BoardTemplate.pageName()
        saving = true; failed = false
        Task {
            defer { saving = false }
            do {
                let id = try await store.createLibraryPage(name: name, template: BoardTemplate.rows(grid, code62: model.code62),
                                                           family: family)
                saved = (id, name, grid)
            } catch { failed = true }
        }
    }
}
