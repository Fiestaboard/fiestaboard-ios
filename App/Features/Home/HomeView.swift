import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

/// Home: the selected display's name, the "what's happening" row, then the
/// board itself — the largest element on screen (B33). Below it: the outcome
/// of the last action, quick actions, what the schedule does next and what
/// the other displays show. Server/account details live in Settings.
struct HomeView<ChangePage: View, Controls: View>: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    let compose: () -> Void
    let preparePage: (String) -> Void
    let prepareRestore: () -> Void
    let openSettings: () -> Void
    @State private var showOverrideReason = false
    let openSchedule: () -> Void
    @ViewBuilder let changePage: () -> ChangePage
    @ViewBuilder let controls: () -> Controls

    private var summary: BoardSummary? { store.boards.first { $0.id == store.selectedBoardID } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let summary {
                        header(summary)
                        board(summary, height: geometry.size.height)
                        if let face = status.outOfSync {
                            OutOfSyncBanner(face: face, summary: summary, store: store, status: status, restore: prepareRestore)
                        }
                        outcome
                        actions(wide: geometry.size.width > 760)
                        changesNote
                        HomeCards(store: store, status: status, wide: geometry.size.width > 760,
                                  openSchedule: openSchedule)
                    } else if store.boards.isEmpty && !store.connecting {
                        emptyBoard
                    } else {
                        outcome
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: 1250).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("FiestaBoard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { displayMenu }
            ToolbarItem(placement: .primaryAction) {
                Button { store.refresh() } label: { Label("Refresh output", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing || store.commandBusy)
            }
        }
    }

    private var displayMenu: some View {
        Menu {
            Picker("Display", selection: Binding(get: { store.selectedBoardID ?? "" }, set: { store.selectBoard($0) })) {
                ForEach(store.boards) { Text($0.name).tag($0.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(summary?.name ?? "FiestaBoard").font(.headline)
                if store.boards.count > 1 { Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
            }
            .foregroundStyle(.primary)
        }
        .disabled(store.commandBusy || store.refreshing || store.boards.count < 2)
        .accessibilityIdentifier("homeDisplayPicker")
    }

    // MARK: status row

    private func header(_ summary: BoardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let now = status.nowShowing {
                nowShowingName(now)
                FlowBadges {
                    if case .override = now.mode { overrideBadge(now) } else {
                        Badge(text: now.mode.label, systemImage: now.mode == .manual ? "hand.tap" : "calendar",
                              tint: modeTint(now.mode)).accessibilityIdentifier("modeBadge")
                    }
                    if now.collection { Badge(text: "Collection", systemImage: "rectangle.stack", tint: .secondary, outline: true).accessibilityIdentifier("collectionBadge") }
                    if now.silence { Badge(text: "Silence mode active", systemImage: "moon.fill", tint: .indigo).accessibilityIdentifier("silenceBadge") }
                    if now.paused { Badge(text: "Paused", systemImage: "pause.circle.fill", tint: .orange).accessibilityIdentifier("pausedBadge") }
                }
            } else {
                Text(" ").font(.title3.weight(.semibold)).redacted(reason: .placeholder)
            }
        }
    }

    /// Why the override's ✕ can't cancel it now, or nil when it can (P5, B8).
    private var overrideCancelReason: String? {
        if !status.canClearOverride { return "This connection can't cancel an override. Use the web app." }
        switch store.boardActionDisabledReason {
        case .changesDisabled?: return "Sign in to control this display."
        case .unsupportedOperation?: return "This server version can't be changed from the app yet."
        case .readbackRequired?: return "Refresh to see the board before making another change."
        default: return store.canWrite ? nil : "Wait for the board, then try again."
        }
    }

    /// "Override: Nm remaining" with its ✕ (B8, `DELETE /settings/temporary-override`). With
    /// permission denied, the ✕ stays dimmed and explains why.
    private func overrideBadge(_ now: NowShowing) -> some View {
        let reason = overrideCancelReason
        return HStack(spacing: 4) {
            Label(now.mode.label, systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(now.mode.label)
                .accessibilityIdentifier("modeBadge")
            Button {
                if reason == nil { Task { await status.clearTemporaryOverride() } } else { showOverrideReason = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(reason == nil ? 1 : 0.35)
            .accessibilityLabel("Cancel override")
            .accessibilityValue(reason == nil ? "" : "Unavailable")
            .accessibilityHint(reason ?? "Returns the board to its schedule")
            .accessibilityIdentifier("overrideCancel")
            .popover(isPresented: $showOverrideReason, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reason ?? "").font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("overrideCancelReason")

                }
                .padding(14).frame(idealWidth: 260, maxWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.purple)
        .padding(.leading, 9).padding(.trailing, 2).padding(.vertical, 1)
        .background(Capsule().fill(Color.purple.opacity(0.14)))
    }

    @ViewBuilder private func nowShowingName(_ now: NowShowing) -> some View {
        let label = Text(now.name).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
        if let id = now.pageID, let page = store.pages.first(where: { $0.id == id }) {
            NavigationLink { PageDetailView(page: page, store: store, prepare: { preparePage(page.id) }) } label: {
                HStack(spacing: 4) { label; Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nowShowingName")
            .accessibilityLabel(now.name)
            .accessibilityHint("Opens the page")
        } else {
            label.foregroundStyle(now.scheduleGap ? .orange : .primary)
                .accessibilityIdentifier("nowShowingName")
        }
    }

    private func modeTint(_ mode: NowShowing.Mode) -> Color {
        switch mode { case .manual: .secondary; case .schedule: .blue; case .override: .purple }
    }

    // MARK: board

    @ViewBuilder private func board(_ summary: BoardSummary, height: CGFloat) -> some View {
        let model = status.model(for: summary)
        let animated = status.display.boardAnimations != false
        Group {
            if let detail = store.board, detail.summary.id == summary.id {
                BoardOutputView(board: detail, model: model, animated: animated, flapStepMs: status.display.flapStepMs)
            } else {
                // First open: the loading drum until the first frame; a paused board never spins.
                BoardFrameView(frame: .empty(rows: model.rows, cols: model.cols), model: model, animated: false,
                               loading: !summary.paused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: max(220, height * 0.62))
        .accessibilityIdentifier("homeBoard")
        .transaction { $0.animation = nil }
    }

    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoardFrameView(frame: .empty(rows: 6, cols: 22), model: .flap(rows: 6, cols: 22), animated: false)
                .accessibilityIdentifier("homeBoard")
            Text("No displays yet. Add one to start showing pages on it.").foregroundStyle(.secondary)
        }
    }

    // MARK: outcome and actions

    @ViewBuilder private var outcome: some View {
        if let message = store.message {
            Text(message).font(.callout).accessibilityIdentifier("actionOutcome")
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        if status.overrideClearFailed {
            Text("Couldn't cancel the override. Refresh and try again.").font(.callout).accessibilityIdentifier("overrideCancelFailed")
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        if store.commandBusy || store.refreshing {
            ProgressView(store.commandBusy ? "Waiting for the board…" : "Refreshing…").font(.callout)
        }
    }

    /// Why Change page / Compose are greyed out, in plain words, with the fix.
    @ViewBuilder private var changesNote: some View {
        switch store.boardActionDisabledReason {
        case .changesDisabled?:
            EmptyView() // W4: shown as a card beside Board controls (`actions`).
        case .unsupportedOperation?:
            Label("This server version can't be changed from the app yet. Use the web app to change the board.",
                  systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        case .readbackRequired?:
            Label("Refresh to see the board before making another change.", systemImage: "arrow.clockwise")
                .font(.callout).foregroundStyle(.orange)
        default: EmptyView()
        }
    }

    /// Three equal quick actions in one row (icon over label), so the board
    /// keeps the screen and the lower half has room for the cards.
    /// While changes from the app are off (or the server can't take them), Change page and Compose
    /// are not shown greyed out: the plain permission line under the row says why (P1).
    private var writeActionsHidden: Bool {
        switch store.boardActionDisabledReason {
        case .changesDisabled?, .unsupportedOperation?: return true
        default: return false
        }
    }

    private func actions(wide: Bool) -> some View {
        HStack(spacing: 10) {
            if !writeActionsHidden {
                NavigationLink { changePage() } label: { QuickAction(title: "Change page", systemImage: "rectangle.stack", prominent: true) }
                    .disabled(!store.canWrite).accessibilityIdentifier("changePage")
                Button(action: compose) { QuickAction(title: "Compose text", systemImage: "square.and.pencil") }
                    .disabled(!store.canWrite)
            }
            NavigationLink { controls() } label: { QuickAction(title: "Board controls", systemImage: "slider.horizontal.3") }
                .accessibilityIdentifier("boardControlsEntry")
                .frame(maxWidth: writeActionsHidden ? (wide ? 200 : 150) : .infinity)
            // W4: with changes off, the reason and its fix fill the row as a card of the same
            // height, instead of a lone half-width tile over a line of grey text.
            if writeActionsHidden { Spacer(minLength: 0) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: wide ? 640 : .infinity, alignment: .leading)
    }


}

/// One quick-action tile: icon above a one-line label, full tile tappable.
struct QuickAction: View {
    let title: String
    let systemImage: String
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title3.weight(.semibold)).frame(height: 26)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .foregroundStyle(prominent && enabled ? Color.white : (enabled ? Color.orange : Color.secondary))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(prominent && enabled ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color(.secondarySystemBackground))))
        .opacity(enabled ? 1 : 0.6)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

struct Badge: View {
    let text: String
    let systemImage: String
    let tint: Color
    var outline = false
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(outline ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .background(Capsule().fill(outline ? AnyShapeStyle(.clear) : AnyShapeStyle(tint.opacity(0.14))))
            .overlay(Capsule().strokeBorder(outline ? AnyShapeStyle(.secondary.opacity(0.5)) : AnyShapeStyle(.clear)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// Badges wrap onto a second line on narrow screens.
struct FlowBadges<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { FlowLayout(spacing: 6) { content() } }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}
