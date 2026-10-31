import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

@MainActor struct SchedulesView: View {
    @ObservedObject var store: BoardStore
    var body: some View {
        List {
            Section {
                Picker("Display", selection: Binding(get: { store.selectedBoardID ?? "" }, set: { store.selectBoard($0) })) {
                    ForEach(store.boards) { Text($0.name).tag($0.id) }
                }.disabled(store.commandBusy || store.refreshing)
                Text(store.status?.isDemo == true ? "Demo · simulated schedule data · read only" : "Server schedule · read only")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.schedulesLoading { ProgressView("Reading schedule…") }
            if let message = store.scheduleMessage {
                Section { Text(message); Button("Try reading again") { store.refreshSchedules() } }
            }
            if let list = store.scheduleList, store.scheduleTarget?.boardID == store.selectedBoardID {
                Section("Server schedule state") {
                    LabeledContent("Following schedule", value: list.enabled.map { $0 ? "Enabled" : "Disabled" } ?? "Not reported")
                    LabeledContent("Fallback page", value: pageName(list.defaultPageID))
                    Text("Times, recurrence and dates use the server’s settings. This app does not convert them to your device’s time zone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Entries · \(list.total)") {
                    ForEach(list.schedules) { entry in
                        NavigationLink {
                            ScheduleDetailView(entry: entry, pageName: pageName(entry.pageID))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pageName(entry.pageID))
                                Text("\(entry.startTime) – \(entry.endTime ?? "Open-ended") · \(entry.dayPattern)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if !entry.enabled { Text("Disabled").font(.caption) }
                            }
                        }.accessibilityIdentifier("schedule-" + entry.id)
                    }
                    if list.schedules.isEmpty { Text("No schedule entries reported for this display.") }
                }
            }
        }
        .navigationTitle("Schedule")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button("Read schedule", systemImage: "arrow.clockwise") { store.refreshSchedules() }
                .disabled(store.schedulesLoading || store.connecting || store.selectedBoardID == nil)
                .accessibilityIdentifier("refreshSchedules")
        } }
        .task(id: store.selectedBoardID) { await store.refreshSchedules().value }
        .refreshable { await store.refreshSchedules().value }
    }
    private func pageName(_ id: String?) -> String {
        guard let id else { return "None reported" }
        return store.pages.first(where: { $0.id == id })?.name ?? id
    }
}

private struct ScheduleDetailView: View {
    let entry: ScheduleEntry
    let pageName: String
    var body: some View {
        Form {
            Section("Server time semantics") {
                Text("Read-only values from the server. Resolved times are the server’s calculation for today; no device time zone or recurrence conversion is applied.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Page", value: pageName)
                LabeledContent("Enabled", value: entry.enabled ? "Yes" : "No")
                LabeledContent("Start", value: entry.startTime)
                LabeledContent("End", value: entry.endTime ?? "Open-ended")
                LabeledContent("Recurrence", value: entry.recurrenceType ?? "Not reported")
                LabeledContent("Day pattern", value: entry.dayPattern)
                if let days = entry.customDays { LabeledContent("Custom days", value: days.joined(separator: ", ")) }
                optional("Annual date", entry.annualDate)
                optional("Annual end date", entry.annualEndDate)
                optional("One-off date", entry.oneOffDate)
                optional("One-off end date", entry.oneOffEndDate)
            }
            Section("Sun and resolved times") {
                LabeledContent("Start type", value: entry.startType ?? "Not reported")
                LabeledContent("End type", value: entry.endType ?? "Not reported")
                if let offset = entry.startSunOffset { LabeledContent("Start offset (minutes)", value: String(offset)) }
                if let offset = entry.endSunOffset { LabeledContent("End offset (minutes)", value: String(offset)) }
                LabeledContent("Resolved start", value: entry.resolvedStartTime ?? "Not reported")
                LabeledContent("Resolved end", value: entry.resolvedEndTime ?? "Open-ended or not reported")
            }
            Section("Source") {
                LabeledContent("Schedule ID", value: entry.id)
                LabeledContent("Board ID", value: entry.boardID.flatMap { $0.isEmpty ? nil : $0 } ?? "Server default board")
                optional("Revision", entry.revision)
                optional("Edit protocol", entry.editProtocol)
                optional("Created", entry.createdAt)
                optional("Updated", entry.updatedAt)
                Text("Schedule editing is not available in this native draft.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 900).frame(maxWidth: .infinity)
        .navigationTitle("Schedule entry")
    }
    @ViewBuilder private func optional(_ title: String, _ value: String?) -> some View {
        if let value { LabeledContent(title, value: value) }
    }
}
