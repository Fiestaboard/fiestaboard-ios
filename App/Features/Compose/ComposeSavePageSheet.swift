import SwiftUI
import FiestaBoardAppState
import FiestaBoardDocuments

struct ComposeSavePageSheet: View {
    @State var name: String
    let descriptor: ComposeBufferTarget?
    @ObservedObject var store: BoardStore
    let save: (String) async -> Bool
    @State private var working = false
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Page name") {
                    TextField("Page name", text: $name).accessibilityIdentifier("composePageName")
                }
                Section {
                    if let descriptor { LabeledContent("Display type", value: "\(descriptor.deviceType.capitalized) · \(descriptor.cols) × \(descriptor.rows)") }
                    LabeledContent("Add to a Collection", value: "None")
                    Text("Saving doesn’t change what’s showing or your Schedule. Find it in Pages.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let issue { Text(issue).font(.callout) }
                if let message = store.pageLibrary?.phase.message { Text(message).font(.callout) }
                if working { ProgressView("Saving Page…") }
            }
            .navigationTitle("Save as Page").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        working = true
                        Task {
                            let created = await save(name)
                            working = false
                            if created { dismiss() }
                            else { issue = "Page creation is not confirmed. Your draft is kept. Review Pages before trying another request." }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canSaveComposePage)
                    .accessibilityIdentifier("composeSavePage")
                }
            }
        }
        .interactiveDismissDisabled(working)
        .presentationDetents([.medium, .large])
        .presentationSizing(.form)
    }
}
