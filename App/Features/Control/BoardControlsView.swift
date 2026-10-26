import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

private typealias ControlState<Value> = SwiftUI.State<Value>

/// Embed inside a Form/List using the same store as Home or Display detail.
@MainActor struct BoardControlsView: View {
    @ObservedObject var store: BoardStore
    @ControlState private var pending: PreparedAction?

    var body: some View {
        Section("Board controls") {
            if let detail = store.board {
                LabeledContent("Board", value: detail.summary.name)
                LabeledContent("Updates", value: detail.summary.paused ? "Paused" : "Running")
                Button(detail.summary.paused ? "Resume updates" : "Pause updates") {
                    pending = store.prepare(.configuration(BoardPatch(paused: !detail.summary.paused)))
                }
                Button(detail.summary.scheduleEnabled ? "Turn schedule off" : "Follow schedule") {
                    pending = store.prepare(.configuration(BoardPatch(scheduleEnabled: !detail.summary.scheduleEnabled)))
                }
                LabeledContent("Schedule", value: detail.summary.scheduleEnabled ? "On" : "Off")
                if let autoRestore = detail.summary.autoRestore {
                    Button(autoRestore ? "Let other apps keep the board" : "Automatically restore board content") {
                        pending = store.prepare(.configuration(BoardPatch(autoRestore: !autoRestore)))
                    }
                }
                Menu {
                    Button("Clear fallback page") {
                        pending = store.prepare(.configuration(BoardPatch(defaultPage: .clear)))
                    }
                    ForEach(store.pages) { page in
                        Button(page.name) {
                            pending = store.prepare(.configuration(BoardPatch(defaultPage: .set(page.id))))
                        }
                    }
                } label: {
                    LabeledContent("Fallback page", value: defaultPageName(detail.defaultPageID))
                }
                Button("Restore board content") { pending = store.prepare(.restore) }
                Text("Restore follows the current schedule, timed message or pinned page. It keeps the pinned selection and respects pause and silence settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Select a board to read its current settings.")
            }
        }
        .disabled(!store.canWrite)
        .confirmationDialog("Confirm board change", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), presenting: pending) { action in
            Button("Confirm") { store.confirm(action); pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { action in
            Text(confirmation(action))
        }
    }

    private func defaultPageName(_ id: String?) -> String {
        guard let id else { return "None" }
        return store.pages.first(where: { $0.id == id })?.name ?? id
    }
    private func confirmation(_ action: PreparedAction) -> String {
        let change: String
        switch action.payload {
        case .configuration(let patch):
            if let paused = patch.paused { change = paused ? "Pause all updates" : "Resume updates" }
            else if let enabled = patch.scheduleEnabled { change = enabled ? "Follow the schedule" : "Turn off the schedule" }
            else if let enabled = patch.autoRestore { change = enabled ? "Automatically restore content after another app writes" : "Let another app keep its content" }
            else {
                switch patch.defaultPage {
                case .clear: change = "Clear the fallback page"
                case .set(let id): change = "Use \(defaultPageName(id)) when the schedule has a gap"
                case .omit: change = "Update settings"
                }
            }
        case .restore: change = "Restore the content FiestaBoard currently intends to show"
        case .text, .page: change = "Change content"
        }
        return "\(action.isDemo ? "Simulated — " : "")\(change) on \(action.boardName) at \(action.target.deployment.description)?"
    }
}
