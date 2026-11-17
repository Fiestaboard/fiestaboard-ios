import SwiftUI
import FiestaBoardAppState
import FiestaBoardKit

struct HomeChangePageSheet: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @Binding var selected: String?
    @State private var minutes = 0
    @State private var expiredBoundary = false
    private var scheduledEnd: Date? {
        guard status.selectedOverride?.active != true, store.board?.overrideStartedAt == nil, store.board?.nextChangeReason == "schedule",
              let end = HomeTiming.instant(store.board?.nextChangeAt), HomeTiming.durationMinutes(until: end, now: Date()) != nil else { return nil }
        return end
    }
    private var choices: [Int] { [15, 60, scheduledEnd == nil ? 180 : -2, -1] }
    private func label(_ value: Int) -> String {
        if value == -2, let end = scheduledEnd { return "Until \(end.formatted(date: .omitted, time: .shortened))" }
        switch value { case 15: return "15 min"; case 60: return "1 hr"; case 180: return "3 hr"; case -1: return "Until I cancel"; default: return "Until changed" }
    }
    private var confirmationTitle: String {
        if minutes == -1 { return "Override until I cancel" }
        if minutes == -2, let end = scheduledEnd { return "Override until \(end.formatted(date: .omitted, time: .shortened))" }
        return minutes == 0 ? "Show now" : "Override for \(minutes) min"
    }
    private func fits(_ page: Page) -> Bool {
        guard let geometry = PageGeometry(page), let summary = store.boards.first(where: { $0.id == store.selectedBoardID }) else { return true }
        return geometry.fits(status.model(for: summary))
    }
    private var canSubmit: Bool {
        guard let page = store.pages.first(where: { $0.id == selected }), fits(page) else { return false }
        if minutes == -1 { return status.canHoldHomePage }
        if minutes == -2 && scheduledEnd == nil { return false }
        return status.canSelectHomePage(timed: minutes != 0)
    }
    var body: some View {
        List {
            Section {
                ForEach(store.pages.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { page in
                    Button { selected = page.id } label: {
                        HStack {
                            Text(page.name).foregroundStyle(.primary)
                            Spacer()
                            if selected == page.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .disabled(!fits(page) || status.homeControlBusy || status.homeControlNeedsReadback)
                    .accessibilityHint(fits(page) ? "" : "This page uses a different display size")
                    .accessibilityLabel(page.name)
                    .accessibilityValue(selected == page.id ? "Selected" : "")
                }
            }
            if store.supportsHomeControl(.timedOverride) {
                Section("Duration") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(choices, id: \.self) { duration in
                            Button { minutes = duration; expiredBoundary = false } label: {
                                HStack { if minutes == duration { Image(systemName: "checkmark") }; Text(label(duration)) }
                                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 4)
                            }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            .disabled(status.homeControlBusy || status.homeControlNeedsReadback)
                            .accessibilityValue(minutes == duration ? "Selected" : "")
                            .accessibilityIdentifier("homePageDuration-\(duration)")
                        }
                    }
                }
            }
            if expiredBoundary { Text("That scheduled change has passed. Choose another duration.").font(.callout) }
            if status.homeControlNeedsReadback {
                Button("Refresh display") { Task { await status.refreshHomeControlState() } }.disabled(!store.networkAvailable)
            }
            if let outcome = status.homeControlOutcome, outcome != .pageSelected && outcome != .overrideCanceled {
                Section { Text(outcome.message).accessibilityIdentifier("homePageOutcome") }
            }
        }
        .searchable(text: $query, prompt: "Search pages")
        .navigationTitle("Change Page").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard let selected else { return }
                Task {
                    if minutes == -1 { await status.holdHomePage(pageID: selected) }
                    else if minutes == -2 {
                        guard let end = scheduledEnd, let duration = HomeTiming.durationMinutes(until: end, now: Date()) else { expiredBoundary = true; return }
                        await status.selectHomePage(pageID: selected, durationMinutes: duration)
                    }
                    else { await status.selectHomePage(pageID: selected, durationMinutes: minutes == 0 ? nil : minutes) }
                    if status.homeControlOutcome == .pageSelected { dismiss() }
                }
            } label: { Text(confirmationTitle).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!canSubmit)
            .accessibilityIdentifier("homeShowPage").padding()
        }
        .onAppear {
            if store.board?.summary.scheduleEnabled == true && status.canSelectHomePage(timed: true) { minutes = scheduledEnd == nil ? 15 : -2 }
        }
        .onChange(of: store.connectionLabel) { _, _ in dismiss() }
        .onChange(of: store.selectedBoardID) { _, _ in dismiss() }
    }
}
