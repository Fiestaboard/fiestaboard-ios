import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// The lower half of Home: what the schedule does next, and what every other
/// display is showing (static thumbnails; tap one to switch to it).
struct HomeCards: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    let wide: Bool
    let openSchedule: () -> Void
    @State private var now = Date()

    private var others: [BoardSummary] { store.boards.filter { $0.id != store.selectedBoardID } }
    private var upNext: HomeNextChange? {
        HomePresentation.make(detail: store.board, showing: status.nowShowing, silence: status.selectedSilence,
            pageNames: Dictionary(store.pages.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }), now: now).nextChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let next = HomePresentation.make(detail: store.board, showing: status.nowShowing, silence: status.selectedSilence,
                    pageNames: Dictionary(store.pages.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }), now: timeline.date).nextChange
                if let next { scheduleCard(next) }
            }
            if !others.isEmpty { otherDisplays }
        }
        .padding(.top, 10)
    }
    private func scheduleCard(_ next: HomeNextChange) -> some View {
        Button(action: openSchedule) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Up next")
                HStack(alignment: .top, spacing: 16) {
                    Text(next.at, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.title).font(.subheadline.weight(.medium))
                        if let page = next.pageName, page != next.title { Text("Then \(page)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("homeUpNext")
    }

    // MARK: other displays

    private var otherDisplays: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Other displays")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 220 : 150), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(others) { board in otherDisplay(board) }
            }
        }
        .accessibilityIdentifier("homeOtherDisplays")
    }

    private func otherDisplay(_ board: BoardSummary) -> some View {
        let model = status.model(for: board)
        let frame = status.frames[board.id] ?? .empty(rows: model.rows, cols: model.cols)
        let subtitle = board.paused ? "Paused" : (status.activePageName(for: board.id) ?? " ")
        return Button { store.selectBoard(board.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                // A fixed-height well so every caption lines up across the grid.
                BoardThumbnail(frame: frame, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: wide ? 130 : 96)
                Text(board.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.commandBusy || store.refreshing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(board.name), \(subtitle)")
        .accessibilityHint("Shows this display on Home")
        .accessibilityIdentifier("otherDisplay_\(board.id)")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }
}
