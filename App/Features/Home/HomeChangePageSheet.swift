import SwiftUI
import FiestaBoardAppState

struct HomeChangePageSheet: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var status: BoardStatus
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: String?
    @State private var minutes = 0
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
                    .accessibilityLabel(page.name)
                    .accessibilityValue(selected == page.id ? "Selected" : "")
                }
            }
            if status.canSelectHomePage(timed: true) {
                Section("Duration") {
                    Picker("Show for", selection: $minutes) {
                        Text("Until changed").tag(0)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("3 hours").tag(180)
                    }.pickerStyle(.menu).accessibilityIdentifier("homePageDuration")
                }
            }
            if let outcome = status.homeControlOutcome {
                Section { Text(outcome.message).accessibilityIdentifier("homePageOutcome") }
            }
        }
        .searchable(text: $query, prompt: "Search pages")
        .navigationTitle("Change Page").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Show now") {
                    guard let selected else { return }
                    Task {
                        await status.selectHomePage(pageID: selected, durationMinutes: minutes == 0 ? nil : minutes)
                        if status.homeControlOutcome == .pageSelected { dismiss() }
                    }
                }
                .disabled(selected == nil || !status.canSelectHomePage(timed: minutes != 0))
                .accessibilityIdentifier("homeShowPage")
            }
        }
        .onChange(of: store.connectionLabel) { _, _ in dismiss() }
        .onChange(of: store.selectedBoardID) { _, _ in dismiss() }
    }
}
