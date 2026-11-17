import SwiftUI
import UIKit
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardRender

struct HomeView<Controls: View>: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    @ObservedObject var thumbnails: PageThumbnails
    let compose: () -> Void
    let preparePage: (String) -> Void
    let prepareRestore: () -> Void
    let openSettings: () -> Void
    let openSchedule: () -> Void
    @ViewBuilder let controls: () -> Controls
    @Environment(\.colorScheme) private var appearance
    @State private var changingPage = false
    @State private var editing = false
    @State private var previewedPageID: String?
    @State private var successToast = false
    private var previewPage: Page? { store.pages.first { $0.id == previewedPageID } }
    private var selectedPreview: PagePreview? { previewPage.flatMap { thumbnails.preview(for: $0, boardID: store.selectedBoardID) } }
    private var previewReady: Bool { selectedPreview?.available == true }
    private var previewLabel: String { previewReady ? "Preview · Not sent yet" : selectedPreview?.available == false ? "Preview unavailable" : "Loading preview…" }
    private var summary: BoardSummary? { store.boards.first { $0.id == store.selectedBoardID } }
    private var selectedPage: Page? { status.nowShowing?.pageID.flatMap { id in store.pages.first { $0.id == id } } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary {
                        if previewedPageID != nil {
                            Label(previewLabel, systemImage: "eye").font(.caption).accessibilityIdentifier("homePagePreviewLabel")
                        }
                        board(summary, height: geometry.size.height)
                            .contextMenu {
                                Button("Change Page", systemImage: "rectangle.stack") { changingPage = true }
                                    .disabled(!status.canSelectHomePage(timed: false))
                                Button("Edit page", systemImage: "pencil") { editing = true }
                                    .disabled((selectedPage.map { !($0.supportsTemplateEditing || CapabilityPolicy.supportsFlexibleDocument($0)) } ?? true) || store.status == nil || store.connecting)
                            }
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let presentation = homePresentation(now: timeline.date)
                            HomeStatusSummary(presentation: presentation, displayName: summary.name,
                                pageName: previewReady ? (previewPage?.name ?? "") : (status.nowShowing?.name ?? "No page selected"), previewing: previewReady, canCancel: status.canClearOverride,
                                cancel: { Task { await status.clearTemporaryOverride() } })
                            if let banner = presentation.banner { statusBanner(banner) }
                        }
                        if let face = status.outOfSync {
                            OutOfSyncBanner(face: face, summary: summary, store: store, status: status, restore: prepareRestore)
                        }
                        if let outcome = status.homeControlOutcome, outcome != .pageSelected && outcome != .overrideCanceled && outcome != .overrideRestored {
                            Label(outcome.message, systemImage: outcome == .pageSelected || outcome == .overrideCanceled ? "checkmark.circle" : "info.circle")
                                .font(.callout).accessibilityIdentifier("homeControlOutcome")
                        }
                        if let message = store.message, !successfulHomeOutcome {
                            Text(message).font(.callout).accessibilityIdentifier("actionOutcome")
                        }
                        if status.homeControlNeedsReadback {
                            Button("Refresh display") { Task { await status.refreshHomeControlState() } }
                        }
                        Button { changingPage = true } label: { Text("Change Page").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                            .disabled(!status.canSelectHomePage(timed: false)).accessibilityIdentifier("changePage")
                        HomeCards(store: store, status: status, wide: geometry.size.width > 760, openSchedule: openSchedule)
                        NavigationLink { controls() } label: { Label("Display controls", systemImage: "slider.horizontal.3") }
                            .accessibilityIdentifier("boardControlsEntry")
                    } else if !store.connecting {
                        ContentUnavailableView("No displays yet", systemImage: "rectangle.on.rectangle",
                            description: Text("Add a display to start showing pages."))
                    }
                }
                .padding(16).frame(maxWidth: 1250).frame(maxWidth: .infinity)
            }
            .background(ShellPalette(appearance: appearance).background)
        }
        .navigationTitle("Home").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { displayMenu }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: compose) { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Compose").accessibilityIdentifier("homeCompose").disabled(!store.canWrite)
                Button { Task { await status.refreshHomeControlState() } } label: { Label("Refresh display", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing || store.commandBusy || status.homeControlBusy)
            }
        }
        .sheet(isPresented: $changingPage, onDismiss: { previewedPageID = nil }) {
            NavigationStack {
                HomeChangePageSheet(store: store, status: status, selected: $previewedPageID)
            }.presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if successToast, let outcome = status.homeControlOutcome {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.message).font(.subheadline.weight(.semibold))
                            Text(summary?.name ?? "Display").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if status.canUndoOverride {
                            Button("Undo") { Task { await status.undoTemporaryOverride() } }
                                .buttonStyle(.glass).controlSize(.large)
                                .accessibilityLabel("Undo override cancellation").accessibilityIdentifier("homeUndoOverride")
                        }
                    }
                    .padding(12).glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .padding(16).accessibilityIdentifier("homeSuccessToast")
                }
            }
        }
        .sensoryFeedback(.success, trigger: successToast) { _, value in value }
        .task(id: status.homeControlOutcome) {
            guard successfulHomeOutcome, let outcome = status.homeControlOutcome else { successToast = false; return }
            successToast = true
            UIAccessibility.post(notification: .announcement, argument: outcome.message + ". " + (summary?.name ?? "Display"))
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            successToast = false
        }
        .modifier(EditorPresentation(isPresented: $editing) {
            if let page = selectedPage { PageEditorLoader(pageID: page.id, store: store) }
        })
        .onChange(of: previewedPageID) { _, id in
            if let page = store.pages.first(where: { $0.id == id }) { thumbnails.request(page, boardID: store.selectedBoardID) }
        }
        .onChange(of: store.connectionLabel) { _, _ in changingPage = false; editing = false }
        .onChange(of: store.selectedBoardID) { _, _ in changingPage = false; editing = false }
    }
    private var successfulHomeOutcome: Bool {
        status.homeControlOutcome == .pageSelected || status.homeControlOutcome == .overrideCanceled || status.homeControlOutcome == .overrideRestored
    }
    private func homePresentation(now: Date) -> HomePresentation {
        HomePresentation.make(detail: store.board, showing: status.nowShowing, silence: status.selectedSilence,
            pageNames: Dictionary(store.pages.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }), now: now)
    }
    private var displayMenu: some View {
        Menu {
            Picker("Display", selection: Binding(get: { store.selectedBoardID ?? "" }, set: { store.selectBoard($0) })) {
                ForEach(store.boards) { Text($0.name).tag($0.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack { Text(summary?.name ?? "FiestaBoard").font(.subheadline.weight(.semibold)); Image(systemName: "chevron.up.chevron.down").font(.caption2) }
                Text(URL(string: store.connectionLabel)?.host ?? store.connectionLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .disabled(store.commandBusy || store.refreshing || store.boards.count < 2)
        .accessibilityIdentifier("homeDisplayPicker")
    }
    @ViewBuilder private func board(_ summary: BoardSummary, height: CGFloat) -> some View {
        let model = status.model(for: summary)
        Group {
            if previewPage != nil, let preview = selectedPreview, preview.available {
                BoardViewport(frame: PagePreviewFrame.make(preview, rows: model.rows, cols: model.cols, model: model), model: model)
            } else if let detail = store.board, detail.summary.id == summary.id {
                BoardOutputView(board: detail, model: model, animated: status.display.boardAnimations != false, flapStepMs: status.display.flapStepMs)
            } else {
                BoardFrameView(frame: .empty(rows: model.rows, cols: model.cols), model: model, animated: false, loading: !summary.paused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: max(220, height * 0.5))
        .accessibilityIdentifier("homeBoard").transaction { $0.animation = nil }
    }
    private func statusBanner(_ banner: HomeBanner) -> some View {
        Label(banner.title, systemImage: banner == .paused ? "pause.circle" : banner == .silenced ? "moon" : "wifi.exclamationmark")
            .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(ShellPalette(appearance: appearance).card, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier(banner == .paused ? "pausedBadge" : banner == .silenced ? "silenceBadge" : "displayOfflineBanner")
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
