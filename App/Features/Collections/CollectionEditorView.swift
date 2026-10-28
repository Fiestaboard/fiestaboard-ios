import SwiftUI
import FiestaBoardKit
import FiestaBoardEditorState

private typealias CollectionFormState<Value> = SwiftUI.State<Value>

@MainActor struct CollectionEditorView: View {
    @ObservedObject var model: CollectionEditorModel
    let pages: [Page]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @CollectionFormState private var confirmClose = false
    @CollectionFormState private var confirmSave = false
    @CollectionFormState private var confirmDelete = false
    @CollectionFormState private var confirmAdopt = false
    @CollectionFormState private var pageSearch = ""

    var body: some View {
        Form {
            Section {
                if model.isSimulated { Label("Demo · simulated", systemImage: "play.rectangle") }
                Text(model.deploymentID).font(.caption).textSelection(.enabled)
                Text(model.collectionID.map { "Collection ID: \($0)" } ?? "New collection").font(.caption).textSelection(.enabled)
                Text("Changes are checkpointed on this device. Server saves acknowledge storage; they do not confirm display output or select a board.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            recoverySection
            Group {
                Section("Name and selection") {
                    TextField("Collection name", text: text(\.name)).autocorrectionDisabled()
                        .accessibilityIdentifier("collectionName")
                    if CollectionSelectionMode(rawValue: model.draft.selectionMode) != nil {
                        Picker("Selection mode", selection: text(\.selectionMode)) {
                            Text("Time").tag("time"); Text("Variable").tag("variable"); Text("Random").tag("random")
                        }
                    } else { LabeledContent("Selection mode", value: model.draft.selectionMode) }
                }
                membersSection
                membershipSection
                timingSection
                if model.draft.selectionMode == "variable" { rulesSection }
            }.disabled(model.editingFrozen || !model.supportsEditing)
            storageSection
            if let message = model.message { Section { Text(message).foregroundStyle(.secondary).textSelection(.enabled) } }
        }
        .navigationTitle(model.collectionID == nil ? "New collection" : "Collection editor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(model.hasChanges || model.editingFrozen)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if model.hasChanges { confirmClose = true }
                    else if model.closeKeepingDraft() { dismiss() }
                }.disabled(model.editingFrozen)
            }
            ToolbarItem(placement: .primaryAction) { EditButton().disabled(model.editingFrozen || !model.supportsEditing) }
        }
        .confirmationDialog("Keep this collection draft?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Keep local draft and close") { if model.closeKeepingDraft() { dismiss() } }
            Button("Discard draft and close", role: .destructive) { model.discard(); if model.status == .ended { dismiss() } }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog(model.isSimulated ? "Simulate storing this collection?" : "Store this collection on the server?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button(model.isSimulated ? "Simulate save" : "Save collection") { Task { await model.save() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Save ‘\(model.draft.name)’ on \(model.deploymentID). This changes collection storage; it does not select content for a board.") }
        .confirmationDialog("Delete this stored collection?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                Task { await model.delete(); if model.status == .ended { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Delete ‘\(model.draft.name)’ on \(model.deploymentID). The server will refuse deletion if the collection is still in use.") }
        .confirmationDialog("Adopt the compared server collection?", isPresented: $confirmAdopt, titleVisibility: .visible) {
            Button("Preserve draft and adopt server content", role: .destructive) { model.adoptComparison() }
            Button("Keep editing local draft", role: .cancel) {}
        } message: { Text("Your local draft remains preserved. The editor will use the compared content and its revision.") }
        .task { model.checkRecovery() }
        .onChange(of: scenePhase) { _, phase in if phase != .active && model.hasChanges { model.preserve() } }
        .onDisappear { if model.hasChanges { model.preserve() } }
    }

    private func text(_ key: WritableKeyPath<CollectionDraft, String>) -> Binding<String> {
        Binding(get: { model.draft[keyPath: key] }, set: { value in model.edit { $0[keyPath: key] = value } })
    }
    @ViewBuilder private var recoverySection: some View {
        if model.canRecover {
            Section("Recovered local drafts") {
                Text("Recovery restores the saved original baseline and revision. It does not merge into this fetched collection or send changes.").font(.footnote)
                ForEach(model.recovery) { draft in
                    Button("Recover ‘\(draft.draft.name)’ · \(draft.savedAt.formatted(date: .abbreviated, time: .shortened))") {
                        model.recoverDraft(id: draft.id)
                    }.disabled(model.hasChanges || model.editingFrozen)
                }
                Button("Keep fetched collection") { model.dismissRecovery() }
            }
        }
    }
    private var membersSection: some View {
        Section("Ordered member pages") {
            if model.draft.pageIDs.isEmpty { Text("Choose at least one page below.").foregroundStyle(.secondary) }
            ForEach(Array(model.draft.pageIDs.enumerated()), id: \.element) { index, id in
                VStack(alignment: .leading) {
                    Text("\(index + 1). \(pageName(id))")
                    Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    VStack(alignment: .leading) {
                        Button("Move up", systemImage: "arrow.up") { moveMember(index, by: -1) }.disabled(index == 0)
                        Button("Move down", systemImage: "arrow.down") { moveMember(index, by: 1) }.disabled(index == model.draft.pageIDs.count - 1)
                        Button("Remove", role: .destructive) { model.edit { $0.pageIDs.removeAll { $0 == id } } }
                    }.font(.caption).buttonStyle(.borderless)
                }
            }
            .onMove { source, target in model.edit { $0.pageIDs.move(fromOffsets: source, toOffset: target) } }
            Text("Member order is preserved. Removing a member may require updating rule targets or the fallback page.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var membershipSection: some View {
        Section("Add member pages") {
            TextField("Find pages", text: $pageSearch)
            if pages.isEmpty { Text("Create a page in Library before adding collection members.").foregroundStyle(.secondary) }
            ForEach(pages.filter { !model.draft.pageIDs.contains($0.id) && (pageSearch.isEmpty || $0.name.localizedStandardContains(pageSearch) || $0.id.localizedStandardContains(pageSearch)) }) { page in
                Button { model.edit { $0.pageIDs.append(page.id) } } label: { Label(page.name, systemImage: "plus.circle") }
            }
        }
    }
    private var timingSection: some View {
        Section("Timing and configuration") {
            TextField("Time interval (seconds)", text: text(\.intervalText)).keyboardType(.numbersAndPunctuation)
                .accessibilityLabel("Time interval in seconds, 5 through 86400")
            if model.draft.selectionMode == "random" || model.draft.hasRandomConfig {
                TextField("Random interval (seconds)", text: text(\.randomIntervalText)).keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel("Random interval in seconds, 5 through 86400")
            }
            Text("Intervals range from 5 to 86400 seconds. Expressions are evaluated by the server.").font(.footnote).foregroundStyle(.secondary)
            if model.draft.selectionMode != "variable", model.draft.hasVariableConfig {
                Text("Variable configuration is retained while another mode is selected.").font(.footnote)
                Button("Clear retained variable configuration", role: .destructive) { model.edit { $0.hasVariableConfig = false } }
            }
            if model.draft.selectionMode != "random", model.draft.hasRandomConfig {
                Text("Random configuration is retained while another mode is selected.").font(.footnote)
                Button("Clear retained random configuration", role: .destructive) { model.edit { $0.hasRandomConfig = false } }
            }
        }
    }
    private var rulesSection: some View {
        Section("Variable rules · evaluated in order") {
            TextField("Poll interval (seconds)", text: text(\.pollText)).keyboardType(.numbersAndPunctuation)
                .accessibilityLabel("Poll interval in seconds, 2 through 600")
            pagePicker("Fallback page", selection: text(\.defaultPageID))
            ForEach(Array(model.draft.rules.enumerated()), id: \.offset) { index, rule in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rule \(index + 1)").font(.headline)
                    TextField("Expression", text: Binding(get: { model.draft.rules.indices.contains(index) ? model.draft.rules[index].expression : "" }, set: { value in
                        model.edit { guard $0.rules.indices.contains(index) else { return }; $0.rules[index] = .init(expression: value, pageID: $0.rules[index].pageID) }
                    }), axis: .vertical).accessibilityLabel("Rule \(index + 1) expression").autocorrectionDisabled().textInputAutocapitalization(.never)
                    pagePicker("Rule \(index + 1) page", selection: Binding(get: { model.draft.rules.indices.contains(index) ? model.draft.rules[index].pageID : "" }, set: { value in
                        model.edit { guard $0.rules.indices.contains(index) else { return }; $0.rules[index] = .init(expression: $0.rules[index].expression, pageID: value) }
                    }))
                    VStack(alignment: .leading) {
                        Button("Move up", systemImage: "arrow.up") { moveRule(index, by: -1) }.disabled(index == 0)
                        Button("Move down", systemImage: "arrow.down") { moveRule(index, by: 1) }.disabled(index == model.draft.rules.count - 1)
                        Button("Remove rule", role: .destructive) { model.edit { if $0.rules.indices.contains(index) { $0.rules.remove(at: index) } } }
                    }.font(.caption).buttonStyle(.borderless)
                }
            }.onMove { source, target in model.edit { $0.rules.move(fromOffsets: source, toOffset: target) } }
            Button("Add rule", systemImage: "plus") { model.edit { $0.rules.append(.init(expression: "", pageID: $0.pageIDs.first ?? "")) } }
        }
    }
    private func pagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Choose a member page").tag("")
            if !selection.wrappedValue.isEmpty, !model.draft.pageIDs.contains(selection.wrappedValue) {
                Text("Unavailable: \(selection.wrappedValue)").tag(selection.wrappedValue)
            }
            ForEach(model.draft.pageIDs, id: \.self) { id in Text(pageName(id)).tag(id) }
        }
    }
    private var storageSection: some View {
        Section("Stored collection") {
            if let reason = model.disabledReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            if let issue = model.validationMessage { Text(issue).font(.footnote).foregroundStyle(.secondary) }
            Button(model.isSimulated ? "Simulate saving collection…" : "Save collection on server…") { confirmSave = true }
                .disabled(!model.canSave).accessibilityIdentifier("saveCollection")
            if model.collectionID != nil {
                Button("Compare server collection") { Task { await model.compare() } }.disabled(!model.canCompare)
                Button("Delete collection…", role: .destructive) { confirmDelete = true }.disabled(!model.canDelete)
            } else if model.status == .unknownOutcome {
                Button("Keep draft and review collection list") { if model.closeKeepingDraft() { dismiss() } }
            }
            if model.editingFrozen { ProgressView("Preserving draft or contacting server…") }
            DisclosureGroup("Local draft and original baseline · select to copy") {
                Text(model.localCopyText).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink("Export local draft", item: model.localCopyText)
            }
            if let comparison = model.comparisonText {
                DisclosureGroup("Compared server collection") { Text(comparison).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Adopt compared server content…") { confirmAdopt = true }.disabled(model.status != .comparison)
            }
        }
    }
    private func pageName(_ id: String) -> String { pages.first { $0.id == id }?.name ?? "Unavailable page · \(id)" }
    private func moveMember(_ index: Int, by delta: Int) {
        model.edit { if $0.pageIDs.indices.contains(index), $0.pageIDs.indices.contains(index + delta) { $0.pageIDs.swapAt(index, index + delta) } }
    }
    private func moveRule(_ index: Int, by delta: Int) {
        model.edit { if $0.rules.indices.contains(index), $0.rules.indices.contains(index + delta) { $0.rules.swapAt(index, index + delta) } }
    }
}
