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
    private var upNext: ScheduleUpNext? {
        guard let list = store.scheduleList, store.scheduleTarget?.boardID == store.selectedBoardID else { return nil }
        return ScheduleUpNext.next(list.schedules, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let upNext { scheduleCard(upNext) }
            if !others.isEmpty { otherDisplays }
        }
        .padding(.top, 10)
        // Read once the selected board has loaded (not while connecting).
        .task(id: "\(store.board?.summary.id ?? "-")|\(store.connecting)") {
            guard store.board != nil, !store.connecting else { return }
            now = Date()
            await store.refreshSchedules().value
        }
    }

    // MARK: schedule

    private func scheduleCard(_ next: ScheduleUpNext) -> some View {
        let name = store.pages.first { $0.id == next.pageID }?.name ?? "A scheduled page"
        let scheduleOn = store.scheduleList?.enabled ?? store.board?.summary.scheduleEnabled ?? false
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Next on the schedule")
            Button(action: openSchedule) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").font(.title3).foregroundStyle(.blue)
                        .frame(width: 40, height: 40).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(scheduleOn ? "Starts \(next.whenText(now: now))"
                                        : "Would start \(next.whenText(now: now)) · the schedule is off")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("homeUpNext")
        }
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
