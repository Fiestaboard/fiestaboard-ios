import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// Displays (B10): one card per display with a static preview of what it shows
/// now, its name, output, `type • rows×cols • colour` and only the badges the
/// server's facts imply. The detail leads with "Now showing" (animated).
struct DisplaysView<Playback: View>: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    let useOnHome: () -> Void
    @ViewBuilder let playback: (String) -> Playback

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if store.boards.isEmpty && !store.connecting {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: geometry.size.width > 700 ? 300 : 260), spacing: 16, alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(store.boards) { board in card(board) }
                    }
                    .padding(16)
                    .frame(maxWidth: 1250).frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Displays")
    }

    private func frame(for board: BoardSummary, model: DisplayModel) -> BoardFrame? {
        if let detail = store.board, detail.summary.id == board.id { return BoardFrame(detail) }
        return status.frames[board.id]
    }

    private func card(_ board: BoardSummary) -> some View {
        let model = status.model(for: board)
        return NavigationLink { detail(board) } label: {
            VStack(alignment: .leading, spacing: 8) {
                BoardThumbnail(frame: frame(for: board, model: model) ?? .empty(rows: model.rows, cols: model.cols), model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: 130)
                HStack(alignment: .firstTextBaseline) {
                    Text(board.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    if store.selectedBoardID == board.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("Selected")
                    }
                }
                Text("\(DisplayDescription.output(board.output)) · \(DisplayDescription.line(summary: board, model: model))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                badges(board)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("displayCard_\(board.id)")
    }

    @ViewBuilder private func badges(_ board: BoardSummary) -> some View {
        let list = DisplayBadge.make(summary: board, runtime: status.runtime[board.id])
        if !list.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(list, id: \.self) { badge in
                    Badge(text: badge.rawValue, systemImage: symbol(badge), tint: tint(badge), outline: badge == .fiestaPanel)
                        .accessibilityIdentifier("displayBadge_\(board.id)_\(badge.rawValue)")
                }
            }
        }
    }

    private func symbol(_ badge: DisplayBadge) -> String {
        switch badge {
        case .unavailable: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        case .fiestaPanel: "tv"
        case .connected: "checkmark.circle.fill"
        case .notConfigured: "gearshape"
        }
    }
    private func tint(_ badge: DisplayBadge) -> Color {
        switch badge {
        case .unavailable: .red
        case .paused: .orange
        case .fiestaPanel: .secondary
        case .connected: .green
        case .notConfigured: .secondary
        }
    }

    // MARK: detail

    private func detail(_ board: BoardSummary) -> some View {
        let model = status.model(for: board)
        let current = frame(for: board, model: model)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Now showing").font(.title3.weight(.semibold))
                // The animated board; the loading drum until the first frame, and a
                // paused display never spins.
                BoardFrameView(frame: current ?? .empty(rows: model.rows, cols: model.cols), model: model,
                               animated: status.display.boardAnimations != false,
                               loading: current == nil && !board.paused, flapStepMs: status.display.flapStepMs)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("displayNowShowing")
                if let page = status.activePageName(for: board.id) {
                    Label(page, systemImage: "doc.text").font(.body.weight(.semibold))
                }
                badges(board)
                VStack(spacing: 0) {
                    row("Output", DisplayDescription.output(board.output))
                    row("Size and colour", DisplayDescription.line(summary: board, model: model))
                    row("Schedule", board.scheduleEnabled ? "Follows the schedule" : "Off")
                    if let message = status.runtime[board.id]?.error { row("Problem", message) }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                VStack(spacing: 10) {
                    Button { store.selectBoard(board.id); useOnHome() } label: {
                        Label("Show on Home", systemImage: "house").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent).disabled(store.commandBusy)
                    NavigationLink { playback(board.id) } label: {
                        Label("Playback", systemImage: "play.rectangle").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered).accessibilityIdentifier("displayPlayback").disabled(store.commandBusy)
                }
            }
            .padding(16)
            .frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .navigationTitle(board.name)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// B32: no displays yet.
    private var emptyState: some View {
        VStack(spacing: 14) {
            BoardThumbnail(frame: .empty(rows: 6, cols: 22), model: .flap(rows: 6, cols: 22)).frame(maxWidth: 360)
            Text("No displays yet. Add one to start showing pages on it.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 16)
    }
}
