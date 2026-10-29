import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState

@main struct FiestaBoardApp: App {
    private let connectionPersistence = ConnectionPersistence(
        directory: URL.applicationSupportDirectory.appendingPathComponent("FiestaBoard/Servers", isDirectory: true))
    var body: some Scene { WindowGroup { DraftScene(persistence: connectionPersistence) } }
}

// Select the standard property-wrapper type explicitly; SDK 27 also overloads @State as a macro.
private typealias DraftState<Value> = SwiftUI.State<Value>

enum DraftTab: Hashable { case home, library, displays, settings }

struct DraftScene: View {
    @StateObject private var store: BoardStore
    @StateObject private var connection: ConnectionModel
    init(persistence: ConnectionPersistence) {
        let store = BoardStore()
        _store = StateObject(wrappedValue: store)
        _connection = StateObject(wrappedValue: ConnectionModel(
            store: store, catalog: persistence.catalog, discovery: BonjourServerDiscovery(),
            preferences: .standard, serviceFactory: { LiveFiestaBoardService(deployment: $0, vault: KeychainSessionVault()) }))
    }
    @DraftState private var tab = DraftTab.home
    @DraftState private var search = ""
    @DraftState private var composing = false
    @DraftState private var textDraft = ""
    @DraftState private var reviewAfterCompose: PreparedAction?
    @DraftState private var pending: PreparedAction?
    @DraftState private var candidateWrites = false
    @DraftState private var started = false
    @DraftState private var demoMode = DemoSimulation.accepted
    private var demo: DemoFiestaBoardService? { connection.demoService }
    private let accent = Color.orange

    var body: some View {
        Group {
            if store.status == nil {
                ConnectionView(model: connection, store: store)
            } else {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house", value: .home) { home }
                    Tab("Library", systemImage: "square.grid.2x2", value: .library) { library }
                    Tab("Displays", systemImage: "rectangle.on.rectangle", value: .displays) { displays }
                    Tab("Settings", systemImage: "gearshape", value: .settings) { settings }
                }
                .tabViewStyle(.sidebarAdaptable)
            }
        }
        .tint(accent)
        .onChange(of: store.selectedBoardID) { _, id in
            if let id, connection.phase == .connected, !connection.busy { Task { await connection.persistPreferredBoard(id) } }
        }
        .onChange(of: store.status == nil) { _, disconnected in
            if disconnected && !store.connecting { connection.storeConnectionChanged(); candidateWrites = false }
        }
        .onChange(of: store.connecting) { _, connecting in
            if !connecting && store.status == nil { connection.storeConnectionChanged(); candidateWrites = false }
        }
        .sheet(isPresented: $composing, onDismiss: {
            if let action = reviewAfterCompose { reviewAfterCompose = nil; pending = action }
        }) {
            NavigationStack {
                Form {
                    Section("Message") {
                        TextEditor(text: $textDraft).frame(minHeight: 150).accessibilityLabel("Message text")
                    }
                    Section {
                        Text("Review captures this exact text and the selected board. Sending uses the server’s layout rules.")
                        Button("Review action") {
                            reviewAfterCompose = store.prepare(.text(textDraft))
                            if reviewAfterCompose != nil { composing = false }
                        }.disabled(!store.canWrite || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle(store.status?.isDemo == true ? "Simulate a message" : "Compose text")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { composing = false } } }
            }
        }
        .sheet(item: $pending) { action in
            NavigationStack {
                Form {
                    Section("Captured destination") {
                        LabeledContent("Server", value: action.isDemo ? "Demo · simulated" : action.target.deployment.description)
                        LabeledContent("Board", value: action.boardName)
                        LabeledContent("Board ID", value: action.target.boardID)
                    }
                    Section("Captured action") {
                        switch action.payload {
                        case .text(let value): Text(value).font(.body.monospaced()).textSelection(.enabled)
                        case .page(let id): LabeledContent("Select page", value: pageName(id))
                        case .configuration(let patch):
                            if let paused = patch.paused { LabeledContent("Updates", value: paused ? "Pause" : "Resume") }
                            if let enabled = patch.scheduleEnabled { LabeledContent("Schedule", value: enabled ? "Follow schedule" : "Off") }
                            if let enabled = patch.autoRestore { LabeledContent("Automatic restore", value: enabled ? "On" : "Off") }
                            switch patch.defaultPage {
                            case .omit: EmptyView()
                            case .clear: Text("Clear the fallback page")
                            case .set(let id): LabeledContent("Fallback page", value: pageName(id))
                            }
                        case .restore:
                            Text("Restore the content FiestaBoard currently intends to show. The pinned selection remains in place; pause and silence settings still apply.")
                        }
                        Text(action.isDemo ? "This action stays in memory and does not contact hardware." : "The server may send this to the board. An acknowledgement does not verify physical output.").foregroundStyle(.secondary)
                    }
                    Section {
                        Button(action.isDemo ? "Confirm simulated action" : "Confirm board action") {
                            store.confirm(action); pending = nil
                        }.disabled(!store.canWrite)
                    }
                }
                .navigationTitle("Review action")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pending = nil } } }
            }
        }
        .task {
            guard !started else { return }; started = true
            await connection.start(demo: ProcessInfo.processInfo.arguments.contains("--demo")).value
        }
    }

    private var connectionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.connectionLabel, systemImage: store.status?.isDemo == true ? "sparkles" : "network")
                .font(.subheadline.weight(.semibold)).textSelection(.enabled)
            Text(store.status?.isDemo == true ? "Demo · page saves, previews and board actions are simulated" : "\(store.status?.version.displayedVersion ?? "Unknown version") · \(store.status?.access == .candidateWrites ? "Board controls enabled" : "Board controls read-only") · Page and collection editing checked separately")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.message {
                Text(message).font(.callout).accessibilityIdentifier("actionOutcome")
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if store.commandBusy || store.refreshing { ProgressView(store.commandBusy ? "Waiting for server…" : "Refreshing…") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var home: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        connectionBanner
                        let wide = geometry.size.width > 760
                        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
                        layout {
                            VStack(alignment: .leading, spacing: 16) {
                                boardPicker
                                if let board = store.board {
                                    Text("Server-reported output").font(.headline)
                                    BoardOutputView(board: board)
                                    Text("Reported content may be cached. This is not independent physical readback.").font(.caption).foregroundStyle(.secondary)
                                    if let date = board.readAt { Text("Server read: \(date)").font(.caption).foregroundStyle(.secondary) }
                                    if board.expectedCharacters != nil && board.expectedCharacters != board.characters {
                                        DisclosureGroup("Expected output differs") { BoardOutputView(board: board, expected: true) }
                                    }
                                } else if store.boards.isEmpty {
                                    ContentUnavailableView("No displays", systemImage: "rectangle.on.rectangle", description: Text("Add a display in the server web interface, then reconnect to load it here."))
                                }
                            }.frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Make room for a little joy.", systemImage: "sun.max").font(.title2.bold())
                                Button { composing = true } label: { Label("Compose text", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 36) }
                                    .buttonStyle(.borderedProminent).disabled(!store.canWrite)
                                if store.status?.access == .readOnly { Text("Board controls are read-only. Settings explains their exact version gate; page saves have a separate protocol check.").font(.callout).foregroundStyle(.secondary) }
                                if store.needsReadback { Text("Refresh output before another action.").font(.callout).foregroundStyle(.orange) }
                                if let board = store.board {
                                    selectionDetails(board)
                                    NavigationLink { pageChooser } label: { Label("Choose a page", systemImage: "rectangle.stack") }
                                        .buttonStyle(.bordered).disabled(!store.canWrite)
                                    NavigationLink {
                                        boardControlsDestination
                                    } label: { Label("Board controls", systemImage: "slider.horizontal.3") }
                                        .buttonStyle(.bordered)
                                        .accessibilityIdentifier("boardControlsEntry")
                                }
                            }.frame(maxWidth: wide ? 290 : .infinity, alignment: .leading)
                        }
                    }.padding().frame(maxWidth: 1250).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("FiestaBoard")
            .toolbar { ToolbarItem(placement: .primaryAction) { refreshButton } }
        }
    }
    private var boardControlsDestination: some View {
        Form {
            Section("Connection & action status") {
                connectionBanner
                if store.status?.access == .readOnly {
                    Text("Board controls are read-only. Settings explains their exact server version gate and session opt-in. Supported page saves are checked separately.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Read current board state") {
                if store.needsReadback && !store.commandBusy {
                    Text("Refresh the board state before another action. Refresh reads current state and never repeats the previous action.")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("controlReadbackPrompt")
                }
                Button("Refresh board state") { store.refresh() }
                    .disabled(store.refreshing || store.commandBusy || store.connecting || store.status == nil || store.selectedBoardID == nil)
                    .accessibilityIdentifier("refreshBoardControls")
            }
            BoardControlsView(store: store)
        }
        .navigationTitle("Board controls")
    }
    private var boardPicker: some View {
        Picker("Display", selection: Binding(get: { store.selectedBoardID ?? "" }, set: { store.selectBoard($0) })) {
            ForEach(store.boards) { Text($0.name).tag($0.id) }
        }.pickerStyle(.menu).disabled(store.commandBusy || store.refreshing)
    }
    private var refreshButton: some View {
        Button { store.refresh() } label: { Label("Refresh output", systemImage: "arrow.clockwise") }
            .disabled(store.refreshing || store.commandBusy)
    }
    private func selectionDetails(_ board: BoardDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selection & delivery").font(.headline)
            LabeledContent("Selected page", value: pageName(board.activePageID))
            LabeledContent("Resolved page", value: pageName(board.resolvedPageID))
            LabeledContent("Scheduled page", value: pageName(board.scheduledPageID))
            LabeledContent("Source", value: board.source)
        }.font(.subheadline)
    }
    private var library: some View {
        NavigationStack {
            List {
                Section { connectionBanner }
                Section {
                    NavigationLink { CollectionsView(store: store) } label: {
                        Label("Collections", systemImage: "rectangle.stack.fill")
                    }
                    .accessibilityIdentifier("openCollections")
                }
                Section("Pages · local drafts available") {
                    ForEach(store.pages.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { page in
                        NavigationLink { PageDetailView(page: page, store: store, prepare: { pending = store.prepare(.page(page.id)) }) } label: {
                            Label { VStack(alignment: .leading, spacing: 4) { Text(page.name).font(.headline); Text("\(page.type) · \(page.deviceType)").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "rectangle.stack").foregroundStyle(.orange) }.padding(.vertical, 6)
                        }
                    }
                    if store.pages.isEmpty { Text("No pages on this deployment.") }
                }
            }.navigationTitle("Library").searchable(text: $search, prompt: "Find a page")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button("Reload library") { store.refreshLibrary() }.disabled(store.connecting) } }
        }
    }
    private var pageChooser: some View {
        List(store.pages) { page in
            Button { pending = store.prepare(.page(page.id)) } label: { Label(page.name, systemImage: "rectangle.stack") }
                .disabled(!store.canWrite)
        }.navigationTitle("Show on selected board")
    }
    private var displays: some View {
        NavigationStack {
            List {
                Section { connectionBanner }
                Section("Displays") {
                    ForEach(store.boards) { board in
                        NavigationLink {
                            Form {
                                Section("Display") {
                                    LabeledContent("Name", value: board.name)
                                    LabeledContent("ID", value: board.id)
                                    LabeledContent("Geometry", value: "\(board.rows) × \(board.cols)")
                                    LabeledContent("Device model", value: board.deviceModel ?? "Not reported")
                                    LabeledContent("Character set", value: board.charset ?? "Not reported")
                                    LabeledContent("Schedule", value: board.scheduleEnabled ? "Enabled" : "Disabled")
                                    LabeledContent("Paused", value: board.paused ? "Yes" : "No")
                                }
                                Section { Button("Use this display") { store.selectBoard(board.id); tab = .home }.disabled(store.commandBusy) }
                            }.navigationTitle(board.name)
                        } label: {
                            HStack { Label(board.name, systemImage: "rectangle.on.rectangle"); Spacer(); if store.selectedBoardID == board.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("Selected") } }
                        }
                    }
                    if store.boards.isEmpty { Text("No displays reported by this server.") }
                }
            }.navigationTitle("Displays")
        }
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    connectionBanner
                    LabeledContent("Version", value: store.status?.version.displayedVersion ?? "Unknown")
                    LabeledContent("Board controls", value: store.status?.access.rawValue ?? "Disconnected")
                    Text("Passwords are never saved. Disconnect clears this window’s active session. Remembered sign-in stays securely stored until you forget it or log out.").font(.footnote).foregroundStyle(.secondary)
                    Button("Disconnect") { connection.disconnect(); candidateWrites = false }
                    if store.status?.isDemo != true {
                        Button("Forget remembered sign-in") { Task { await connection.forgetSignIn() } }
                        if let warning = connection.persistence.warning {
                        Text(warning == .remoteRevocationPending ? "Remote sign-out is still pending. Sign out in the server web interface if needed." : "Remembered sign-in needs attention. Sign in again or forget the saved session.").font(.footnote).foregroundStyle(.orange)
                    }
                        Button("Log out & disconnect") { connection.logout(); candidateWrites = false }
                    }
                }
                if !store.logoutNotices.isEmpty {
                    Section("Sign-out status") {
                        ForEach(store.logoutNotices) { notice in Text(notice.message).font(.footnote) }
                    }
                }
                if store.status?.isDemo == true {
                    Section("Simulate an outcome") {
                        Picker("Next action", selection: $demoMode) { ForEach(DemoSimulation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            .accessibilityIdentifier("demoOutcomePicker")
                        Text("Demonstrate board outcomes without hardware. For page saves, Rejected simulates a revision conflict; Unknown and Partial simulate an uncertain save result.").font(.footnote)
                    }.onChange(of: demoMode) { _, value in if let demo { Task { await demo.setSimulation(value) } } }
                } else {
                    Section("Server changes") {
                        Toggle("Enable changes on this server", isOn: $candidateWrites)
                        DisclosureGroup("Compatibility details") { Text("Applying reconnects. With this setting enabled, this session opts into supported page saves, collection editing and board controls. Collection creation supports the audited 10.1.7 candidate; editing existing collections requires collection-revision-v1 and the original revision. Page saves require the exact page-revision-v1 protocol and a loaded revision; each save needs confirmation. Board controls separately require the exact non-development FiestaBoard 10.0.0 version and can change the chosen board. Other versions may support page saves while board controls remain read-only. This draft has no supported release pairing.").font(.footnote) }
                        Button("Apply change setting") { store.reconnect(allowCandidateWrites: candidateWrites) }.disabled(store.commandBusy || store.connecting)
                    }
                }
                Section("About this draft") {
                    DraftScopeView()
                    NavigationLink("Open-source notices") {
                        ScrollView { Text(licenseText).font(.footnote.monospaced()).padding().textSelection(.enabled) }.navigationTitle("Notices")
                    }
                }
            }.navigationTitle("Settings")
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "FiestaBoardTV-MIT", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "FiestaBoard TV mapping · MIT license. See ThirdPartyNotices in the source distribution." }
        return text
    }
    private func pageName(_ id: String?) -> String {
        guard let id else { return "None reported" }
        return store.pages.first(where: { $0.id == id })?.name ?? id
    }
}

private struct DraftScopeView: View {
    var body: some View {
        Text("Native draft: manual connection, page library, on-device drafts, supported page name and fixed template edits, explicit template validation and text preview, revision-checked server page saves, display selection, text and page actions, pause, schedule following, fallback page and restore controls. Refresh is manual; there is no background polling. Demo saves, evaluations and board actions are entirely simulated.")
        Text("Save local draft keeps a recovery copy on this device. A separate confirmed server save updates supported stored page fields when the server advertises the known page protocol and this session opts in. Native discovery, sign-in and initial server setup are available as a testable draft. Collections support revision-checked editing where available. Rich split-flap and LED editing, canvas editing, OAuth, schedule editing, plugins, administration and pixel rendering remain planned. Use the web interface for those features and full visual previews.")
        Text("No supported release pairing or full web/TV renderer parity is claimed.").font(.footnote).foregroundStyle(.secondary)
    }
}
